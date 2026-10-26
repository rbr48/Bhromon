import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

/** Firebase Auth accepts up to 100 identifiers per lookup. */
const AUTH_LOOKUP_LIMIT = 100;
/** FCM accepts up to 500 tokens per multicast send. */
const FCM_BATCH_LIMIT = 500;

/**
 * sendSosAlert
 *
 * Triggered when a member raises a safety alert in tours/{tourId}/sos.
 * Pushes to every other active member of the tour who has signed in on a
 * device.
 *
 * Tour memberships are keyed by email, while device tokens are keyed by
 * Firebase user ID, so each member's email is resolved to a user ID with the
 * Admin SDK. Members without an account, or without a token, are skipped.
 */
export const sendSosAlert = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/sos/{alertId}')
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    if (!alert) return;

    const { tourId, alertId } = context.params;
    const senderEmail = String(alert.senderEmail ?? '').trim().toLowerCase();
    if (!senderEmail) return;

    const senderName =
      typeof alert.senderName === 'string' && alert.senderName.trim() !== ''
        ? alert.senderName.trim()
        : 'A member';

    try {
      const emails = await activeMemberEmails(tourId, senderEmail);
      if (emails.length === 0) return;

      const uids = await uidsForEmails(emails);
      const tokens = await tokensForUids(uids);

      for (let i = 0; i < tokens.length; i += FCM_BATCH_LIMIT) {
        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokens.slice(i, i + FCM_BATCH_LIMIT),
          notification: {
            title: `SOS from ${senderName}`,
            body: 'Open Bhromon and check the Family Safety Hub.',
          },
          data: { type: 'sos', tourId, alertId },
          android: { priority: 'high' },
        });
        if (response.failureCount > 0) {
          console.warn(
            `[sendSosAlert] ${response.failureCount} push(es) failed for alert ${alertId}`,
          );
        }
      }
    } catch (e) {
      console.error('[sendSosAlert] Could not send alert pushes:', e);
    }
  });

/** Emails of the tour's active members, except the sender, lower-cased. */
async function activeMemberEmails(tourId: string, senderEmail: string): Promise<string[]> {
  const rows = await db
    .collection('memberships')
    .where('tourId', '==', tourId)
    .where('status', '==', 'active')
    .get();

  const emails = new Set<string>();
  for (const row of rows.docs) {
    const email = String(row.data().email ?? '').trim().toLowerCase();
    if (email !== '' && email !== senderEmail) emails.add(email);
  }
  return [...emails];
}

/** Firebase user IDs for the emails that have an account. */
async function uidsForEmails(emails: string[]): Promise<string[]> {
  const uids: string[] = [];
  for (let i = 0; i < emails.length; i += AUTH_LOOKUP_LIMIT) {
    const result = await admin.auth().getUsers(
      emails.slice(i, i + AUTH_LOOKUP_LIMIT).map((email) => ({ email })),
    );
    for (const user of result.users) uids.push(user.uid);
  }
  return uids;
}

/** Push tokens saved for those user IDs, skipping users with none. */
async function tokensForUids(uids: string[]): Promise<string[]> {
  if (uids.length === 0) return [];

  const snaps = await db.getAll(
    ...uids.map((uid) => db.collection('fcm_tokens').doc(uid)),
  );
  const tokens: string[] = [];
  for (const snap of snaps) {
    const token = snap.exists ? snap.data()?.token : undefined;
    if (typeof token === 'string' && token !== '') tokens.push(token);
  }
  return tokens;
}
