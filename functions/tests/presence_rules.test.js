// Tour presence rules. Needs the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/presence_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, collection, deleteDoc, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';

describe('tours/{tourId}/presence rules', () => {
  let env;
  const db = (email) => env.authenticatedContext(email.split('@')[0], { email, email_verified: true }).firestore();
  const guestDb = () => env.unauthenticatedContext().firestore();
  const presence = (firestore, email) =>
    doc(firestore, 'tours', TOUR, 'presence', email);

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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Trip', ownerEmail: 'owner@x.com' });
      for (const email of ['owner@x.com', 'asha@x.com', 'babu@x.com']) {
        await setDoc(doc(f, 'memberships', `${TOUR}__${email}`), {
          tourId: TOUR,
          email,
          role: email === 'owner@x.com' ? 'owner' : 'member',
          status: 'active',
        });
      }
      await setDoc(presence(f, 'babu@x.com'), {
        email: 'babu@x.com',
        displayName: 'Babu',
        lastSeen: new Date(),
      });
    });
  });

  const here = (email, overrides = {}) => ({
    email,
    displayName: 'Asha',
    lastSeen: serverTimestamp(),
    ...overrides,
  });

  test('a member can record their own presence with the server clock', async () => {
    await assertSucceeds(setDoc(presence(db('asha@x.com'), 'asha@x.com'), here('asha@x.com')));
  });

  test('a member can see who else is here', async () => {
    await assertSucceeds(getDocs(collection(db('asha@x.com'), 'tours', TOUR, 'presence')));
  });

  test('a member cannot record someone else\'s presence', async () => {
    await assertFails(setDoc(presence(db('asha@x.com'), 'babu@x.com'), here('babu@x.com')));
  });

  test('a client-supplied last-seen time is refused', async () => {
    await assertFails(
      setDoc(presence(db('asha@x.com'), 'asha@x.com'), here('asha@x.com', { lastSeen: new Date() })),
    );
  });

  test('extra fields are refused', async () => {
    await assertFails(
      setDoc(presence(db('asha@x.com'), 'asha@x.com'), here('asha@x.com', { role: 'owner' })),
    );
  });

  test('a member can remove only their own presence', async () => {
    await assertSucceeds(deleteDoc(presence(db('babu@x.com'), 'babu@x.com')));
    await assertFails(deleteDoc(presence(db('asha@x.com'), 'babu@x.com')));
  });

  test('someone who is not a member can see nothing', async () => {
    await assertFails(getDoc(presence(db('eve@x.com'), 'babu@x.com')));
    await assertFails(setDoc(presence(db('eve@x.com'), 'eve@x.com'), here('eve@x.com')));
  });

  test('a guest can see nothing', async () => {
    await assertFails(getDoc(presence(guestDb(), 'babu@x.com')));
  });
});
