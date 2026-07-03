import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

async function _notifyFounders(targetId: string, targetType: string) {
  const pioneers = await db.collection('explorer_profiles')
    .where('tier', '==', 'pioneer').get();

  const tokens: string[] = [];
  for (const doc of pioneers.docs) {
    const tokenDoc = await db.collection('fcm_tokens').doc(doc.id).get();
    const tokenData = tokenDoc.data();
    if (tokenDoc.exists && tokenData?.token) {
      tokens.push(tokenData.token);
    }
  }

  if (tokens.length === 0) return;

  const payload = {
    notification: {
      title: '🛡️ Safety Flag Alert',
      body: `A ${targetType} (ID: ${targetId}) was immediately hidden due to a safety flag.`,
    },
    data: {
      action: 'safety_review',
      targetId: targetId,
      targetType: targetType,
    }
  };

  try {
    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      ...payload
    });
    console.log(`Successfully sent safety notification to ${response.successCount} founders.`);
  } catch (e) {
    console.error('Error sending multicast FCM notification:', e);
  }
}

export const moderateContent = functions
  .region('asia-south1')
  .firestore.document('trust_events/{eventId}')
  .onCreate(async (snap) => {
    const eventData = snap.data();
    if (!eventData) return;

    const { type, targetId, targetType, actorId } = eventData;
    
    // Ignore penalty events to prevent infinite loops
    if (type === 'spam_flag_received' || type === 'safety_flag_received') return;
    if (type !== 'spam_flag' && type !== 'safety_flag') return;

    const collection = targetType === 'trip_log' ? 'trip_logs' : 'pro_tips';
    const ref = db.collection(collection).doc(targetId);
    const doc = await ref.get();

    if (!doc.exists) return;
    const authorId = doc.data()?.authorId;

    // Apply immediate client action & alerts
    if (type === 'safety_flag') {
      await ref.update({ hidden: true, hiddenReason: 'safety_flag' });
      await _notifyFounders(targetId, targetType);
    }

    // Write penalty event targeting the content author
    if (authorId) {
      const penaltyWeight = type === 'safety_flag' ? -10 : -5;
      const penaltyType = type === 'safety_flag' ? 'safety_flag_received' : 'spam_flag_received';

      await db.collection('trust_events').add({
        type: penaltyType,
        targetUid: authorId,
        actorId: actorId || 'system',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        weight: penaltyWeight,
        targetId: targetId,
        targetType: targetType
      });
    }

    // Check if spam flags reached threshold
    if (type === 'spam_flag') {
      const spamCountSnap = await db.collection('trust_events')
        .where('targetId', '==', targetId)
        .where('type', '==', 'spam_flag')
        .count()
        .get();
      
      const spamCount = spamCountSnap.data().count;

      if (spamCount >= 2) {
        await ref.update({ hidden: true, hiddenReason: 'spam_threshold' });
      }
    }
  });
