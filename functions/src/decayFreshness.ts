import * as functions from 'firebase-functions/v1';
import { getFirestore } from 'firebase-admin/firestore';
import { Message, getMessaging } from 'firebase-admin/messaging';
import { chunk, drainQuery, getAllInChunks, MAX_FCM_BATCH } from './lib/batching';

const db = getFirestore();

/** Pages per run; with 400 tips a page that is 20,000 tips a night. */
const MAX_PAGES = 50;

/** Sends one "tip went stale" push per author, batched. */
export async function notifyStaleAuthors(authorIds: string[]): Promise<number> {
  const tokenDocs = await getAllInChunks(
    db,
    authorIds.map((uid) => db.collection('fcm_tokens').doc(uid)),
  );
  const messages: Message[] = [];
  tokenDocs.forEach((tokenDoc, i) => {
    const token = tokenDoc.exists ? tokenDoc.data()?.token : undefined;
    if (!token) return;
    messages.push({
      notification: {
        title: 'Tip Stale Alert',
        body: 'Your pro tip has gone stale. Please re-confirm it!',
      },
      data: {
        action: 're_confirm_tips',
        uid: authorIds[i],
      },
      token,
    });
  });

  let sent = 0;
  for (const part of chunk(messages, MAX_FCM_BATCH)) {
    try {
      const response = await getMessaging().sendEach(part);
      sent += response.successCount;
    } catch (e) {
      console.error('Error sending FCM:', e);
    }
  }
  return sent;
}

/**
 * Marks tips unconfirmed for 180 days as stale.
 *
 * Works through the tips in pages, one batch each: a single batch for every
 * stale tip fails outright past Firestore's 500-write limit, which used to
 * make the whole nightly run fail once enough tips went stale.
 */
export async function runDecayFreshness(now: Date = new Date()) {
  const cutoff = new Date(now);
  cutoff.setDate(cutoff.getDate() - 180);

  const authorIds = new Set<string>();
  const query = db.collection('pro_tips')
    .where('lastConfirmed', '<', cutoff)
    .where('decayStatus', '!=', 'stale');

  // Updated tips stop matching the query, so each page fetches new ones.
  const { handled, exhausted } = await drainQuery(query, async (docs) => {
    const batch = db.batch();
    for (const doc of docs) {
      batch.update(doc.ref, { decayStatus: 'stale' });
      const authorId = doc.data().authorId;
      if (authorId) authorIds.add(authorId);
    }
    await batch.commit();
  }, { maxPages: MAX_PAGES });

  const notified = await notifyStaleAuthors([...authorIds]);
  console.log(
    `Marked ${handled} tips stale, notified ${notified} of ${authorIds.size} authors` +
      (exhausted ? '' : ' (more remain; continuing next run)'),
  );
  return { handled, notified, exhausted };
}

export const decayFreshness = functions
  .region('asia-south1')
  .pubsub.schedule('0 20 * * *')  // 02:00 BST (UTC+6)
  .timeZone('Asia/Dhaka')
  .onRun(async () => {
    await runDecayFreshness();
  });
