import * as functions from 'firebase-functions/v1';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';

const db = getFirestore();

/**
 * chatRateLimiter
 *
 * Triggered on every new message in chats/{chatId}/messages/{messageId}.
 * Enforces a rate limit of max 30 messages per user per minute per chat.
 *
 * If the limit is exceeded:
 *  - Deletes the offending message.
 *  - Writes a rate_limit_violations/{uid} document (upserted).
 *  - After 3 violations, the user's explorer_profiles tier is not changed here
 *    (that requires a separate admin flow), but violations are logged for review.
 */
export const chatRateLimiter = functions
  .region('asia-south1')
  .firestore.document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return;

    const { senderId } = data;
    if (!senderId) return;

    const chatId = context.params.chatId;
    const now = Date.now();
    const windowMs = 60 * 1000; // 1-minute window
    const maxMessages = 30;

    // Count messages from this sender in the last 1 minute
    const windowStart = Timestamp.fromMillis(now - windowMs);
    const recentSnap = await db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .where('senderId', '==', senderId)
      .where('timestamp', '>=', windowStart)
      .count()
      .get();

    const count = recentSnap.data().count;

    if (count > maxMessages) {
      console.warn(
        `[chatRateLimiter] Rate limit exceeded: uid=${senderId}, chatId=${chatId}, count=${count}`
      );

      // Delete the offending message (service account bypasses Firestore rules)
      try {
        await snap.ref.delete();
      } catch (e) {
        console.error('[chatRateLimiter] Could not delete message:', e);
      }

      // Upsert rate_limit_violations document
      const violationRef = db.collection('rate_limit_violations').doc(senderId);
      await violationRef.set(
        {
          uid: senderId,
          lastViolationAt: FieldValue.serverTimestamp(),
          violationCount: FieldValue.increment(1),
          lastChatId: chatId,
        },
        { merge: true }
      );

      // Read updated violation count
      const violationDoc = await violationRef.get();
      const violationCount = violationDoc.data()?.violationCount ?? 1;

      // After 5 violations: write an in-app warning notification to the user
      if (violationCount >= 5) {
        await db
          .collection('users')
          .doc(senderId)
          .collection('notifications')
          .add({
            title: '⚠️ Messaging Limit Warning',
            body:
              'You are sending messages too quickly. Repeated violations may result in a temporary messaging restriction.',
            action: 'rate_limit_warning',
            timestamp: FieldValue.serverTimestamp(),
          });
        console.warn(
          `[chatRateLimiter] Warning notification sent to uid=${senderId} (violations: ${violationCount})`
        );
      }
    }
  });
