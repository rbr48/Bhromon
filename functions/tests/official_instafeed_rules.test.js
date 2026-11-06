const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';

// The official feed is readable by anyone signed in, and written by no app: the server
// publishes it with the Admin SDK.
describe('Official instafeed rules', () => {
  let testEnv;

  beforeAll(async () => {
    const rules = fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8');
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules, host: '127.0.0.1', port: 8080 },
    });
  });

  afterAll(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('official_instafeed').doc('p1').set({
        videoUrl: 'https://bhromon.fun/media/official/reels/p1.mp4',
        caption: 'Welcome',
        kind: 'reel',
      });
    });
  });

  test('a signed-in person may read the official feed', async () => {
    const alice = testEnv.authenticatedContext('uid-alice', { email: 'alice@x.com' }).firestore();

    await assertSucceeds(alice.collection('official_instafeed').doc('p1').get());
    await assertSucceeds(alice.collection('official_instafeed').get());
  });

  test('a signed-out visitor may not read it', async () => {
    const visitor = testEnv.unauthenticatedContext().firestore();

    await assertFails(visitor.collection('official_instafeed').doc('p1').get());
  });

  test('no app writes it: not a create, an edit or a delete', async () => {
    const alice = testEnv.authenticatedContext('uid-alice', { email: 'alice@x.com' }).firestore();
    const posts = alice.collection('official_instafeed');

    await assertFails(posts.doc('mine').set({
      videoUrl: 'https://bhromon.fun/media/official/reels/mine.mp4',
      caption: 'Not allowed',
      kind: 'reel',
    }));
    await assertFails(posts.doc('p1').update({ caption: 'Changed' }));
    await assertFails(posts.doc('p1').delete());
  });
});
