import * as functions from 'firebase-functions/v1';
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { drainQuery } from './lib/batching';

const db = getFirestore();

/** Pages per collection per run (400 docs each): up to 20,000 deletions. */
const MAX_PAGES = 50;

async function purgeOlderThan(
  collection: string,
  before: Timestamp,
): Promise<{ handled: number; exhausted: boolean }> {
  return drainQuery(
    db.collection(collection).where('timestamp', '<', before),
    async (docs) => {
      const batch = db.batch();
      docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    },
    { maxPages: MAX_PAGES },
  );
}

/**
 * Purges trust_events older than 1 year and admin_audit_logs older than 2
 * years.
 *
 * Deletes in batches until nothing old is left (bounded per run). It used to
 * delete only 100 of each per day, so any backlog above that kept growing.
 */
export async function runRetention(nowSeconds = Timestamp.now().seconds) {
  const oneYearAgo = new Timestamp(nowSeconds - 365 * 24 * 3600, 0);
  const twoYearsAgo = new Timestamp(nowSeconds - 730 * 24 * 3600, 0);

  const trust = await purgeOlderThan('trust_events', oneYearAgo);
  const audit = await purgeOlderThan('admin_audit_logs', twoYearsAgo);

  console.log(
    `[retainData] Purged ${trust.handled} trust_events, ${audit.handled} audit_logs` +
      (trust.exhausted && audit.exhausted ? '' : ' (more remain; continuing next run)'),
  );
  return { trust, audit };
}

/** Data retention scheduler — runs daily at 02:00 Asia/Dhaka. */
export const retainData = functions
  .region('asia-south1')
  .pubsub.schedule('0 2 * * *')
  .timeZone('Asia/Dhaka')
  .onRun(async () => {
    await runRetention();
  });
