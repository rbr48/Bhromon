// Legacy chat media Storage rules. Needs the Storage emulator:
//   firebase emulators:exec --only storage --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/chat_media_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const MB = 1024 * 1024;

describe('Legacy chat media Storage rules', () => {
  let env;
  const who = (uid) => env.authenticatedContext(uid, { email: `${uid}@x.com` }).storage();

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
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
    await env.clearStorage();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.storage().ref('chat_media/chat1/old.jpg').put(Buffer.alloc(1 * MB), { contentType: 'image/jpeg' });
    });
  });

  test('signed-in users can still read old chat media', async () => {
    await assertSucceeds(who('explorer1').ref('chat_media/chat1/old.jpg').getDownloadURL());
  });

  test('nothing new can be uploaded under chat_media', async () => {
    await assertFails(
      who('explorer1').ref('chat_media/chat1/new.jpg').put(Buffer.alloc(1024), { contentType: 'image/jpeg' }),
    );
  });

  test('the uploader cannot delete chat media from the client any more', async () => {
    await assertFails(who('explorer1').ref('chat_media/chat1/old.jpg').delete());
  });
});
