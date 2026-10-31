import * as functions from 'firebase-functions/v1';
import { getFirestore } from 'firebase-admin/firestore';
import { Message, getMessaging } from 'firebase-admin/messaging';

const db = getFirestore();

export const sendGeneralNotification = functions
  .region('asia-south1')
  .firestore.document('users/{userId}/notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notifData = snap.data();
    if (!notifData) return;

    const { title, body, action, uid, itemId, imageUrl } = notifData;
    const userId = context.params.userId;

    // Chat push notifications are already sent directly by sendChatNotification.ts
    if (action === 'chat') return;

    try {
      // Fetch recipient's FCM token
      const tokenDoc = await db.collection('fcm_tokens').doc(userId).get();
      if (!tokenDoc.exists) return;
      const token = tokenDoc.data()?.token;
      if (!token) return;

      const message: Message = {
        notification: {
          title: title || 'New Notification',
          body: body || '',
          ...(imageUrl ? { imageUrl } : {}),
        },
        data: {
          action: action || '',
          uid: uid || '',
          itemId: itemId || '',
          ...(imageUrl ? { imageUrl } : {}),
        },
        android: {
          notification: {
            imageUrl: imageUrl || undefined,
            channelId: 'bhromon_general',
          },
        },
        apns: {
          payload: { aps: { sound: 'default', mutableContent: imageUrl ? true : false } },
          ...(imageUrl ? { fcmOptions: { imageUrl } } : {}),
        },
        token: token,
      };

      await getMessaging().send(message);
      console.log(`Successfully sent general push notification to user ${userId} for action: ${action}`);
    } catch (e) {
      console.error('Error sending general FCM push notification:', e);
    }
  });
