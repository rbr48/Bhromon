// A one-to-one message has no length limit in the rules: its text is stored whole, up to
// the size of one Firestore document. The rules still require the text to be a string.
// Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/chat_message_length_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, addDoc, collection, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tour_long_text';
const ALICE = { uid: 'longtext-alice', email: 'longtext-alice@x.com' };
const BOB = { uid: 'longtext-bob', email: 'longtext-bob@x.com' };
const CHAT = `${ALICE.uid}_${BOB.uid}`;

describe('one-to-one messages have no length limit', () => {
  let env;
  const as = (who) => env.authenticatedContext(who.uid, { email: who.email, email_verified: true }).firestore();
  const messages = (db) => collection(db, 'chats', CHAT, 'messages');
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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Long text', ownerEmail: ALICE.email, ownerUid: ALICE.uid, inviteCode: 'LONGTEXT' });
      for (const who of [ALICE, BOB]) {
        await setDoc(doc(f, 'memberships', `${TOUR}__${who.email}`), {
          tourId: TOUR, email: who.email, uid: who.uid, role: 'member', status: 'active', displayName: who.uid,
        });
      }
    });
  });

  test('a message longer than the old 4,096-character limit is accepted', async () => {
    const alice = as(ALICE);
    await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody, { merge: true }));
    await assertSucceeds(addDoc(messages(alice), {
      senderId: ALICE.uid, type: 'text', text: 'ক'.repeat(6000), seen: false, status: 'sent', timestamp: serverTimestamp(),
    }));
  });

  test('the text must still be a string', async () => {
    const alice = as(ALICE);
    await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody, { merge: true }));
    await assertFails(addDoc(messages(alice), {
      senderId: ALICE.uid, type: 'text', text: 42, seen: false, status: 'sent', timestamp: serverTimestamp(),
    }));
  });
});
