import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import {
  buildCallPushMessage,
  callerDisplayName,
  CALL_WINDOW_MS,
  isOverCallLimit,
  isStaleCall,
  recentCallCount,
} from './lib/callPush';
import {
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendCallPushNotification
 *
 * Triggered when a call document is created in calls/{callId}. This is the only
 * push for a call. The VPS relay sends none, so one call rings one phone once.
 *
 * The caller's name comes from explorer_profiles, not from the call document,
 * which the caller wrote. A caller who starts too many calls has the new call
 * ended without a push.
 */
export const sendCallPushNotification = functions
  .region('asia-south1')
  .firestore.document('calls/{callId}')
  .onCreate(async (snap, context) => {
    const call = snap.data();
    if (!call) return;

    const { callId } = context.params;
    const callerId = String(call.callerId ?? '').trim();
    const calleeId = String(call.calleeId ?? '').trim();
    if (!callerId || !calleeId) return;

    const createdAtMs =
      call.createdAt && typeof call.createdAt.toMillis === 'function'
        ? call.createdAt.toMillis()
        : Date.now();
    if (isStaleCall(createdAtMs, Date.now())) return;

    try {
      const db = admin.firestore();
      const recent = await recentCallCount(db, callerId, Date.now() - CALL_WINDOW_MS);
      if (isOverCallLimit(recent)) {
        console.warn(`[sendCallPushNotification] ${callerId} started too many calls; ending ${callId}`);
        await snap.ref.update({ status: 'ended', endReason: 'rate_limited' });
        return;
      }

      const uids = calleeId.includes('@')
        ? await uidsForEmails([calleeId.toLowerCase()])
        : [calleeId];
      const callees = uids.filter((uid) => uid !== callerId);
      if (callees.length === 0) return;

      const profile = await db.collection('explorer_profiles').doc(callerId).get();
      const callerName = callerDisplayName(profile.exists ? profile.data()?.displayName : undefined);

      const targets = await pushTargetsForUids(callees);
      await sendPush(
        targets,
        buildCallPushMessage(
          { callId, callerId, callerName, isVideo: call.isVideo === true },
          Date.now(),
        ),
        `sendCallPushNotification ${callId}`,
      );
    } catch (e) {
      console.error('[sendCallPushNotification] Failed to send call push:', e);
    }
  });
