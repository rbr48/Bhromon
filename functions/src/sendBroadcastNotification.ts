import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Triggered whenever the admin dashboard creates a document in the top-level
 * `notifications` collection.  Fans the broadcast out to every matching
 * FCM token (filtered by target tier when specified).
 *
 * Supported Firestore payload fields:
 *   title      – notification title (required)
 *   body       – notification body  (required)
 *   target     – 'all' | tier string  e.g. 'pioneer', 'verified' …
 *   icon       – string label used in data payload
 *   imageUrl   – optional HTTPS URL for a big-picture notification image
 */
export const sendBroadcastNotification = functions
  .region('asia-south1')
  .firestore.document('notifications/{notifId}')
  .onCreate(async (snap) => {
    const data = snap.data();
    if (!data) return;

    const { title, body, target, icon, imageUrl } = data;
    if (!title || !body) {
      console.warn('sendBroadcastNotification: missing title or body, skipping.');
      return;
    }

    try {
      // ── 1. Collect target FCM tokens ──────────────────────────────────────
      let tokens: string[] = [];

      if (!target || target === 'all') {
        // Fetch every document from the fcm_tokens collection
        const tokenSnap = await db.collection('fcm_tokens').get();
        tokenSnap.forEach((doc) => {
          const t = doc.data()?.token as string | undefined;
          if (t) tokens.push(t);
        });
      } else {
        // Fetch only profiles that match the requested tier, then look up tokens
        const profileSnap = await db
          .collection('explorer_profiles')
          .where('tier', '==', target)
          .get();

        const uids: string[] = [];
        profileSnap.forEach((doc) => uids.push(doc.id));

        // Batch-fetch their FCM tokens (Firestore allows up to 30 in 'in' query)
        for (let i = 0; i < uids.length; i += 30) {
          const batch = uids.slice(i, i + 30);
          const tokenSnap = await db
            .collection('fcm_tokens')
            .where(admin.firestore.FieldPath.documentId(), 'in', batch)
            .get();
          tokenSnap.forEach((doc) => {
            const t = doc.data()?.token as string | undefined;
            if (t) tokens.push(t);
          });
        }
      }

      if (tokens.length === 0) {
        console.log('sendBroadcastNotification: no matching tokens found.');
        return;
      }

      // ── 2. Build FCM notification payload ─────────────────────────────────
      const notification: admin.messaging.Notification = {
        title,
        body,
        ...(imageUrl ? { imageUrl } : {}),
      };

      const dataPayload: Record<string, string> = {
        action: 'broadcast',
        icon: icon || 'announcement',
        ...(imageUrl ? { imageUrl } : {}),
      };

      // ── 3. Send in batches of 500 (FCM multicast limit) ───────────────────
      const chunkSize = 500;
      let successCount = 0;
      let failureCount = 0;

      for (let i = 0; i < tokens.length; i += chunkSize) {
        const chunk = tokens.slice(i, i + chunkSize);

        const multicastMessage: admin.messaging.MulticastMessage = {
          notification,
          data: dataPayload,
          tokens: chunk,
          android: {
            notification: {
              imageUrl: imageUrl || undefined,
              channelId: 'bhromon_general',
            },
          },
          apns: {
            payload: {
              aps: {
                alert: { title, body },
                sound: 'default',
                mutableContent: imageUrl ? true : false,
              },
            },
            ...(imageUrl
              ? {
                  fcmOptions: { imageUrl },
                }
              : {}),
          },
        };

        const response = await messaging.sendEachForMulticast(multicastMessage);
        successCount += response.successCount;
        failureCount += response.failureCount;
      }

      console.log(
        `sendBroadcastNotification: sent to ${tokens.length} tokens. ` +
          `Success=${successCount}, Failure=${failureCount}, ` +
          `target=${target || 'all'}, hasImage=${!!imageUrl}`
      );
    } catch (e) {
      console.error('sendBroadcastNotification error:', e);
    }
  });
