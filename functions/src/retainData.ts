import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

/**
 * Data retention scheduler — runs daily at 02:00 Asia/Dhaka.
 *
 * Purges:
 *   - trust_events older than 1 year  (batch of up to 100 docs)
 *   - admin_audit_logs older than 2 years (batch of up to 100 docs)
 *
 * Uses batches of 100 to stay within Firestore batch limits (500 max writes).
 * Consecutive executions will continue purging until nothing remains.
 */
export const retainData = functions
  .region('asia-south1')
  .pubsub.schedule('0 2 * * *')
  .timeZone('Asia/Dhaka')
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const oneYearAgo = new admin.firestore.Timestamp(
      now.seconds - 365 * 24 * 3600,
      0,
    );
    const twoYearsAgo = new admin.firestore.Timestamp(
      now.seconds - 730 * 24 * 3600,
      0,
    );

    // ── Purge trust_events older than 1 year ─────────────────────────────
    const oldTrustEvents = await db
      .collection('trust_events')
      .where('timestamp', '<', oneYearAgo)
      .limit(100)
      .get();

    if (!oldTrustEvents.empty) {
      const batch1 = db.batch();
      oldTrustEvents.docs.forEach((doc) => batch1.delete(doc.ref));
      await batch1.commit();
    }

    // ── Purge admin_audit_logs older than 2 years ─────────────────────────
    const oldAuditLogs = await db
      .collection('admin_audit_logs')
      .where('timestamp', '<', twoYearsAgo)
      .limit(100)
      .get();

    if (!oldAuditLogs.empty) {
      const batch2 = db.batch();
      oldAuditLogs.docs.forEach((doc) => batch2.delete(doc.ref));
      await batch2.commit();
    }

    console.log(
      `[retainData] Purged ${oldTrustEvents.size} trust_events, ` +
        `${oldAuditLogs.size} audit_logs`,
    );
  });
