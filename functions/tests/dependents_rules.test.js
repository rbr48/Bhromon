// Dependents: people in a family with no account, listed under a member. Runs against
// the Firestore emulator on port 8080, like the other tour rules suites:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/dependents_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const FAMILY = 'famdeps';
const TRIP = 'tripdeps';
const people = {
  owner: { uid: 'down', email: 'down@x.com' },
  admin: { uid: 'dadm', email: 'dadm@x.com' },
  member: { uid: 'dmem', email: 'dmem@x.com' },
  other: { uid: 'doth', email: 'doth@x.com' },
  outsider: { uid: 'deve', email: 'deve@x.com' },
};

const dependent = (parent, extra = {}) => ({
  name: 'Rafi',
  relation: 'son',
  parentEmail: parent,
  countedInFamily: true,
  ...extra,
});

describe('dependents rules', () => {
  let env;
  const db = (who) =>
    env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

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
      await setDoc(doc(f, 'tours', FAMILY), { name: 'Rahman family', kind: 'family', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'FAMDEP01' });
      await setDoc(doc(f, 'tours', TRIP), { name: 'Trip', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'TRIPDEP1' });
      const membership = (tourId, email, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), { tourId, email, role, status: 'active', displayName: email, familyCount: 2 });
      await membership(FAMILY, people.owner.email, 'owner');
      await membership(FAMILY, people.admin.email, 'admin');
      await membership(FAMILY, people.member.email, 'member');
      await membership(FAMILY, people.other.email, 'member');
      await membership(TRIP, people.owner.email, 'owner');
      await membership(TRIP, people.member.email, 'member');
      await setDoc(doc(f, 'tours', FAMILY, 'dependents', 'd1'), dependent(people.member.email));
    });
  });

  test('a member lists a dependent under their own email only', async () => {
    await assertSucceeds(setDoc(doc(db('member'), 'tours', FAMILY, 'dependents', 'd2'), dependent(people.member.email, { name: 'Nani' })));
    await assertFails(setDoc(doc(db('member'), 'tours', FAMILY, 'dependents', 'd3'), dependent(people.owner.email)));
    await assertFails(setDoc(doc(db('outsider'), 'tours', FAMILY, 'dependents', 'd4'), dependent(people.outsider.email)));
  });

  test('a trip has no dependents', async () => {
    await assertFails(setDoc(doc(db('member'), 'tours', TRIP, 'dependents', 'd2'), dependent(people.member.email)));
  });

  test('every field is checked', async () => {
    const me = people.member.email;
    const bad = [
      { name: '' },
      { name: 'x'.repeat(61) },
      { relation: 'x'.repeat(31) },
      { relation: 7 },
      { countedInFamily: 'yes' },
      { surprise: true },
    ];
    for (let i = 0; i < bad.length; i++) {
      await assertFails(setDoc(doc(db('member'), 'tours', FAMILY, 'dependents', `bad${i}`), dependent(me, bad[i])));
    }
  });

  test('only the member who listed a dependent changes them, and their parent stays the same', async () => {
    await assertSucceeds(updateDoc(doc(db('member'), 'tours', FAMILY, 'dependents', 'd1'), { name: 'Rafiq' }));
    await assertFails(updateDoc(doc(db('member'), 'tours', FAMILY, 'dependents', 'd1'), { parentEmail: people.other.email }));
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'dependents', 'd1'), { name: 'Hijack' }));
    await assertFails(updateDoc(doc(db('admin'), 'tours', FAMILY, 'dependents', 'd1'), { name: 'Hijack' }));
  });

  test('only the member who listed a dependent removes them, not an admin', async () => {
    await assertFails(deleteDoc(doc(db('admin'), 'tours', FAMILY, 'dependents', 'd1')));
    await assertFails(deleteDoc(doc(db('other'), 'tours', FAMILY, 'dependents', 'd1')));
    await assertSucceeds(deleteDoc(doc(db('member'), 'tours', FAMILY, 'dependents', 'd1')));
  });

  test('members read the dependents of their circle; outsiders read nothing', async () => {
    await assertSucceeds(getDoc(doc(db('other'), 'tours', FAMILY, 'dependents', 'd1')));
    await assertSucceeds(getDocs(collection(db('other'), 'tours', FAMILY, 'dependents')));
    await assertFails(getDoc(doc(db('outsider'), 'tours', FAMILY, 'dependents', 'd1')));
    await assertFails(getDocs(collection(db('outsider'), 'tours', FAMILY, 'dependents')));
  });

  test('the member can change their own family size, which the add and remove use', async () => {
    await assertSucceeds(updateDoc(doc(db('member'), 'memberships', `${FAMILY}__${people.member.email}`), { familyCount: 3 }));
    await assertFails(updateDoc(doc(db('other'), 'memberships', `${FAMILY}__${people.member.email}`), { familyCount: 3 }));
  });
});
