// Closing an account removes what the person owns, takes them out of their chats, and
// asks the media server to remove their files. Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/account_erasure"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
if (!getApps().length) initializeApp({ projectId: PROJECT_ID });

const {
  eraseFromChats,
  eraseOwnedDocuments,
  eraseStorageFiles,
  purgeAccountOnMediaServer,
} = require('../src/lib/accountErasure');

describe('closing an account erases what the person owns', () => {
  let db;

  beforeAll(() => {
    db = getFirestore();
  });

  beforeEach(async () => {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
    delete process.env.MEDIA_PURGE_KEY;
  });

  test('the documents that name the person go, and other people keep theirs', async () => {
    await db.doc('trip_logs/t1').set({ authorId: 'uid-a' });
    await db.doc('trip_logs/t2').set({ authorId: 'uid-b' });
    await db.doc('likes/l1').set({ userId: 'uid-a' });
    await db.doc('follows/f1').set({ followerId: 'uid-a' });
    await db.doc('calls/c1').set({ callerId: 'uid-b', calleeId: 'uid-a' });
    await db.doc('users/uid-a').set({ name: 'Ann' });
    await db.doc('users/uid-a/notifications/n1').set({ body: 'hello' });
    await db.doc('explorer_profiles/uid-a').set({ tier: 'explorer' });

    const deleted = await eraseOwnedDocuments(db, 'uid-a');

    expect(deleted).toBe(4);
    expect((await db.doc('trip_logs/t1').get()).exists).toBe(false);
    expect((await db.doc('trip_logs/t2').get()).exists).toBe(true);
    expect((await db.doc('likes/l1').get()).exists).toBe(false);
    expect((await db.doc('follows/f1').get()).exists).toBe(false);
    expect((await db.doc('calls/c1').get()).exists).toBe(false);
    expect((await db.doc('users/uid-a').get()).exists).toBe(false);
    expect((await db.doc('users/uid-a/notifications/n1').get()).exists).toBe(false);
    expect((await db.doc('explorer_profiles/uid-a').get()).exists).toBe(false);
  });

  test('a direct chat loses the messages the person sent and their place in it', async () => {
    await db.doc('chats/c1').set({
      participants: ['uid-a', 'uid-b'],
      memberEmails: { 'uid-a': 'a@x.com', 'uid-b': 'b@x.com' },
      lastSenderId: 'uid-a',
      lastMessage: 'bye',
    });
    await db.doc('chats/c1/messages/m1').set({ senderId: 'uid-a', text: 'bye' });
    await db.doc('chats/c1/messages/m2').set({ senderId: 'uid-b', text: 'hello' });

    const result = await eraseFromChats(db, 'uid-a');

    expect(result).toEqual({ chats: 1, messages: 1 });
    expect((await db.doc('chats/c1/messages/m1').get()).exists).toBe(false);
    expect((await db.doc('chats/c1/messages/m2').get()).exists).toBe(true);
    const chat = (await db.doc('chats/c1').get()).data();
    expect(chat.participants).toEqual(['uid-b']);
    expect(chat.memberEmails).toEqual({ 'uid-b': 'b@x.com' });
    expect(chat.lastSenderId).toBe('');
    expect(chat.lastMessage).toBe('');
  });

  test('the media server is asked to remove the files and the chat data', async () => {
    process.env.MEDIA_PURGE_KEY = 'purge-key';
    const fetchMock = jest.fn(async () => ({
      ok: true,
      json: async () => ({ paths: ['t1/posts/a.jpg'] }),
    }));
    global.fetch = fetchMock;

    const paths = await purgeAccountOnMediaServer('uid-a', 'a@x.com');

    expect(paths).toEqual(['t1/posts/a.jpg']);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toMatch(/\/purge\/account$/);
    expect(init.headers['X-Purge-Key']).toBe('purge-key');
    expect(JSON.parse(init.body)).toEqual({ uid: 'uid-a', email: 'a@x.com' });
  });

  test('a media server that refuses the purge fails the closing, so it is retried', async () => {
    process.env.MEDIA_PURGE_KEY = 'purge-key';
    global.fetch = jest.fn(async () => ({ ok: false, status: 503 }));
    await expect(purgeAccountOnMediaServer('uid-a', 'a@x.com')).rejects.toThrow(/HTTP 503/);
  });

  test('without the purge key the closing fails rather than skipping the media', async () => {
    delete process.env.MEDIA_PURGE_KEY;
    await expect(purgeAccountOnMediaServer('uid-a', 'a@x.com')).rejects.toThrow(/MEDIA_PURGE_KEY/);
  });

  test('the storage folder is removed by prefix, and a failure is not swallowed', async () => {
    const deleteFiles = jest.fn(async () => undefined);
    await eraseStorageFiles({ deleteFiles }, 'uid-a');
    expect(deleteFiles).toHaveBeenCalledWith({ prefix: 'users/uid-a/' });

    const failing = { deleteFiles: jest.fn(async () => { throw new Error('bucket down'); }) };
    await expect(eraseStorageFiles(failing, 'uid-a')).rejects.toThrow('bucket down');
  });
});
