import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import { leaveAllTours } from './lib/accountTours';
import {
  eraseFromChats,
  eraseOwnedDocuments,
  eraseStorageFiles,
  purgeAccountOnMediaServer,
} from './lib/accountErasure';
import { purgeCdnPaths } from './lib/cdnPurge';

const db = admin.firestore();

export const gdprDeleteUser = functions
  .runWith({ secrets: ['MEDIA_PURGE_KEY'] })
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const uid = context.auth.uid;
    // A person without an email is listed under the uid-based address the app uses.
    const email = context.auth.token.email ?? `${uid}@bhromon.app`;

    // Every step below can run again, so a failure at any point is cleared by closing
    // the account again. The sign-in account is deleted last, after everything else.
    // Tours come first: a tour they own passes to another member, and what they put
    // into each tour is purged with their membership.
    await leaveAllTours(db, email);
    await eraseOwnedDocuments(db, uid);
    await eraseFromChats(db, uid);
    const removedPaths = await purgeAccountOnMediaServer(uid, email);
    await eraseStorageFiles(admin.storage().bucket(), uid);

    // Cached copies of the deleted media are a convenience to clear, not a reason to
    // fail the closing, so a CDN failure is logged and left for the cache to expire.
    try {
      await purgeCdnPaths(removedPaths);
    } catch (error) {
      console.error('CDN purge after account closing failed:', error);
    }

    await admin.auth().deleteUser(uid);

    await db.collection('admin_audit_logs').add({
      action: 'gdpr_user_deleted',
      targetUid: uid,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  });
