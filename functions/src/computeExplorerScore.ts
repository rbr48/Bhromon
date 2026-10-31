import * as functions from 'firebase-functions/v1';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const db = getFirestore();

export const computeExplorerScore = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated.',
      );
    }

    const uid = context.auth.uid;

    const snap = await db.collection('trust_events')
      .where('targetUid', '==', uid).get();

    let helpfulVotes = 0, tripsPublished = 0, endorsements = 0,
        spamFlags = 0, safetyFlags = 0;

    let score = 0;

    snap.forEach(doc => {
      const eventData = doc.data();
      const weight = eventData.weight || 0;
      score += weight;

      switch (eventData.type) {
        case 'helpful_vote':   helpfulVotes++;   break;
        case 'trip_published': tripsPublished++; break;
        case 'endorsement':    endorsements++;   break;
        case 'spam_flag_received':      spamFlags++;      break;
        case 'safety_flag_received':    safetyFlags++;    break;
      }
    });

    // Enforce minimum score of 0
    score = Math.max(0, score);

    // Check if the user is a pioneer to prevent demoting them
    const userDoc = await db.collection('explorer_profiles').doc(uid).get();
    const userData = userDoc.data();
    const isPioneer = userData?.isPioneer === true || userData?.tier === 'pioneer';

    let tier = score >= 500 ? 'regionExpert'
               : score >= 200 ? 'verified'
               : score >= 50  ? 'community'
               : 'unverified';

    if (isPioneer) {
      tier = 'pioneer';
    }

    // Update explorer_scores
    await db.collection('explorer_scores').doc(uid).set(
      { 
        score, 
        tier, 
        lastUpdated: FieldValue.serverTimestamp(),
        breakdown: { helpfulVotes, tripsPublished, endorsements, spamFlags, safetyFlags } 
      },
      { merge: true }
    );

    // Update explorer_profiles
    await db.collection('explorer_profiles').doc(uid).set(
      {
        tier,
        isPioneer: isPioneer,
        explorerScore: {
          value: score,
          tier: tier
        }
      },
      { merge: true }
    );

    return { success: true, score, tier };
  });
