// The chat screen's listeners depend on two rules facts for a one-to-one chat
// that does not exist yet:
//   - its messages cannot be read until the chat document exists, so a listener
//     opened earlier is refused, and
//   - the chat document itself can be read (and watched) before it exists, so the
//     screen learns when the first message creates it.
// Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/chat_listener_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, setDoc, addDoc, collection, query, orderBy, limit, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tour_listen';
const ALICE = { uid: 'listen-alice', email: 'listen-alice@x.com' };
const BOB = { uid: 'listen-bob', email: 'listen-bob@x.com' };
const CHAT = `${ALICE.uid}_${BOB.uid}`;

describe('chat listeners before the chat document exists', () => {
  let env;
  const as = (who) => env.authenticatedContext(who.uid, { email: who.email, email_verified: true }).firestore();
  const messagesQuery = (db) => query(collection(db, 'chats', CHAT, 'messages'), orderBy('timestamp', 'desc'), limit(30));
  const chatBody = {
    participants: [ALICE.uid, BOB.uid],
    sharedTourId: TOUR,
    memberEmails: { [ALICE.uid]: ALICE.email, [BOB.uid]: BOB.email },
  };

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  afterAll(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'tours', TOUR), { name: 'Listen', ownerEmail: ALICE.email, ownerUid: ALICE.uid, inviteCode: 'LISTENCD' });
      for (const who of [ALICE, BOB]) {
        await setDoc(doc(f, 'memberships', `${TOUR}__${who.email}`), {
          tourId: TOUR, email: who.email, uid: who.uid, role: 'member', status: 'active', displayName: who.uid,
        });
      }
    });
  });

  test('the messages of a chat that does not exist yet are refused', async () => {
    await assertFails(getDocs(messagesQuery(as(BOB))));
  });

  test('the chat document can be read before it exists, so its listener sees the chat appear', async () => {
    await assertSucceeds(getDoc(doc(as(BOB), 'chats', CHAT)));
  });

  test('once the first message creates the chat, its messages can be listed', async () => {
    const alice = as(ALICE);
    await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody, { merge: true }));
    await assertSucceeds(addDoc(collection(alice, 'chats', CHAT, 'messages'), {
      senderId: ALICE.uid, type: 'text', text: 'hello', seen: false, status: 'sent', timestamp: serverTimestamp(),
    }));
    await assertSucceeds(getDocs(messagesQuery(as(BOB))));
  });
});
