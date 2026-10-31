import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import sharp from 'sharp';

const storage = admin.storage();
const db = admin.firestore();

/**
 * generateChatThumbnail
 *
 * Triggered whenever a file is uploaded to `chat_media/{chatId}/{fileName}`.
 * - Resizes images to max 400×400 WebP for fast thumbnail display in the chat bubble.
 * - Writes the thumbnail to `chat_media_thumbs/{chatId}/{fileName.webp}`.
 * - Updates the Firestore message document with `thumbnailUrl`.
 *
 * Videos are skipped (thumbnailing requires ffmpeg; left as a future enhancement).
 */
export const generateChatThumbnail = functions
  .region('asia-south1')
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .storage.object()
  .onFinalize(async (object) => {
    const filePath = object.name;
    const contentType = object.contentType || '';

    // Only process chat_media uploads
    if (!filePath || !filePath.startsWith('chat_media/')) return;
    // Only process images
    if (!contentType.startsWith('image/')) return;
    // Skip already-generated thumbnails to avoid infinite loops
    if (filePath.includes('_thumb')) return;

    const bucket = storage.bucket(object.bucket);

    // Parse chatId and fileName from path: chat_media/{chatId}/{fileName}
    const segments = filePath.split('/');
    if (segments.length < 3) return;
    const chatId = segments[1];
    const fileName = segments.slice(2).join('/');
    const fileNameNoExt = path.parse(fileName).name;

    const thumbFileName = `${fileNameNoExt}_thumb.webp`;
    const thumbDestPath = `chat_media_thumbs/${chatId}/${thumbFileName}`;
    const tempInputPath = path.join(os.tmpdir(), `input_${fileNameNoExt}`);
    const tempOutputPath = path.join(os.tmpdir(), `thumb_${fileNameNoExt}.webp`);

    try {
      // 1. Download the original file
      await bucket.file(filePath).download({ destination: tempInputPath });

      // 2. Resize to 400×400 max WebP (maintains aspect ratio)
      await sharp(tempInputPath)
        .resize(400, 400, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 80 })
        .toFile(tempOutputPath);

      // 3. Upload the thumbnail
      await bucket.upload(tempOutputPath, {
        destination: thumbDestPath,
        metadata: {
          contentType: 'image/webp',
          cacheControl: 'public, max-age=31536000', // 1 year CDN cache
        },
      });

      // 4. Make the thumbnail publicly readable and get its URL
      const thumbFile = bucket.file(thumbDestPath);
      await thumbFile.makePublic();
      const thumbUrl = thumbFile.publicUrl();

      // 5. Locate the Firestore message document via chatId and the original
      //    file URL. We query for the message whose mediaUrl contains the filename.
      const messagesRef = db
        .collection('chats')
        .doc(chatId)
        .collection('messages');

      const querySnap = await messagesRef
        .where('mediaUrl', '>=', fileNameNoExt)
        .where('mediaUrl', '<=', fileNameNoExt + '\uf8ff')
        .limit(5)
        .get();

      if (!querySnap.empty) {
        const batch = db.batch();
        for (const doc of querySnap.docs) {
          batch.update(doc.ref, { thumbnailUrl: thumbUrl });
        }
        await batch.commit();
        console.log(`[generateChatThumbnail] Updated ${querySnap.size} message(s) with thumbnailUrl for chatId=${chatId}`);
      } else {
        // Fallback: update the most recent image message in the chat
        const recentSnap = await messagesRef
          .where('type', '==', 'image')
          .orderBy('timestamp', 'desc')
          .limit(1)
          .get();
        if (!recentSnap.empty && !recentSnap.docs[0].data().thumbnailUrl) {
          await recentSnap.docs[0].ref.update({ thumbnailUrl: thumbUrl });
          console.log(`[generateChatThumbnail] Fallback: updated latest image message for chatId=${chatId}`);
        }
      }

      console.log(`[generateChatThumbnail] Thumbnail created: ${thumbDestPath}`);
    } catch (err) {
      console.error('[generateChatThumbnail] Error:', err);
    } finally {
      // Clean up temp files
      if (fs.existsSync(tempInputPath)) fs.unlinkSync(tempInputPath);
      if (fs.existsSync(tempOutputPath)) fs.unlinkSync(tempOutputPath);
    }
  });
