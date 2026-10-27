import * as admin from 'firebase-admin';

/** Firebase Auth accepts up to 100 identifiers per lookup. */
const AUTH_LOOKUP_LIMIT = 100;
/** FCM accepts up to 500 tokens per multicast send. */
const FCM_BATCH_LIMIT = 500;

/** FCM codes that mean a token will never work again, so it should be removed. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** One device to push to, and the document holding its token. */
export interface PushTarget {
  token: string;
  ref: admin.firestore.DocumentReference;
}

/** Emails of the tour's active members, except [exceptEmail], lower-cased. */
export async function activeMemberEmails(tourId: string, exceptEmail: string): Promise<string[]> {
  const rows = await admin
    .firestore()
    .collection('memberships')
    .where('tourId', '==', tourId)
    .where('status', '==', 'active')
    .get();

  const emails = new Set<string>();
  for (const row of rows.docs) {
    const email = String(row.data().email ?? '').trim().toLowerCase();
    if (email !== '' && email !== exceptEmail) emails.add(email);
  }
  return [...emails];
}

/** Firebase user IDs for the emails that have an account. */
export async function uidsForEmails(emails: string[]): Promise<string[]> {
  const uids: string[] = [];
  for (let i = 0; i < emails.length; i += AUTH_LOOKUP_LIMIT) {
    const result = await admin.auth().getUsers(
      emails.slice(i, i + AUTH_LOOKUP_LIMIT).map((email) => ({ email })),
    );
    for (const user of result.users) uids.push(user.uid);
  }
  return uids;
}

/**
 * Every device a user has signed in on. Each device keeps its token in
 * fcm_tokens/{uid}/devices/{deviceId}. The older single token in fcm_tokens/{uid}
 * is still read, so devices that have not reopened the app keep receiving pushes.
 * A token that appears twice is sent once.
 */
export async function pushTargetsForUids(uids: string[]): Promise<PushTarget[]> {
  const db = admin.firestore();
  const perUser = await Promise.all(
    uids.map(async (uid) => {
      const userRef = db.collection('fcm_tokens').doc(uid);
      const [devices, legacy] = await Promise.all([
        userRef.collection('devices').get(),
        userRef.get(),
      ]);
      const targets: PushTarget[] = devices.docs.map((d) => ({
        token: d.data().token,
        ref: d.ref,
      }));
      targets.push({ token: legacy.data()?.token, ref: userRef });
      return targets;
    }),
  );

  const seen = new Set<string>();
  const targets: PushTarget[] = [];
  for (const target of perUser.flat()) {
    if (typeof target.token !== 'string' || target.token === '') continue;
    if (seen.has(target.token)) continue;
    seen.add(target.token);
    targets.push(target);
  }
  return targets;
}

/**
 * Sends one message to every target, in batches of FCM_BATCH_LIMIT. A dead
 * token is deleted, so the next send does not try it again.
 */
export async function sendPush(
  targets: PushTarget[],
  message: Omit<admin.messaging.MulticastMessage, 'tokens'>,
  label: string,
): Promise<void> {
  for (let i = 0; i < targets.length; i += FCM_BATCH_LIMIT) {
    const batch = targets.slice(i, i + FCM_BATCH_LIMIT);
    const response = await admin.messaging().sendEachForMulticast({
      ...message,
      tokens: batch.map((t) => t.token),
    });

    const removals: Promise<unknown>[] = [];
    response.responses.forEach((r, idx) => {
      if (r.success) return;
      if (r.error && DEAD_TOKEN_CODES.has(r.error.code)) {
        removals.push(batch[idx].ref.delete());
      }
    });
    await Promise.all(removals);

    if (response.failureCount > 0) {
      console.warn(`[${label}] ${response.failureCount} push(es) failed`);
    }
  }
}
