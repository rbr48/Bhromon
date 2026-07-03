import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

async function _sendDecayFCM(uid: string) {
  const tokenDoc = await db.collection('fcm_tokens').doc(uid).get();
  if (!tokenDoc.exists) return;
  const token = tokenDoc.data()?.token;
  if (!token) return;

  const message = {
    notification: {
      title: 'Tip Stale Alert',
      body: 'Your pro tip has gone stale. Please re-confirm it!',
    },
    data: {
      action: 're_confirm_tips',
      uid: uid,
    },
    token: token,
  };

  try {
    await admin.messaging().send(message);
  } catch (e) {
    console.error('Error sending FCM:', e);
  }
}

export const decayFreshness = functions
  .region('asia-south1')
  .pubsub.schedule('0 20 * * *')  // 02:00 BST (UTC+6)
  .timeZone('Asia/Dhaka')
  .onRun(async (context) => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 180);

    const stale = await db.collection('pro_tips')
      .where('lastConfirmed', '<', cutoff)
      .where('decayStatus', '!=', 'stale')
      .get();

    const batch = db.batch();
    const authorIds = new Set<string>();

    stale.forEach(doc => {
      batch.update(doc.ref, { decayStatus: 'stale' });
      authorIds.add(doc.data().authorId);
    });

    await batch.commit();
    for (const uid of authorIds) {
      await _sendDecayFCM(uid);
    }
    console.log(`Marked ${stale.size} tips stale, notified ${authorIds.size} authors`);
  });
