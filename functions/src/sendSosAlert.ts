import * as functions from 'firebase-functions';
import {
  activeMemberEmails,
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendSosAlert
 *
 * Triggered when a member raises a safety alert in tours/{tourId}/sos.
 * Pushes to every other active member of the tour who has signed in on a
 * device, including every device a member has signed in on.
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

      const targets = await pushTargetsForUids(await uidsForEmails(emails));
      await sendPush(
        targets,
        {
          notification: {
            title: `SOS from ${senderName}`,
            body: 'Open Bhromon and check the Family Safety Hub.',
          },
          data: { action: 'sos', type: 'sos', tourId, alertId },
          android: { priority: 'high' },
        },
        `sendSosAlert ${alertId}`,
      );
    } catch (e) {
      console.error('[sendSosAlert] Could not send alert pushes:', e);
    }
  });
