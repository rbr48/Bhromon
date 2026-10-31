// Chat documents and voice notes: only the two people in a chat can read or add its files,
// and only while they share a tour. Needs the Firestore and Storage emulators:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore,storage --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/chat_files_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';
const CHAT = 'ann_ben';
const BYTES = Buffer.from('bytes');

describe('Chat documents and voice notes in Storage', () => {
  let env;
  const who = (email) => env.authenticatedContext(email, { email, email_verified: true }).storage();

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 8080,
      },
      storage: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../storage.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 9199,
      },
    });
  });

  afterAll(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      const membership = (email) =>
        f.collection('memberships').doc(`${TOUR}__${email}`).set({ tourId: TOUR, email, role: 'member', status: 'active' });
      await membership('ann@x.com');
      await membership('ben@x.com');
      await membership('eve@x.com');
      await f.collection('chats').doc(CHAT).set({
        participants: ['ann@x.com', 'ben@x.com'],
        sharedTourId: TOUR,
        memberEmails: { 'ann@x.com': 'ann@x.com', 'ben@x.com': 'ben@x.com' },
      });
      // A chat from before the tour rule: it names no tour, so nothing in it is open.
      await f.collection('chats').doc('old').set({ participants: ['ann@x.com', 'ben@x.com'] });
    });
  });

  test('a participant can add a voice note and read it back', async () => {
    await assertSucceeds(
      who('ann@x.com').ref(`chat_voice/${CHAT}/v1.m4a`).put(BYTES, { contentType: 'audio/m4a' }),
    );
    await assertSucceeds(who('ben@x.com').ref(`chat_voice/${CHAT}/v1.m4a`).getDownloadURL());
  });

  test('someone who is not in the chat cannot read or add its files', async () => {
    await assertSucceeds(who('ann@x.com').ref(`chat_docs/${CHAT}/d1.pdf`).put(BYTES, { contentType: 'application/pdf' }));
    await assertFails(who('eve@x.com').ref(`chat_docs/${CHAT}/d1.pdf`).getDownloadURL());
    await assertFails(who('eve@x.com').ref(`chat_voice/${CHAT}/v2.m4a`).put(BYTES, { contentType: 'audio/m4a' }));
  });

  test('a chat that names no tour has no files open to anyone', async () => {
    await assertFails(who('ann@x.com').ref('chat_voice/old/v1.m4a').put(BYTES, { contentType: 'audio/m4a' }));
  });

  test('a document that the browser could run as a page is refused', async () => {
    await assertFails(who('ann@x.com').ref(`chat_docs/${CHAT}/page.html`).put(BYTES, { contentType: 'text/html' }));
    await assertFails(who('ann@x.com').ref(`chat_docs/${CHAT}/drawing.svg`).put(BYTES, { contentType: 'image/svg+xml' }));
  });

  test('a voice note must be audio', async () => {
    await assertFails(who('ann@x.com').ref(`chat_voice/${CHAT}/v3.txt`).put(BYTES, { contentType: 'text/plain' }));
  });
});
