import * as functions from 'firebase-functions';
import {
  activeMemberEmails,
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendTourLedgerNotification
 *
 * Triggered on every new expense in tours/{tourId}/expenses/{expenseId}.
 * Pushes to all active members of the tour.
 */
export const sendTourLedgerNotification = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/expenses/{expenseId}')
  .onCreate(async (snap, context) => {
    const expense = snap.data();
    if (!expense) return;

    const { tourId, expenseId } = context.params;
    const addedByEmail = String(expense.addedByEmail ?? '').trim().toLowerCase();

    try {
      const members = await activeMemberEmails(tourId, addedByEmail);
      if (members.length === 0) return;

      const payerName =
        typeof expense.paidByName === 'string' && expense.paidByName.trim() !== ''
          ? expense.paidByName.trim()
          : 'A member';
      const expenseTitle =
        typeof expense.title === 'string' && expense.title.trim() !== ''
          ? expense.title.trim()
          : 'trip expense';
      const amountPaisa =
        typeof expense.amount === 'number' ? expense.amount : 0;
      const taka = Math.round(amountPaisa / 100);

      const title = `💸 ৳${taka} expense recorded`;
      const body = `${payerName} paid ৳${taka} for ${expenseTitle}`;

      const targets = await pushTargetsForUids(await uidsForEmails(members));
      await sendPush(
        targets,
        {
          notification: {
            title,
            body,
          },
          data: {
            action: 'ledger',
            tourId,
            expenseId,
          },
        },
        `sendTourLedgerNotification ${expenseId}`,
      );
    } catch (e) {
      console.error(
        '[sendTourLedgerNotification] Failed to send ledger push:',
        e,
      );
    }
  });
