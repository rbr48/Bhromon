import * as functions from 'firebase-functions/v1';
import {
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendTourReactionNotification
 *
 * Triggered when a post is updated:
 * tours/{tourId}/posts/{postId}
 * Detects newly added likes and notifies the author.
 */
export const sendTourReactionNotification = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/posts/{postId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    if (!beforeData || !afterData) return;

    const { tourId, postId } = context.params;
    const postAuthorEmail = String(afterData.authorEmail ?? '').trim().toLowerCase();
    if (!postAuthorEmail) return;

    const beforeLikes = new Set(
      Array.isArray(beforeData.likes) ? beforeData.likes.map(String) : [],
    );
    const afterLikes = Array.isArray(afterData.likes)
      ? afterData.likes.map(String)
      : [];

    // Find new likers who are not the author
    const newLikers = afterLikes.filter(
      (email) =>
        !beforeLikes.has(email) && email.toLowerCase() !== postAuthorEmail,
    );
    if (newLikers.length === 0) return;

    try {
      const liker = newLikers[0];
      const targets = await pushTargetsForUids(
        await uidsForEmails([postAuthorEmail]),
      );
      await sendPush(
        targets,
        {
          notification: {
            title: 'New like on your post ❤️',
            body: `${liker} liked your photo`,
          },
          data: {
            action: 'like',
            tourId,
            postId,
          },
        },
        `sendTourReactionNotification ${postId}`,
      );
    } catch (e) {
      console.error(
        '[sendTourReactionNotification] Failed to send reaction push:',
        e,
      );
    }
  });
