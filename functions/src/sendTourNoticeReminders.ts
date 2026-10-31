import { FieldValue, QueryDocumentSnapshot, Timestamp, getFirestore } from 'firebase-admin/firestore';
import * as functions from 'firebase-functions/v1';
import { minutesUntil, reminderText, reminderWindow } from './lib/noticeReminders';
import {
  activeMemberEmails,
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendTourNoticeReminders
 *
 * Runs every five minutes. A timed notice that starts within the next half hour
 * gets one push to every active member of its group. The reminder is claimed
 * with `reminderSentAt` in a transaction before anything is sent, so runs that
 * overlap send it once.
 */
export const sendTourNoticeReminders = functions
  .region('asia-south1')
  .pubsub.schedule('every 5 minutes')
  .onRun(async () => {
    const { fromMs, toMs } = reminderWindow(Date.now());
    const due = await getFirestore()
      .collectionGroup('notices')
      .where('eventAt', '>=', Timestamp.fromMillis(fromMs))
      .where('eventAt', '<=', Timestamp.fromMillis(toMs))
      .get();

    for (const doc of due.docs) {
      try {
        await sendReminder(doc);
      } catch (e) {
        console.error(`[sendTourNoticeReminders] Failed for ${doc.ref.path}:`, e);
      }
    }
  });

async function sendReminder(doc: QueryDocumentSnapshot): Promise<void> {
  const tourId = doc.ref.parent.parent?.id;
  if (!tourId) return;

  const notice = await getFirestore().runTransaction(async (tx) => {
    const fresh = await tx.get(doc.ref);
    if (!fresh.exists || fresh.get('reminderSentAt')) return null;
    tx.update(doc.ref, {
      reminderSentAt: FieldValue.serverTimestamp(),
    });
    return fresh.data() ?? null;
  });
  if (notice === null) return;

  const eventAt = notice.eventAt as Timestamp | undefined;
  if (!eventAt) return;
  const { title, body } = reminderText(
    notice,
    minutesUntil(eventAt.toMillis(), Date.now()),
  );

  // Everyone in the group, the author included: this is the time to be there.
  const members = await activeMemberEmails(tourId, '');
  if (members.length === 0) return;
  const targets = await pushTargetsForUids(await uidsForEmails(members));
  await sendPush(
    targets,
    {
      notification: { title, body },
      data: { action: 'notice', tourId, noticeId: doc.id },
      android: { priority: 'high' },
    },
    `sendTourNoticeReminders ${doc.id}`,
  );
}
