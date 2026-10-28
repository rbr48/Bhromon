import * as functions from 'firebase-functions';
import {
  activeMemberEmails,
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * sendTourPostNotification
 *
 * Triggered on every new post in tours/{tourId}/posts/{postId}.
 * Pushes to all active members of the tour, excluding the author.
 */
export const sendTourPostNotification = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/posts/{postId}')
  .onCreate(async (snap, context) => {
    const post = snap.data();
    if (!post) return;

    const { tourId, postId } = context.params;
    const authorEmail = String(post.authorEmail ?? '').trim().toLowerCase();
    if (!authorEmail) return;

    try {
      const members = await activeMemberEmails(tourId, authorEmail);
      if (members.length === 0) return;

      const authorName =
        typeof post.authorName === 'string' && post.authorName.trim() !== ''
          ? post.authorName.trim()
          : 'A member';
      const isReel = post.isReel === true;
      const caption =
        typeof post.caption === 'string' && post.caption.trim() !== ''
          ? post.caption.trim()
          : '';
      const firstImage =
        Array.isArray(post.images) && post.images.length > 0
          ? String(post.images[0])
          : undefined;

      const title = `${authorName} shared a new ${isReel ? 'reel' : 'photo'}`;
      const body = caption
        ? (caption.length > 100 ? `${caption.slice(0, 99)}…` : caption)
        : (isReel ? '🎬 Watch reel' : '📷 View photo in trip feed');

      const targets = await pushTargetsForUids(await uidsForEmails(members));
      await sendPush(
        targets,
        {
          notification: {
            title,
            body,
            imageUrl: firstImage,
          },
          data: {
            action: 'post',
            tourId,
            postId,
          },
        },
        `sendTourPostNotification ${postId}`,
      );
    } catch (e) {
      console.error('[sendTourPostNotification] Failed to send post push:', e);
    }
  });
