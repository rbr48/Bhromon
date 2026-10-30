import * as admin from 'firebase-admin';
import {
  chatIdFor,
  isChatStoragePath,
  isHttpUrl,
  storagePathFromUrl,
} from './lib/directChatPlan';
import { postToMediaPurge } from './lib/mediaPurgeClient';
import { FORMER_MEMBER_NAME } from './lib/tourContentPlan';

/**
 * Removal of a leaver's messages in one-to-one chats with the people still in
 * the tour. The other person's messages stay, as they do in a group channel.
 */

type Db = admin.firestore.Firestore;
type DocRef = admin.firestore.DocumentReference;
type DocSnap = admin.firestore.DocumentSnapshot;

/** The person who left: their account id, when they have one, and their email. */
export interface Member {
  uid: string | null;
  email: string;
}

/** The other active members of the tour, by account id and by email. */
export interface Peers {
  uids: string[];
  emails: string[];
}

/** What the media server needs to remove a person's chat messages and their files. */
export interface VpsChatRequest {
  uid: string | null;
  email: string;
  peerUids: string[];
  peerEmails: string[];
  /** Media URLs on the media server that the person's Firestore messages point to. */
  mediaUrls: string[];
}

/** The places outside Firestore a chat purge reaches. */
export interface ChatPurgeDeps {
  purgeStorageFile: (path: string) => Promise<void>;
  purgeVpsChats: (request: VpsChatRequest) => Promise<void>;
}

/** Removes a person's messages in chats shared with the given peers. */
export type ChatPurge = (
  db: Db,
  member: Member,
  peers: Peers,
) => Promise<void>;

/** `in` queries take at most ten values. */
const IN_LIMIT = 10;
const BATCH_LIMIT = 400;

function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

function millis(value: unknown): number {
  return value instanceof admin.firestore.Timestamp ? value.toMillis() : 0;
}

function participantsOf(doc: DocSnap): string[] {
  const list = doc.get('participants');
  return Array.isArray(list)
    ? list.filter((entry): entry is string => typeof entry === 'string')
    : [];
}

function isFirebaseStorageUrl(url: string): boolean {
  return url.includes('firebasestorage.googleapis.com');
}

async function deleteAll(db: Db, refs: DocRef[]): Promise<void> {
  for (const group of chunks(refs, BATCH_LIMIT)) {
    const batch = db.batch();
    for (const ref of group) batch.delete(ref);
    await batch.commit();
  }
}

/** The chats the person shared with one of the peers. */
async function sharedChats(
  db: Db,
  uid: string,
  peerUids: string[],
): Promise<DocRef[]> {
  const found = new Map<string, DocRef>();
  for (const peer of peerUids) {
    const ref = db.collection('chats').doc(chatIdFor(uid, peer));
    if ((await ref.get()).exists) found.set(ref.id, ref);
  }
  // A chat whose id does not follow the usual pattern is found by its participants.
  const peerSet = new Set(peerUids);
  const mine = await db
    .collection('chats')
    .where('participants', 'array-contains', uid)
    .get();
  for (const doc of mine.docs) {
    const others = participantsOf(doc).filter((p) => p !== uid);
    if (others.some((p) => peerSet.has(p))) found.set(doc.id, doc.ref);
  }
  return [...found.values()];
}

/**
 * Removes the person's messages from one chat and their files, then brings
 * the chat list's preview up to date. Returns the media-server URLs they used.
 */
async function purgeChatMessages(
  db: Db,
  chat: DocRef,
  member: Member,
  deps: ChatPurgeDeps,
): Promise<string[]> {
  const senders = [member.uid, member.email].filter(
    (id): id is string => typeof id === 'string' && id !== '',
  );
  const messages = chat.collection('messages');
  const mine = await messages.where('senderId', 'in', senders).get();
  if (mine.empty) return [];

  const mediaUrls: string[] = [];
  let newestGone = 0;
  for (const doc of mine.docs) {
    newestGone = Math.max(newestGone, millis(doc.get('timestamp')));
    for (const field of ['mediaUrl', 'thumbnailUrl']) {
      const url = doc.get(field);
      if (typeof url !== 'string' || url === '') continue;
      if (isFirebaseStorageUrl(url)) {
        const path = storagePathFromUrl(url);
        if (path !== null && isChatStoragePath(path)) {
          await deps.purgeStorageFile(path);
        }
      } else if (isHttpUrl(url)) {
        mediaUrls.push(url);
      }
    }
  }
  await deleteAll(db, mine.docs.map((doc) => doc.ref));
  await refreshPreview(chat, newestGone);
  await replaceQuotes(chat, senders);
  await scrubMessageFields(chat, senders);
  return mediaUrls;
}

/**
 * The messages that stay still name the person in their lists of who starred or
 * deleted them, and in their reactions. Those entries are taken out.
 */
async function scrubMessageFields(chat: DocRef, senders: string[]): Promise<void> {
  const messages = chat.collection('messages');
  const found = new Map<string, DocSnap>();
  for (const sender of senders) {
    const queries = [
      messages.where('deletedFor', 'array-contains', sender),
      messages.where('starredBy', 'array-contains', sender),
      messages.where(new admin.firestore.FieldPath('reactions', sender), '!=', null),
    ];
    for (const query of queries) {
      for (const doc of (await query.get()).docs) found.set(doc.ref.path, doc);
    }
  }
  for (const doc of found.values()) {
    const fields: Record<string, unknown> = {};
    for (const list of ['deletedFor', 'starredBy']) {
      const values = doc.get(list);
      if (Array.isArray(values) && values.some((v) => senders.includes(v))) {
        fields[list] = values.filter((v) => !senders.includes(v));
      }
    }
    const reactions = doc.get('reactions');
    if (
      reactions !== null &&
      typeof reactions === 'object' &&
      !Array.isArray(reactions) &&
      senders.some((sender) => sender in reactions)
    ) {
      fields.reactions = Object.fromEntries(
        Object.entries(reactions).filter(([key]) => !senders.includes(key)),
      );
    }
    if (Object.keys(fields).length > 0) await doc.ref.update(fields);
  }
}

/**
 * A reply in the peer's messages quotes the person's message, text and name
 * included. The quote keeps its message id, and the rest is replaced.
 */
async function replaceQuotes(chat: DocRef, senders: string[]): Promise<void> {
  const quotes = await chat
    .collection('messages')
    .where('replyTo.senderId', 'in', senders)
    .get();
  for (const doc of quotes.docs) {
    const quoted = doc.get('replyTo') ?? {};
    await doc.ref.update({
      replyTo: {
        messageId: quoted.messageId ?? null,
        senderId: '',
        senderName: FORMER_MEMBER_NAME,
        text: '',
        type: 'text',
      },
    });
  }
}

/**
 * The chat list shows the newest message. When the newest one was the
 * person's, it shows the newest message that is left, or nothing.
 */
async function refreshPreview(chat: DocRef, newestGone: number): Promise<void> {
  const snap = await chat.get();
  if (millis(snap.get('lastMessageTime')) > newestGone) return;

  const remaining = await chat
    .collection('messages')
    .orderBy('timestamp', 'desc')
    .limit(1)
    .get();
  if (remaining.empty) {
    await chat.update({
      lastMessage: admin.firestore.FieldValue.delete(),
      lastMessageTime: admin.firestore.FieldValue.delete(),
    });
    return;
  }
  const newest = remaining.docs[0];
  const text = newest.get('text');
  await chat.update({
    lastMessage: typeof text === 'string' ? text : '',
    lastMessageTime:
      newest.get('timestamp') ?? admin.firestore.FieldValue.delete(),
  });
}

/**
 * The notification copies of the chats: the person's own inbox, and the
 * inboxes of the people they wrote to, which hold the message text.
 */
async function purgeNotifications(
  db: Db,
  uid: string,
  chatIds: string[],
): Promise<void> {
  if (chatIds.length === 0) return;
  const inChats = new Set(chatIds);

  const inbox = db.collection('users').doc(uid).collection('notifications');
  for (const group of chunks(chatIds, IN_LIMIT)) {
    const copies = await inbox.where('chatId', 'in', group).get();
    await deleteAll(db, copies.docs.map((doc) => doc.ref));
  }

  const sent = await db
    .collectionGroup('notifications')
    .where('uid', '==', uid)
    .get();
  await deleteAll(
    db,
    sent.docs
      .filter((doc) => inChats.has(String(doc.get('chatId') ?? '')))
      .map((doc) => doc.ref),
  );
}

/** Call records between the person and a peer. They carry the caller's name and network details. */
async function purgeCalls(db: Db, uid: string, peerUids: string[]): Promise<void> {
  const peers = new Set(peerUids);
  const asCaller = await db.collection('calls').where('callerId', '==', uid).get();
  const asCallee = await db.collection('calls').where('calleeId', '==', uid).get();
  for (const doc of [...asCaller.docs, ...asCallee.docs]) {
    const other =
      doc.get('callerId') === uid ? doc.get('calleeId') : doc.get('callerId');
    if (typeof other === 'string' && peers.has(other)) {
      await db.recursiveDelete(doc.ref);
    }
  }
}

/**
 * Removes the person's messages in every one-to-one chat they share with a
 * member of the tour, along with the notifications and calls that carry them.
 * Nothing outside those chats is touched.
 */
export async function purgeDirectChats(
  db: Db,
  member: Member,
  peers: Peers,
  deps: ChatPurgeDeps,
): Promise<void> {
  const peerUids = peers.uids.filter((uid) => uid !== member.uid);
  if (peerUids.length === 0 && peers.emails.length === 0) return;

  const mediaUrls: string[] = [];
  if (member.uid !== null) {
    const chatIds: string[] = [];
    for (const chat of await sharedChats(db, member.uid, peerUids)) {
      chatIds.push(chat.id);
      mediaUrls.push(...(await purgeChatMessages(db, chat, member, deps)));
    }
    await purgeNotifications(db, member.uid, chatIds);
    await purgeCalls(db, member.uid, peerUids);
  }

  // The chats the media server keeps: its own messages and files.
  await deps.purgeVpsChats({
    uid: member.uid,
    email: member.email,
    peerUids: peers.uids,
    peerEmails: peers.emails,
    mediaUrls,
  });
}

/** The production wiring: Storage through Admin, and the VPS through its purge route. */
export function productionChatDeps(): ChatPurgeDeps {
  return {
    purgeStorageFile: async (path) => {
      await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
    },
    purgeVpsChats: async (request) => {
      await postToMediaPurge<unknown>('/chat', request);
    },
  };
}
