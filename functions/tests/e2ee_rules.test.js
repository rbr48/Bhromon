// Encrypted one-to-one chats and the public key bundles (E2EE_DESIGN.md, sections 6 and 7).
// Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/e2ee_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, addDoc, collection, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tour_e2ee';
const ALICE = { uid: 'e2ee-alice', email: 'e2ee-alice@x.com' };
const BOB = { uid: 'e2ee-bob', email: 'e2ee-bob@x.com' };
const CHAT = `${ALICE.uid}_${BOB.uid}`;
const PLAIN = `${ALICE.uid}_${BOB.uid}-plain`;
const KEY = 'A'.repeat(43);
const SIG = 'B'.repeat(86);
const KEY_ID = 'K'.repeat(22);
const ENVELOPE = { v: 1, alg: 'olm.v1', from: 'device-alice', to: 'device-bob', type: 1, ct: 'AQID' };

function bundle(overrides = {}) {
  return {
    deviceId: 'device-alice',
    curve25519Key: KEY,
    ed25519Key: KEY,
    identitySignature: SIG,
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

describe('end-to-end encryption rules', () => {
  let env;
  const as = (who) => env.authenticatedContext(who.uid, { email: who.email, email_verified: true }).firestore();
  const signedOut = () => env.unauthenticatedContext().firestore();
  const messages = (db, chatId) => collection(db, 'chats', chatId, 'messages');
  const chatBody = (extra = {}) => ({
    participants: [ALICE.uid, BOB.uid],
    sharedTourId: TOUR,
    memberEmails: { [ALICE.uid]: ALICE.email, [BOB.uid]: BOB.email },
    ...extra,
  });
  const message = (extra = {}) => ({
    senderId: ALICE.uid,
    type: 'text',
    seen: false,
    status: 'sent',
    timestamp: serverTimestamp(),
    ...extra,
  });

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
      await setDoc(doc(f, 'tours', TOUR), { name: 'E2EE', ownerEmail: ALICE.email, ownerUid: ALICE.uid, inviteCode: 'E2EETOUR' });
      for (const who of [ALICE, BOB]) {
        await setDoc(doc(f, 'memberships', `${TOUR}__${who.email}`), {
          tourId: TOUR, email: who.email, uid: who.uid, role: 'member', status: 'active', displayName: who.uid,
        });
      }
    });
  });

  describe('public key bundles', () => {
    test('the owner publishes a bundle, and a signed-in user reads it', async () => {
      await assertSucceeds(setDoc(doc(as(ALICE), 'e2ee_keys', ALICE.uid), bundle()));
      await assertSucceeds(getDoc(doc(as(BOB), 'e2ee_keys', ALICE.uid)));
      await assertFails(getDoc(doc(signedOut(), 'e2ee_keys', ALICE.uid)));
    });

    test('another user cannot publish a bundle for someone else', async () => {
      await assertFails(setDoc(doc(as(BOB), 'e2ee_keys', ALICE.uid), bundle()));
    });

    test('a bundle with a malformed key, signature or field is refused', async () => {
      const alice = as(ALICE);
      const refused = [
        bundle({ curve25519Key: 'A'.repeat(42) }),
        bundle({ ed25519Key: 'A'.repeat(42) }),
        bundle({ identitySignature: 'B'.repeat(85) }),
        bundle({ deviceId: 'device alice' }),
        bundle({ extra: true }),
        bundle({ fallbackKey: { keyId: 'short', key: KEY, signature: SIG } }),
        bundle({ updatedAt: '2026-01-01' }),
      ];
      for (const body of refused) {
        await assertFails(setDoc(doc(alice, 'e2ee_keys', ALICE.uid), body));
      }
    });

    test('the owner adds and removes one-time keys; others cannot', async () => {
      const otk = { deviceId: 'device-alice', keyId: KEY_ID, key: KEY, signature: SIG };
      const ref = doc(as(ALICE), 'e2ee_keys', ALICE.uid, 'oneTimeKeys', KEY_ID);

      await assertSucceeds(setDoc(ref, otk));
      await assertSucceeds(getDoc(doc(as(BOB), 'e2ee_keys', ALICE.uid, 'oneTimeKeys', KEY_ID)));
      await assertFails(setDoc(doc(as(BOB), 'e2ee_keys', ALICE.uid, 'oneTimeKeys', 'L'.repeat(22)), { ...otk, keyId: 'L'.repeat(22) }));
      await assertFails(updateDoc(ref, { key: KEY }));
      await assertSucceeds(deleteDoc(ref));
    });

    test('a one-time key must sit at the path of its own id', async () => {
      await assertFails(setDoc(
        doc(as(ALICE), 'e2ee_keys', ALICE.uid, 'oneTimeKeys', 'M'.repeat(22)),
        { deviceId: 'device-alice', keyId: KEY_ID, key: KEY, signature: SIG },
      ));
    });
  });

  describe('encrypted one-to-one chats', () => {
    test('a chat is created encrypted or plain, and its flag cannot change', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody({ e2ee: true })));
      await assertFails(updateDoc(doc(alice, 'chats', CHAT), { e2ee: false }));
      await assertSucceeds(updateDoc(doc(alice, 'chats', CHAT), { lastMessage: 'hi' }));

      await assertSucceeds(setDoc(doc(alice, 'chats', PLAIN), chatBody()));
      await assertFails(updateDoc(doc(alice, 'chats', PLAIN), { e2ee: true }));

      await assertFails(setDoc(doc(alice, 'chats', `${CHAT}-bad`), chatBody({ e2ee: 'yes' })));
    });

    test('an encrypted chat takes an envelope and no text', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody({ e2ee: true })));
      await assertSucceeds(addDoc(messages(alice, CHAT), message({ envelope: ENVELOPE })));
    });

    test('an encrypted chat refuses text, other types and malformed envelopes', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody({ e2ee: true })));
      const refused = [
        message({ envelope: ENVELOPE, text: 'hello' }),
        message({ text: 'hello' }),
        message({ envelope: ENVELOPE, type: 'image' }),
        message({ envelope: { ...ENVELOPE, v: 2 } }),
        message({ envelope: { ...ENVELOPE, extra: 1 } }),
        message({ envelope: { ...ENVELOPE, ct: 'A!B=' } }),
        message({ envelope: { ...ENVELOPE, type: 2 } }),
      ];
      for (const body of refused) {
        await assertFails(addDoc(messages(alice, CHAT), body));
      }
    });

    test('a plaintext chat refuses an envelope and takes text', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', PLAIN), chatBody()));
      await assertFails(addDoc(messages(alice, PLAIN), message({ envelope: ENVELOPE })));
      await assertSucceeds(addDoc(messages(alice, PLAIN), message({ text: 'hello' })));
    });

    test('in an encrypted chat a message cannot be edited, deleted for everyone or reacted to', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody({ e2ee: true })));
      const ref = await addDoc(messages(alice, CHAT), message({ envelope: ENVELOPE }));
      const forAlice = doc(alice, 'chats', CHAT, 'messages', ref.id);
      const forBob = doc(as(BOB), 'chats', CHAT, 'messages', ref.id);

      await assertFails(updateDoc(forAlice, { text: 'changed', isEdited: true, editedAt: serverTimestamp() }));
      await assertFails(updateDoc(forAlice, { type: 'deleted', text: '', isDeleted: true, deletedAt: serverTimestamp() }));
      await assertFails(updateDoc(forBob, { reactions: { '👍': [BOB.uid] } }));
      await assertFails(updateDoc(forBob, { isStarred: true, starredBy: [BOB.uid] }));
    });

    test('in an encrypted chat the recipient can still mark a message read and delete it for themselves', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', CHAT), chatBody({ e2ee: true })));
      const ref = await addDoc(messages(alice, CHAT), message({ envelope: ENVELOPE }));
      const forBob = doc(as(BOB), 'chats', CHAT, 'messages', ref.id);

      await assertSucceeds(updateDoc(forBob, { seen: true, status: 'read', readAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(forBob, { deletedFor: [BOB.uid] }));
    });

    test('a plaintext message keeps its edit within fifteen minutes', async () => {
      const alice = as(ALICE);
      await assertSucceeds(setDoc(doc(alice, 'chats', PLAIN), chatBody()));
      const ref = await addDoc(messages(alice, PLAIN), message({ text: 'first' }));
      await assertSucceeds(updateDoc(
        doc(alice, 'chats', PLAIN, 'messages', ref.id),
        { text: 'edited', isEdited: true, editedAt: serverTimestamp() },
      ));
    });
  });
});
