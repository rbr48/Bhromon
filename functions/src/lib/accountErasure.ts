import * as admin from 'firebase-admin';

type Firestore = admin.firestore.Firestore;

/** Documents that belong to one person, with the field that names them. */
export const OWNED_DOCUMENTS: ReadonlyArray<readonly [string, string]> = [
  ['trip_logs', 'authorId'],
  ['archived_trip_logs', 'authorId'],
  ['pro_tips', 'authorId'],
  ['location_pins', 'createdByUid'],
  ['follows', 'followerId'],
  ['likes', 'userId'],
  ['pin_visits', 'userId'],
  ['calls', 'callerId'],
  ['calls', 'calleeId'],
];

/** Documents keyed by the person's uid, with everything under them. */
export const UID_DOCUMENTS: ReadonlyArray<string> = [
  'users',
  'explorer_profiles',
  'explorer_scores',
  'fcm_tokens',
  'direct_messages',
];

const PAGE_SIZE = 200;

/**
 * Deletes every document a query matches, a page at a time, with whatever sits
 * under each one. A failed delete throws, so the closing is retried rather than
 * leaving a partial record behind. Returns how many were deleted.
 */
async function deleteAll(db: Firestore, query: admin.firestore.Query): Promise<number> {
  let deleted = 0;
  for (;;) {
    const page = await query.limit(PAGE_SIZE).get();
    if (page.empty) return deleted;
    for (const doc of page.docs) {
      await db.recursiveDelete(doc.ref);
      deleted += 1;
    }
  }
}

/** Removes what one person owns in the database, and their own account documents. */
export async function eraseOwnedDocuments(db: Firestore, uid: string): Promise<number> {
  let deleted = 0;
  for (const [collection, field] of OWNED_DOCUMENTS) {
    deleted += await deleteAll(db, db.collection(collection).where(field, '==', uid));
  }
  for (const collection of UID_DOCUMENTS) {
    await db.recursiveDelete(db.collection(collection).doc(uid));
  }
  return deleted;
}

/**
 * Takes one person out of their direct chats. The messages they sent are deleted and
 * they leave the chat's participants. The other person keeps the chat and their own
 * messages.
 */
export async function eraseFromChats(
  db: Firestore,
  uid: string,
): Promise<{ chats: number; messages: number }> {
  const chats = await db.collection('chats').where('participants', 'array-contains', uid).get();
  let messages = 0;
  for (const chat of chats.docs) {
    messages += await deleteAll(db, chat.ref.collection('messages').where('senderId', '==', uid));
    const update: admin.firestore.UpdateData<admin.firestore.DocumentData> = {
      participants: admin.firestore.FieldValue.arrayRemove(uid),
      [`memberEmails.${uid}`]: admin.firestore.FieldValue.delete(),
    };
    if (chat.get('lastSenderId') === uid) {
      update.lastSenderId = '';
      update.lastMessage = '';
    }
    await chat.ref.update(update);
  }
  return { chats: chats.size, messages };
}

/**
 * Removes the files kept under the person's storage folder. A failure throws, so the
 * closing can be retried.
 */
export async function eraseStorageFiles(
  bucket: { deleteFiles(options: { prefix: string }): Promise<unknown> },
  uid: string,
): Promise<void> {
  await bucket.deleteFiles({ prefix: `users/${uid}/` });
}

const MEDIA_ACCOUNT_PURGE_URL =
  process.env.MEDIA_ACCOUNT_PURGE_URL ?? 'https://bhromon.fun/api/media/purge/account';

/**
 * The media server removes the person's files in every space, and their part in the
 * chat service. Returns the paths of the files it removed. A failed call throws, so
 * the closing is retried.
 */
export async function purgeAccountOnMediaServer(uid: string, email: string): Promise<string[]> {
  const key = process.env.MEDIA_PURGE_KEY;
  if (!key) throw new Error('MEDIA_PURGE_KEY is not configured');
  const response = await fetch(MEDIA_ACCOUNT_PURGE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Purge-Key': key },
    body: JSON.stringify({ uid, email }),
  });
  if (!response.ok) {
    throw new Error(`Media account purge answered HTTP ${response.status}`);
  }
  const body = (await response.json()) as { paths?: unknown };
  return Array.isArray(body.paths)
    ? body.paths.filter((path): path is string => typeof path === 'string')
    : [];
}
