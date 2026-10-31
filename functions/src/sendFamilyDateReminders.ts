import { QueryDocumentSnapshot, getFirestore } from 'firebase-admin/firestore';
import * as functions from 'firebase-functions/v1';
import {
  FamilyDateRecord,
  dhakaDayKey,
  familyDateReminderText,
  planFamilyDateReminders,
} from './lib/familyDates';
import { activeMemberEmails, pushTargetsForUids, sendPush, uidsForEmails } from './lib/tourPush';

/**
 * sendFamilyDateReminders
 *
 * Runs every morning at seven, Dhaka time. A family date whose reminder day has
 * come gets one push for each reminder due, to every active member of its circle.
 * The claim and the next schedule are written in one transaction before anything
 * is sent, so a run that overlaps another sends nothing twice. A date whose
 * reminder was missed on an earlier day is brought up to date without a late push.
 */
export const sendFamilyDateReminders = functions
  .region('asia-south1')
  .pubsub.schedule('0 7 * * *')
  .timeZone('Asia/Dhaka')
  .onRun(async () => {
    const today = dhakaDayKey(Date.now());
    // Dates with no reminder due carry a null remindOn, which this range skips.
    const due = await getFirestore()
      .collectionGroup('family_dates')
      .where('remindOn', '<=', today)
      .get();

    for (const doc of due.docs) {
      try {
        await sendDueReminders(doc, today);
      } catch (e) {
        console.error(`[sendFamilyDateReminders] Failed for ${doc.ref.path}:`, e);
      }
    }
  });

async function sendDueReminders(doc: QueryDocumentSnapshot, today: string): Promise<void> {
  const tourId = doc.ref.parent.parent?.id;
  if (!tourId) return;

  const claimed = await getFirestore().runTransaction(async (tx) => {
    const fresh = await tx.get(doc.ref);
    if (!fresh.exists) return null;
    const record = (fresh.data() ?? {}) as FamilyDateRecord;
    const plan = planFamilyDateReminders(record, today);
    if (plan === null) return null;
    tx.update(doc.ref, {
      nextOn: plan.update.nextOn,
      remindOn: plan.update.remindOn,
    });
    return { record, reminders: plan.reminders };
  });
  if (claimed === null || claimed.reminders.length === 0) return;

  // The whole circle, the creator included: the date is for everyone in it.
  const members = await activeMemberEmails(tourId, '');
  if (members.length === 0) return;
  const targets = await pushTargetsForUids(await uidsForEmails(members));
  for (const reminder of claimed.reminders) {
    const { title, body } = familyDateReminderText(claimed.record, reminder.daysLeft);
    await sendPush(
      targets,
      {
        notification: { title, body },
        data: { action: 'family_date', tourId, dateId: doc.id },
        android: { priority: 'high' },
      },
      `sendFamilyDateReminders ${doc.id}`,
    );
  }
}
