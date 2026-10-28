import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendTourCommentNotification
 *
 * Triggered when a member comments on a post:
 * tours/{tourId}/posts/{postId}/comments/{commentId}
 * Notifies the post author (if not the commenter).
 */
export const sendTourCommentNotification = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/posts/{postId}/comments/{commentId}')
  .onCreate(async (snap, context) => {
    const comment = snap.data();
    if (!comment) return;

    const { tourId, postId, commentId } = context.params;
    const commenterEmail = String(comment.authorEmail ?? '').trim().toLowerCase();
    if (!commenterEmail) return;

    try {
      const postSnap = await admin
        .firestore()
        .collection('tours')
        .doc(tourId)
        .collection('posts')
        .doc(postId)
        .get();
      if (!postSnap.exists) return;
      const post = postSnap.data();
      const postAuthorEmail = String(post?.authorEmail ?? '').trim().toLowerCase();

      // Only notify if someone else commented on the author's post
      if (!postAuthorEmail || postAuthorEmail === commenterEmail) return;

      const commenterName =
        typeof comment.authorName === 'string' && comment.authorName.trim() !== ''
          ? comment.authorName.trim()
          : 'A traveler';
      const text =
        typeof comment.text === 'string' && comment.text.trim() !== ''
          ? comment.text.trim()
          : 'Commented on your post';
      const body = text.length > 100 ? `${text.slice(0, 99)}…` : text;

      const targets = await pushTargetsForUids(await uidsForEmails([postAuthorEmail]));
      await sendPush(
        targets,
        {
          notification: {
            title: `${commenterName} commented on your post`,
            body,
          },
          data: {
            action: 'comment',
            tourId,
            postId,
            commentId,
          },
        },
        `sendTourCommentNotification ${commentId}`,
      );
    } catch (e) {
      console.error('[sendTourCommentNotification] Failed to send comment push:', e);
    }
  });
