import * as functions from 'firebase-functions';
import {
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendCallPushNotification
 *
 * Triggered on new calls in calls/{callId}.
 * Sends a high-priority incoming call push to wake up the callee's device.
 */
export const sendCallPushNotification = functions
  .region('asia-south1')
  .firestore.document('calls/{callId}')
  .onCreate(async (snap, context) => {
    const call = snap.data();
    if (!call) return;

    const { callId } = context.params;
    const calleeId = String(call.calleeId ?? '').trim();
    if (!calleeId) return;

    try {
      let uids: string[];
      if (calleeId.includes('@')) {
        uids = await uidsForEmails([calleeId.toLowerCase()]);
      } else {
        uids = [calleeId];
      }

      if (uids.length === 0) return;

      const callerName =
        typeof call.callerName === 'string' && call.callerName.trim() !== ''
          ? call.callerName.trim()
          : 'A traveler';
      const isVideo = call.isVideo === true;

      const targets = await pushTargetsForUids(uids);
      await sendPush(
        targets,
        {
          notification: {
            title: `Incoming ${isVideo ? 'Video' : 'Voice'} Call`,
            body: `${callerName} is calling you on Bhromon...`,
          },
          data: {
            action: 'call',
            callId,
            callerId: String(call.callerId ?? ''),
            callerName,
            callerAvatar: String(call.callerAvatar ?? ''),
            isVideo: String(isVideo),
          },
          android: {
            priority: 'high',
          },
        },
        `sendCallPushNotification ${callId}`,
      );
    } catch (e) {
      console.error('[sendCallPushNotification] Failed to send call push:', e);
    }
  });
