// Safety report and geofence trigger rules. Needs the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/abuse_surfaces_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, addDoc, collection, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const MB = 1024 * 1024;

describe('Safety reports and geofence triggers', () => {
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
      await setDoc(doc(f, 'explorer_profiles', 'admin1'), { tier: 'regionExpert' });
      await setDoc(doc(f, 'explorer_profiles', 'explorer1'), { tier: 'explorer' });
    });
  });

  const report = (uid, overrides = {}) => ({
    pinId: 'pin1',
    pinName: 'Sajek Road',
    reason: 'Road blocked',
    detail: 'Landslide near the bend',
    reportedBy: uid,
    status: 'pending',
    timestamp: serverTimestamp(),
    ...overrides,
  });

  describe('safety_reports', () => {
    test('a signed-in user can file a pending report under their own uid', async () => {
      await assertSucceeds(addDoc(collection(db('explorer1'), 'safety_reports'), report('explorer1')));
    });

    test('guests cannot file reports', async () => {
      await assertFails(
        addDoc(collection(guestDb(), 'safety_reports'), report('anonymous')),
      );
    });

    test('a report cannot be filed under someone else\'s uid', async () => {
      await assertFails(addDoc(collection(db('explorer1'), 'safety_reports'), report('admin1')));
    });

    test('a report cannot start as anything but pending', async () => {
      await assertFails(
        addDoc(collection(db('explorer1'), 'safety_reports'), report('explorer1', { status: 'resolved' })),
      );
    });

    test('the timestamp must be the server clock, not a client date', async () => {
      await assertFails(
        addDoc(collection(db('explorer1'), 'safety_reports'), report('explorer1', { timestamp: new Date(0) })),
      );
    });

    test('unexpected fields are refused', async () => {
      await assertFails(
        addDoc(collection(db('explorer1'), 'safety_reports'), report('explorer1', { isAdmin: true })),
      );
    });

    test('oversized text is refused', async () => {
      await assertFails(
        addDoc(collection(db('explorer1'), 'safety_reports'), report('explorer1', { detail: 'x'.repeat(1001) })),
      );
    });

    test('only admins can read reports', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'safety_reports', 'r1'), report('explorer1'));
      });
      await assertFails(getDoc(doc(db('explorer1'), 'safety_reports', 'r1')));
      await assertSucceeds(getDoc(doc(db('admin1'), 'safety_reports', 'r1')));
    });
  });

  describe('geo_fence_triggers', () => {
    const trigger = (overrides = {}) => ({
      pinId: 'pin1',
      pinName: 'Sajek Road',
      distanceM: 120,
      triggeredAt: serverTimestamp(),
      ...overrides,
    });

    test('a signed-in device can record a trigger with the server clock', async () => {
      await assertSucceeds(addDoc(collection(db('explorer1'), 'geo_fence_triggers'), trigger()));
    });

    test('guests cannot record triggers', async () => {
      await assertFails(addDoc(collection(guestDb(), 'geo_fence_triggers'), trigger()));
    });

    test('a client-supplied trigger time is refused', async () => {
      await assertFails(
        addDoc(collection(db('explorer1'), 'geo_fence_triggers'), trigger({ triggeredAt: new Date() })),
      );
    });

    test('distance must be a non-negative integer', async () => {
      await assertFails(addDoc(collection(db('explorer1'), 'geo_fence_triggers'), trigger({ distanceM: -1 })));
      await assertFails(addDoc(collection(db('explorer1'), 'geo_fence_triggers'), trigger({ distanceM: 'far' })));
    });
  });
});
