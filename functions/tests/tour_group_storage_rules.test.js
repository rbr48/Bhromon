// Tour Group Storage rules. Needs the Firestore and Storage emulators:
//   firebase emulators:exec --only firestore,storage --project bhromon-rules-test-project "npx jest --runInBand tests/tour_group_storage_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';
const MB = 1024 * 1024;

describe('Tour Group Storage rules', () => {
  let env;
  const who = (email) => env.authenticatedContext(email, { email }).storage();

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
      const membership = (email, role, status = 'active') =>
        f.collection('memberships').doc(`${TOUR}__${email}`).set({ tourId: TOUR, email, role, status });
      await membership('owner@x.com', 'owner');
      await membership('admin@x.com', 'admin');
      await membership('member@x.com', 'member');
      await membership('left@x.com', 'member', 'removed');
    });
  });

  const upload = (email, name, size, contentType, uploader = email) =>
    who(email)
      .ref(`tours/${TOUR}/posts/${name}`)
      .put(Buffer.alloc(size), { contentType, customMetadata: { uploadedByEmail: uploader } });

  test('active members upload images and videos under their own email', async () => {
    await assertSucceeds(upload('member@x.com', 'a.jpg', 1 * MB, 'image/jpeg'));
    await assertSucceeds(upload('member@x.com', 'b.mp4', 50 * MB, 'video/mp4'));
  });

  test('images over 10 MB are refused even though the video limit is higher', async () => {
    await assertFails(upload('member@x.com', 'big.jpg', 11 * MB, 'image/jpeg'));
  });

  test('videos over 100 MB are refused', async () => {
    await assertFails(upload('member@x.com', 'huge.mp4', 101 * MB, 'video/mp4'));
  });

  test('uploads must be tagged with the uploader email', async () => {
    await assertFails(upload('member@x.com', 'spoof.jpg', 1 * MB, 'image/jpeg', 'admin@x.com'));
  });

  test('outsiders and removed members can neither read nor upload', async () => {
    await assertFails(upload('eve@x.com', 'e.jpg', 1 * MB, 'image/jpeg'));
    await assertFails(upload('left@x.com', 'l.jpg', 1 * MB, 'image/jpeg'));
    await assertSucceeds(upload('member@x.com', 'ok.jpg', 1 * MB, 'image/jpeg'));
    await assertFails(who('eve@x.com').ref(`tours/${TOUR}/posts/ok.jpg`).getDownloadURL());
    await assertSucceeds(who('admin@x.com').ref(`tours/${TOUR}/posts/ok.jpg`).getDownloadURL());
  });

  test('uploader can delete their own file; other members cannot; admins can', async () => {
    await upload('member@x.com', 'mine.jpg', 1 * MB, 'image/jpeg');
    await upload('admin@x.com', 'theirs.jpg', 1 * MB, 'image/jpeg');
    await assertFails(who('member@x.com').ref(`tours/${TOUR}/posts/theirs.jpg`).delete());
    await assertSucceeds(who('member@x.com').ref(`tours/${TOUR}/posts/mine.jpg`).delete());
    await assertSucceeds(who('admin@x.com').ref(`tours/${TOUR}/posts/theirs.jpg`).delete());
  });
});
