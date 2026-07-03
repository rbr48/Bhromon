import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();
const storage = admin.storage();

export const gdprDeleteUser = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const uid = context.auth.uid;
    const batch = db.batch();

    // Delete all primary user documents in a single atomic batch
    batch.delete(db.collection('explorer_profiles').doc(uid));
    batch.delete(db.collection('users').doc(uid));
    batch.delete(db.collection('explorer_scores').doc(uid));
    batch.delete(db.collection('fcm_tokens').doc(uid));

    await batch.commit();

    // Delete user-owned storage files (best-effort; non-fatal on error)
    try {
      const bucket = storage.bucket();
      await bucket.deleteFiles({ prefix: `users/${uid}/` });
    } catch (e) {
      console.error('Storage deletion error (non-fatal):', e);
    }

    // Remove Firebase Auth account
    await admin.auth().deleteUser(uid);

    // Write GDPR audit record
    await db.collection('admin_audit_logs').add({
      action: 'gdpr_user_deleted',
      targetUid: uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  });
