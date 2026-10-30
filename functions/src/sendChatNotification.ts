import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { pushTargetsForUids, sendPush, uidsForEmails } from './lib/tourPush';

const db = admin.firestore();

/**
 * sendChatNotification
 *
 * Triggered on every new message in chats/{chatId}/messages/{messageId}.
 * Responsibilities:
 *  1. Fetches sender display name.
 *  2. Writes an in-app notification to the recipient's users/{uid}/notifications.
 *  3. Sends an FCM push notification to the recipient's registered devices via tourPush.
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
    // A call log records a call. It is not a message, so nobody is notified.
    if (type === 'call') return;
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
    const chatData = chatDoc.exists ? chatDoc.data() : null;
    let participants: string[] = chatData?.participants || [];
    if (participants.length === 0 && chatId.includes('_')) {
      participants = chatId.split('_');
    }

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

    // 3. Resolve recipient UIDs for push notifications
    try {
      let uids: string[];
      if (recipientId.includes('@')) {
        uids = await uidsForEmails([recipientId.toLowerCase()]);
      } else {
        uids = [recipientId];
      }

      if (uids.length === 0) return;

      const targets = await pushTargetsForUids(uids);
      if (targets.length === 0) return;

      // 4. Send high-priority FCM push notification to all user's devices
      await sendPush(
        targets,
        {
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
              priority: 'high',
            },
            priority: 'high',
          },
          apns: {
            payload: {
              aps: {
                badge: 1,
                sound: 'default',
              },
            },
          },
        },
        `sendChatNotification ${chatId}`,
      );

      console.log(
        `[sendChatNotification] Push sent to ${targets.length} device(s) for recipient=${recipientId}`
      );

      // 5. Update message status to 'delivered'
      await snap.ref.update({
        status: 'delivered',
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('[sendChatNotification] Error sending push notification:', e);
    }
  });
