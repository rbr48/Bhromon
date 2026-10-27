// Per-device push token rules. Needs the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/push_devices_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, deleteDoc } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';

describe('fcm_tokens/{uid}/devices rules', () => {
  let env;
  const db = (uid) => env.authenticatedContext(uid, { email: `${uid}@x.com` }).firestore();
  const guestDb = () => env.unauthenticatedContext().firestore();

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
      await setDoc(doc(f, 'fcm_tokens', 'asha', 'devices', 'phone'), { token: 't_phone' });
    });
  });

  test('a user can register their own device', async () => {
    await assertSucceeds(
      setDoc(doc(db('babu'), 'fcm_tokens', 'babu', 'devices', 'tablet'), { token: 't_tablet' }),
    );
  });

  test('a user can read and remove their own device', async () => {
    await assertSucceeds(getDoc(doc(db('asha'), 'fcm_tokens', 'asha', 'devices', 'phone')));
    await assertSucceeds(deleteDoc(doc(db('asha'), 'fcm_tokens', 'asha', 'devices', 'phone')));
  });

  test('another member cannot read or write someone else\'s devices', async () => {
    await assertFails(getDoc(doc(db('babu'), 'fcm_tokens', 'asha', 'devices', 'phone')));
    await assertFails(
      setDoc(doc(db('babu'), 'fcm_tokens', 'asha', 'devices', 'phone'), { token: 't_hijack' }),
    );
  });

  test('guests cannot touch devices', async () => {
    await assertFails(getDoc(doc(guestDb(), 'fcm_tokens', 'asha', 'devices', 'phone')));
    await assertFails(
      setDoc(doc(guestDb(), 'fcm_tokens', 'asha', 'devices', 'new'), { token: 't_guest' }),
    );
  });
});
