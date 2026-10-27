import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {
  activeMemberEmails,
  pushTargetsForUids,
  sendPush,
  uidsForEmails,
} from './lib/tourPush';

/**
 * The channel that pings everyone. Other channels ping only the members a
 * message mentions, so a busy group chat does not buzz every phone.
 */
const EVERYONE_CHANNEL_ID = 'emergency';

/** Push preview length, the same limit used for direct chats. */
const PREVIEW_LIMIT = 120;

/**
 * sendChannelNotification
 *
 * Triggered on every new message in tours/{tourId}/channels/{channelId}/messages.
 * Pushes to the active members the message reaches: everyone in the emergency
 * channel, otherwise only the members it mentions. The sender is never pinged.
 */
export const sendChannelNotification = functions
  .region('asia-south1')
  .firestore.document('tours/{tourId}/channels/{channelId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    if (!message) return;

    const { tourId, channelId, messageId } = context.params;
    const senderEmail = String(message.senderEmail ?? '').trim().toLowerCase();
    if (!senderEmail) return;

    try {
      const members = await activeMemberEmails(tourId, senderEmail);
      const recipients =
        channelId === EVERYONE_CHANNEL_ID
          ? members
          : members.filter((email) => mentionsOf(message).has(email));
      if (recipients.length === 0) return;

      const channelSnap = await admin
        .firestore()
        .collection('tours')
        .doc(tourId)
        .collection('channels')
        .doc(channelId)
        .get();
      const channelName = nonEmpty(channelSnap.data()?.name) ?? channelId;
      const senderName = nonEmpty(message.senderName) ?? 'A member';

      const targets = await pushTargetsForUids(await uidsForEmails(recipients));
      await sendPush(
        targets,
        {
          notification: {
            title: `${senderName} in ${channelName}`,
            body: previewOf(message),
          },
          data: { action: 'channel', tourId, channelId, messageId },
          android: {
            priority: channelId === EVERYONE_CHANNEL_ID ? 'high' : 'normal',
          },
        },
        `sendChannelNotification ${messageId}`,
      );
    } catch (e) {
      console.error('[sendChannelNotification] Could not send pushes:', e);
    }
  });

function mentionsOf(message: admin.firestore.DocumentData): Set<string> {
  const list: unknown[] = Array.isArray(message.mentions) ? message.mentions : [];
  return new Set(list.map((m) => String(m).trim().toLowerCase()));
}

function nonEmpty(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : undefined;
}

/** The text of the message, or a label for a photo, video, poll or expense. */
function previewOf(message: admin.firestore.DocumentData): string {
  let body = nonEmpty(message.text);
  if (!body) {
    const attachments: unknown[] = Array.isArray(message.attachments) ? message.attachments : [];
    const first = attachments[0] as { isVideo?: unknown } | undefined;
    if (first && first.isVideo === true) body = '🎬 Video';
    else if (attachments.length > 0) body = '📷 Photo';
    else if (message.kind === 'poll') body = '📊 Poll';
    else if (message.kind === 'expense') body = '💸 Expense';
    else body = 'New message';
  }
  return body.length > PREVIEW_LIMIT ? body.substring(0, PREVIEW_LIMIT - 1) + '…' : body;
}
