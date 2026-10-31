import * as functions from 'firebase-functions';
import { noticePushBody, noticePushTitle } from './lib/noticePush';
import {
  activeMemberEmails,
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendTourNoticeNotification
 *
 * Triggered on every new notice in tours/{tourId}/notices/{noticeId}.
 * Pushes to all active members of the tour.
 */
export const sendTourNoticeNotification = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/notices/{noticeId}')
  .onCreate(async (snap, context) => {
    const notice = snap.data();
    if (!notice) return;

    const { tourId, noticeId } = context.params;
    const authorEmail = String(notice.authorEmail ?? '').trim().toLowerCase();

    try {
      const members = await activeMemberEmails(tourId, authorEmail);
      if (members.length === 0) return;

      const title = noticePushTitle(notice);
      const body = noticePushBody(notice);

      const targets = await pushTargetsForUids(await uidsForEmails(members));
      await sendPush(
        targets,
        {
          notification: {
            title,
            body,
          },
          data: {
            action: 'notice',
            tourId,
            noticeId,
          },
          android: {
            priority: 'high',
          },
        },
        `sendTourNoticeNotification ${noticeId}`,
      );
    } catch (e) {
      console.error('[sendTourNoticeNotification] Failed to send notice push:', e);
    }
  });
