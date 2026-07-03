import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

export const promoteToRegionExpert = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    // Must be authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    // Caller must be a pioneer tier to promote others
    const callerDoc = await db
      .collection('explorer_profiles')
      .doc(context.auth.uid)
      .get();
    const callerTier = callerDoc.data()?.tier;
    if (!['pioneer'].includes(callerTier)) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only pioneers can promote users',
      );
    }

    const { targetUid, newTier } = data;
    if (
      !targetUid ||
      !['regionExpert', 'verified', 'community'].includes(newTier)
    ) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid targetUid or newTier',
      );
    }

    // Promote the target user
    await db.collection('explorer_profiles').doc(targetUid).update({
      tier: newTier,
      promotedBy: context.auth.uid,
      promotedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Write audit log
    await db.collection('admin_audit_logs').add({
      action: 'user_promoted',
      targetUid,
      newTier,
      performedBy: context.auth.uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, targetUid, newTier };
  });
