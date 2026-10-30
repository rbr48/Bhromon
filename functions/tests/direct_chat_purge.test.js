// A leaver's messages leave the one-to-one chats they shared with the tour, and nothing else:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/direct_chat_purge"
const admin = require('firebase-admin');
const { purgeDirectChats } = require('../src/directChatPurge');
const { chatIdFor } = require('../src/lib/directChatPlan');
const { FORMER_MEMBER_NAME } = require('../src/lib/tourContentPlan');

const PROJECT_ID = 'bhromon-rules-test-project';
const LEAVER = 'leaver@x.com';
const PEER = 'friend@x.com';
const LEAVER_UID = 'uid_leaver';
const PEER_UID = 'uid_friend';
const STRANGER_UID = 'uid_stranger';
const CHAT = chatIdFor(LEAVER_UID, PEER_UID);
const OTHER_CHAT = chatIdFor(LEAVER_UID, STRANGER_UID);
const FILE_PATH = `chat_docs/${CHAT}/file.pdf`;

jest.setTimeout(120000);

let db;

function ts(seconds) {
  return admin.firestore.Timestamp.fromMillis(seconds * 1000);
}

async function clearEmulator() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
}

async function exists(path) {
  return (await db.doc(path).get()).exists;
}

async function read(path) {
  return (await db.doc(path).get()).data();
}

async function seed() {
  const set = (path, data) => db.doc(path).set(data);

  // The chat with the peer: the leaver's messages, and the peer's reply, which is the newest.
  await set(`chats/${CHAT}`, {
    participants: [LEAVER_UID, PEER_UID],
    lastMessage: 'Photo',
    lastMessageTime: ts(3),
  });
  await set(`chats/${CHAT}/messages/m1`, { senderId: LEAVER_UID, text: 'Hello', type: 'text', timestamp: ts(1) });
  // The peer's reply quotes the leaver's first message, with the leaver's name and text.
  await set(`chats/${CHAT}/messages/m2`, {
    senderId: PEER_UID,
    text: 'Hi back',
    type: 'text',
    timestamp: ts(2),
    replyTo: { messageId: 'm1', senderId: LEAVER_UID, senderName: 'Leaver', text: 'Hello', type: 'text' },
    // The leaver hid this reply and starred it, and reacted to it.
    deletedFor: [LEAVER_UID],
    starredBy: [LEAVER_UID, PEER_UID],
    reactions: { [LEAVER_UID]: '👍', [PEER_UID]: '❤️' },
  });
  await set(`chats/${CHAT}/messages/m3`, {
    senderId: LEAVER_UID,
    text: 'Photo',
    type: 'document',
    mediaUrl: `https://firebasestorage.googleapis.com/v0/b/bhromon.appspot.com/o/chat_docs%2F${CHAT}%2Ffile.pdf?alt=media&token=t`,
    timestamp: ts(3),
  });
  // A message the leaver sent under their email, before accounts were keyed by uid.
  await set(`chats/${CHAT}/messages/m4`, { senderId: LEAVER, text: 'old', type: 'text', timestamp: ts(0.5) });
  // A photo kept on the media server.
  await set(`chats/${CHAT}/messages/m5`, {
    senderId: LEAVER_UID,
    text: '',
    type: 'image',
    mediaUrl: 'https://bhromon.fun/media/chat_media/x.jpg',
    timestamp: ts(0.7),
  });

  // A chat with someone outside the tour: it is not touched.
  await set(`chats/${OTHER_CHAT}`, {
    participants: [LEAVER_UID, STRANGER_UID],
    lastMessage: 'Hello',
    lastMessageTime: ts(1),
  });
  await set(`chats/${OTHER_CHAT}/messages/m1`, { senderId: LEAVER_UID, text: 'Hello', type: 'text', timestamp: ts(1) });

  // Notification copies: the peer's inbox holds the leaver's message, the leaver's inbox holds the peer's.
  await set(`users/${PEER_UID}/notifications/n1`, { uid: LEAVER_UID, chatId: CHAT, body: 'Hello' });
  await set(`users/${LEAVER_UID}/notifications/n2`, { uid: PEER_UID, chatId: CHAT, body: 'Hi back' });
  await set(`users/${PEER_UID}/notifications/n3`, { uid: LEAVER_UID, chatId: OTHER_CHAT, body: 'Hello' });

  // Calls: one with the peer, one with someone outside the tour.
  await set('calls/c1', {
    callerId: LEAVER_UID,
    calleeId: PEER_UID,
    callerName: 'Leaver',
    status: 'ended',
  });
  await set('calls/c1/offerCandidates/x1', { candidate: 'candidate:1 1 udp 1 10.0.0.1 9 typ host' });
  await set('calls/c2', { callerId: LEAVER_UID, calleeId: STRANGER_UID, status: 'ended' });
}

function fakes() {
  const calls = { storage: [], vps: [] };
  return {
    calls,
    deps: {
      purgeStorageFile: async (path) => {
        calls.storage.push(path);
      },
      purgeVpsChats: async (request) => {
        calls.vps.push(request);
      },
    },
  };
}

const leaver = { uid: LEAVER_UID, email: LEAVER };
const peers = { uids: [PEER_UID], emails: [PEER] };

beforeAll(() => {
  if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
  db = admin.firestore();
});

beforeEach(async () => {
  await clearEmulator();
  await seed();
});

describe('direct chat purge', () => {
  it('removes the leaver’s messages in the shared chat and keeps the peer’s', async () => {
    const { calls, deps } = fakes();
    await purgeDirectChats(db, leaver, peers, deps);

    expect(await exists(`chats/${CHAT}/messages/m1`)).toBe(false);
    expect(await exists(`chats/${CHAT}/messages/m3`)).toBe(false);
    expect(await exists(`chats/${CHAT}/messages/m4`)).toBe(false);
    expect(await exists(`chats/${CHAT}/messages/m5`)).toBe(false);
    expect((await read(`chats/${CHAT}/messages/m2`)).text).toBe('Hi back');
    expect((await read(`chats/${CHAT}/messages/m2`)).replyTo).toEqual({
      messageId: 'm1',
      senderId: '',
      senderName: FORMER_MEMBER_NAME,
      text: '',
      type: 'text',
    });
    expect(await read(`chats/${CHAT}/messages/m2`)).toMatchObject({
      deletedFor: [],
      starredBy: [PEER_UID],
      reactions: { [PEER_UID]: '❤️' },
    });

    // The newest message was the leaver's, so the preview shows the peer's.
    const chat = await read(`chats/${CHAT}`);
    expect(chat.lastMessage).toBe('Hi back');
    expect(chat.lastMessageTime.toMillis()).toBe(2000);
  });

  it('removes the Storage file and hands the media-server photo on, with the peers', async () => {
    const { calls, deps } = fakes();
    await purgeDirectChats(db, leaver, peers, deps);

    expect(calls.storage).toEqual([FILE_PATH]);
    expect(calls.vps).toEqual([
      {
        uid: LEAVER_UID,
        email: LEAVER,
        peerUids: [PEER_UID],
        peerEmails: [PEER],
        mediaUrls: ['https://bhromon.fun/media/chat_media/x.jpg'],
      },
    ]);
  });

  it('leaves a chat with someone outside the tour as it was', async () => {
    const { deps } = fakes();
    await purgeDirectChats(db, leaver, peers, deps);

    expect(await exists(`chats/${OTHER_CHAT}/messages/m1`)).toBe(true);
    expect(await read(`chats/${OTHER_CHAT}`)).toMatchObject({ lastMessage: 'Hello' });
  });

  it('removes the notification copies of the shared chat, and keeps the others', async () => {
    const { deps } = fakes();
    await purgeDirectChats(db, leaver, peers, deps);

    expect(await exists(`users/${PEER_UID}/notifications/n1`)).toBe(false);
    expect(await exists(`users/${LEAVER_UID}/notifications/n2`)).toBe(false);
    expect(await exists(`users/${PEER_UID}/notifications/n3`)).toBe(true);
  });

  it('removes the calls with the peer, with their candidates, and keeps the rest', async () => {
    const { deps } = fakes();
    await purgeDirectChats(db, leaver, peers, deps);

    expect(await exists('calls/c1')).toBe(false);
    expect(await exists('calls/c1/offerCandidates/x1')).toBe(false);
    expect(await exists('calls/c2')).toBe(true);
  });

  it('a leaver with no account has no Firestore chats, but the media server still gets the request', async () => {
    const { calls, deps } = fakes();
    await purgeDirectChats(db, { uid: null, email: LEAVER }, peers, deps);

    expect(await exists(`chats/${CHAT}/messages/m1`)).toBe(true);
    expect(calls.storage).toEqual([]);
    expect(calls.vps).toHaveLength(1);
    expect(calls.vps[0]).toMatchObject({ uid: null, email: LEAVER, peerUids: [PEER_UID] });
  });

  it('with no other member in the tour, nothing is done', async () => {
    const { calls, deps } = fakes();
    await purgeDirectChats(db, leaver, { uids: [], emails: [] }, deps);

    expect(await exists(`chats/${CHAT}/messages/m1`)).toBe(true);
    expect(calls.vps).toEqual([]);
    expect(calls.storage).toEqual([]);
  });
});
