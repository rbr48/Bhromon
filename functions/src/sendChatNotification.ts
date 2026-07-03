import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

/**
 * sendChatNotification
 *
 * Triggered on every new message in chats/{chatId}/messages/{messageId}.
 * Responsibilities:
 *  1. Fetches sender display name.
 *  2. Writes an in-app notification to the recipient's users/{uid}/notifications.
 *  3. Sends an FCM push notification to the recipient's registered device.
 *  4. Updates message `status` from 'sent' → 'delivered' (when FCM send succeeds).
 *  5. Handles media message types gracefully (photo/video notification body).
 */
export const sendChatNotification = functions
  .region('asia-south1')
  .firestore.document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const messageData = snap.data();
    if (!messageData) return;

    const { senderId, text, type } = messageData;
    const chatId = context.params.chatId;

    // Build notification body based on message type
    let notificationBody = text as string | undefined;
    if (!notificationBody || notificationBody.trim() === '') {
      if (type === 'image') notificationBody = '📷 Photo';
      else if (type === 'video') notificationBody = '🎬 Video';
      else if (type === 'audio') notificationBody = '🎤 Voice message';
      else notificationBody = 'New message';
    }
    // Truncate to 120 chars for push preview
    if (notificationBody.length > 120) {
      notificationBody = notificationBody.substring(0, 117) + '…';
    }

    // Get the parent chat metadata to find the recipient
    const chatDoc = await db.collection('chats').doc(chatId).get();
    if (!chatDoc.exists) return;

    const chatData = chatDoc.data();
    const participants: string[] = chatData?.participants || [];

    // Recipient is the participant who is not the sender
    const recipientId = participants.find((uid) => uid !== senderId);
    if (!recipientId) return;

    // 1. Fetch sender's display name
    let senderName = 'Explorer';
    try {
      const senderProfile = await db
        .collection('explorer_profiles')
        .doc(senderId)
        .get();
      if (senderProfile.exists) {
        senderName = senderProfile.data()?.displayName || 'Explorer';
      }
    } catch (e) {
      console.error('[sendChatNotification] Error fetching sender profile:', e);
    }

    // 2. Write in-app notification to users/{recipientId}/notifications
    try {
      await db
        .collection('users')
        .doc(recipientId)
        .collection('notifications')
        .add({
          title: `New message from ${senderName}`,
          body: notificationBody,
          action: 'chat',
          uid: senderId,
          chatId: chatId,
          messageType: type || 'text',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
      console.error('[sendChatNotification] Error writing in-app notification:', e);
    }

    // 3. Fetch recipient's FCM token
    let token: string | undefined;
    try {
      const tokenDoc = await db.collection('fcm_tokens').doc(recipientId).get();
      if (!tokenDoc.exists) return;
      token = tokenDoc.data()?.token;
      if (!token) return;
    } catch (e) {
      console.error('[sendChatNotification] Error fetching FCM token:', e);
      return;
    }

    // 4. Send FCM push notification
    const message = {
      notification: {
        title: `New message from ${senderName}`,
        body: notificationBody,
      },
      data: {
        action: 'chat',
        uid: senderId,
        chatId: chatId,
        itemId: chatId,
        messageType: type || 'text',
      },
      android: {
        notification: {
          channelId: 'bhromon_general',
          priority: 'high' as const,
        },
      },
      apns: {
        payload: {
          aps: {
            badge: 1,
            sound: 'default',
          },
        },
      },
      token,
    };

    try {
      await admin.messaging().send(message);
      console.log(
        `[sendChatNotification] Push sent to uid=${recipientId} for chatId=${chatId}`
      );

      // 5. Update message status to 'delivered' (FCM accepted the message)
      await snap.ref.update({
        status: 'delivered',
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('[sendChatNotification] Error sending FCM push:', e);
      // If the token is invalid, remove it to prevent future failures
      const errorCode = (e as any)?.errorInfo?.code;
      if (
        errorCode === 'messaging/invalid-registration-token' ||
        errorCode === 'messaging/registration-token-not-registered'
      ) {
        await db.collection('fcm_tokens').doc(recipientId).delete();
        console.log(
          `[sendChatNotification] Deleted invalid FCM token for uid=${recipientId}`
        );
      }
    }
  });
