const admin = require('firebase-admin');
const path = require('path');

// ─────────────────────────────────────────────────────────────────────────────
// ⚠️  IMPORTANT — DOUBLE-SEND CONFLICT WARNING
//
// The Firebase Cloud Functions (sendBroadcastNotification, sendGeneralNotification)
// listen to the EXACT SAME Firestore paths as this daemon.
// If BOTH are active simultaneously, every notification will be delivered TWICE.
//
// Recommended deployment strategy:
//   • Use Cloud Functions ONLY  (zero-server, auto-scales, built-in retries)
//   • This daemon should only run when Cloud Functions are NOT deployed.
//
// To stop this daemon on the VPS:
//   systemctl stop bhromon-notif-daemon
//   systemctl disable bhromon-notif-daemon
// ─────────────────────────────────────────────────────────────────────────────

// Initialize Firebase Admin with local service account
const serviceAccountPath = path.join(__dirname, 'service-account.json');
const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const messaging = admin.messaging();

const daemonStartTime = Date.now();
const processedDocs = new Set();

console.log(`Notification daemon started at ${new Date(daemonStartTime).toISOString()}`);

// Listen to all notifications (collection group)
db.collectionGroup('notifications').onSnapshot(snapshot => {
  snapshot.docChanges().forEach(async change => {
    // Only process new document additions
    if (change.type !== 'added') return;

    const doc = change.doc;
    const docPath = doc.ref.path;
    const data = doc.data();

    // Skip if already processed in this session
    if (processedDocs.has(doc.id)) return;
    processedDocs.add(doc.id);

    // Get document timestamp — broadcast docs use createdAt, individual ones use
    // timestamp or submittedAt. Fall back to daemon start time so a missing
    // timestamp field never silently drops the notification.
    const timestamp = data.createdAt || data.timestamp || data.submittedAt;
    const docTime = timestamp
      ? (timestamp.toDate ? timestamp.toDate().getTime() : new Date(timestamp).getTime())
      : daemonStartTime; // treat undated docs as "just created"

    // Skip documents that were created before the daemon started.
    // Allow a 10-second grace window for server-time delta.
    if (docTime < daemonStartTime - 10000) {
      return;
    }

    console.log(`[${new Date().toISOString()}] Processing notification: ${docPath}`);

    const pathParts = docPath.split('/');
    
    if (pathParts.length === 2) {
      // Broadcast notification: notifications/{notifId}
      await handleBroadcastNotification(doc.id, data);
    } else if (pathParts.length === 4 && pathParts[0] === 'users' && pathParts[2] === 'notifications') {
      // Individual notification: users/{userId}/notifications/{notifId}
      const userId = pathParts[1];
      await handleIndividualNotification(userId, doc.id, data);
    }
  });
}, error => {
  console.error('Firestore listener error:', error);
});

async function handleBroadcastNotification(notifId, data) {
  const { title, body, target, icon, imageUrl } = data;
  if (!title || !body) {
    console.warn(`Broadcast ${notifId} is missing title or body. Skipping.`);
    return;
  }

  try {
    let tokens = [];
    if (!target || target === 'all') {
      const tokenSnap = await db.collection('fcm_tokens').get();
      tokenSnap.forEach((doc) => {
        const t = doc.data()?.token;
        if (t) tokens.push(t);
      });
    } else {
      const profileSnap = await db.collection('explorer_profiles').where('tier', '==', target).get();
      const uids = [];
      profileSnap.forEach((doc) => uids.push(doc.id));

      for (let i = 0; i < uids.length; i += 30) {
        const batch = uids.slice(i, i + 30);
        const tokenSnap = await db.collection('fcm_tokens').where(admin.firestore.FieldPath.documentId(), 'in', batch).get();
        tokenSnap.forEach((doc) => {
          const t = doc.data()?.token;
          if (t) tokens.push(t);
        });
      }
    }

    if (tokens.length === 0) {
      console.log(`No matching tokens found for broadcast ${notifId} (target: ${target})`);
      return;
    }

    // Send in chunks of 500
    const chunkSize = 500;
    let successCount = 0;
    let failureCount = 0;

    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const message = {
        notification: { title, body, ...(imageUrl ? { imageUrl } : {}) },
        data: {
          action: 'broadcast',
          icon: icon || 'announcement',
          ...(imageUrl ? { imageUrl } : {}),
        },
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
          ...(imageUrl ? { fcmOptions: { imageUrl } } : {}),
        },
      };

      const response = await messaging.sendEachForMulticast(message);
      successCount += response.successCount;
      failureCount += response.failureCount;
    }

    console.log(`Broadcast ${notifId} sent to ${tokens.length} devices (Success: ${successCount}, Fail: ${failureCount})`);
  } catch (err) {
    console.error(`Error sending broadcast ${notifId}:`, err);
  }
}

async function handleIndividualNotification(userId, notifId, data) {
  const { title, body, action, uid, itemId, imageUrl } = data;
  if (action === 'chat') {
    // Chat push notifications are already sent directly by chat service or client
    return;
  }

  try {
    const tokenDoc = await db.collection('fcm_tokens').doc(userId).get();
    if (!tokenDoc.exists) {
      console.log(`No FCM token registered for user ${userId}. Skipping individual notification ${notifId}.`);
      return;
    }
    const token = tokenDoc.data()?.token;
    if (!token) return;

    const message = {
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

    await messaging.send(message);
    console.log(`Individual notification ${notifId} sent successfully to user ${userId}`);
  } catch (err) {
    console.error(`Error sending individual notification ${notifId} to user ${userId}:`, err);
  }
}
