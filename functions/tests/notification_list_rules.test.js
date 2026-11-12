// The in-app notification list: a member reads, marks and clears only their own entries, and only
// admins touch the top-level notifications collection. Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/notification_list_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const ALICE = { uid: 'alice-uid', email: 'alice@x.com' };
const BOB = { uid: 'bob-uid', email: 'bob@x.com' };
const EVE = { uid: 'eve-uid', email: 'eve@x.com' };
const ADMIN = { uid: 'admin-uid', email: 'admin@x.com' };

describe('notification list rules', () => {
  jest.setTimeout(60000);
  let env;
  const db = (who) => env.authenticatedContext(who.uid, { email: who.email, email_verified: true }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 8080,
      },
    });
  }, 60000);

  afterAll(async () => {
    if (env) await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'users', ALICE.uid, 'notifications', 'n1'), {
        title: 'Notice', body: 'Tuesday', action: 'notice', tourId: 't1', read: false, timestamp: new Date(),
      });
      await setDoc(doc(f, 'explorer_profiles', ADMIN.uid), { tier: 'regionExpert' });
      await setDoc(doc(f, 'notifications', 'broadcast'), { title: 'Hello', body: 'All members' });
    });
  });

  const entry = (overrides = {}) => ({
    title: 'Hello',
    body: 'Body',
    action: 'chat',
    read: false,
    timestamp: serverTimestamp(),
    ...overrides,
  });

  test('a member reads their own entries', async () => {
    await assertSucceeds(getDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'n1')));
    await assertSucceeds(getDocs(collection(db(ALICE), 'users', ALICE.uid, 'notifications')));
  });

  test('nobody else reads a member\'s entries, and nobody signed out does', async () => {
    await assertFails(getDoc(doc(db(BOB), 'users', ALICE.uid, 'notifications', 'n1')));
    await assertFails(getDocs(collection(db(EVE), 'users', ALICE.uid, 'notifications')));
    await assertFails(getDoc(doc(anon(), 'users', ALICE.uid, 'notifications', 'n1')));
  });

  test('the owner marks an entry read and unread', async () => {
    await assertSucceeds(updateDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'n1'), { read: true }));
    await assertSucceeds(updateDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'n1'), { read: false }));
  });

  test('the owner changes nothing in an entry but its read flag', async () => {
    await assertFails(updateDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'n1'), { read: true, title: 'Changed' }));
    await assertFails(updateDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'n1'), { body: 'Changed' }));
  });

  test('the owner clears an entry; nobody else can delete it', async () => {
    await assertFails(deleteDoc(doc(db(BOB), 'users', ALICE.uid, 'notifications', 'n1')));
    await assertSucceeds(deleteDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'n1')));
  });

  test('a member cannot write an entry into another member\'s list unless it is a chat notice they may send', async () => {
    await assertFails(setDoc(doc(db(BOB), 'users', ALICE.uid, 'notifications', 'x1'), entry({ action: 'notice' })));
  });

  test('the owner adds an entry to their own list', async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), 'users', ALICE.uid, 'notifications', 'own1'), entry()));
  });

  test('the top-level notifications collection is for admins only', async () => {
    await assertFails(getDoc(doc(db(BOB), 'notifications', 'broadcast')));
    await assertFails(getDoc(doc(anon(), 'notifications', 'broadcast')));
    await assertSucceeds(getDoc(doc(db(ADMIN), 'notifications', 'broadcast')));
  });
});
