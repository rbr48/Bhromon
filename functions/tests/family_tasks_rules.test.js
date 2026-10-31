// Family shopping and to-do items. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/family_tasks_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const FAMILY = 'famtasks';
const TRIP = 'triptasks';
const people = {
  owner: { uid: 'town', email: 'town@x.com' },
  admin: { uid: 'tadm', email: 'tadm@x.com' },
  member: { uid: 'tmem', email: 'tmem@x.com' },
  other: { uid: 'toth', email: 'toth@x.com' },
  outsider: { uid: 'teve', email: 'teve@x.com' },
};

const task = (by, extra = {}) => ({
  title: 'Rice',
  kind: 'shopping',
  done: false,
  assigneeEmail: null,
  doneByEmail: null,
  createdByEmail: by,
  ...extra,
});

describe('family tasks rules', () => {
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
      await setDoc(doc(f, 'tours', FAMILY), { name: 'Rahman family', kind: 'family', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'FAMTASK1' });
      await setDoc(doc(f, 'tours', TRIP), { name: 'Trip', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'TRIPTSK1' });
      const membership = (tourId, email, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), { tourId, email, role, status: 'active', displayName: email });
      await membership(FAMILY, people.owner.email, 'owner');
      await membership(FAMILY, people.admin.email, 'admin');
      await membership(FAMILY, people.member.email, 'member');
      await membership(FAMILY, people.other.email, 'member');
      await membership(TRIP, people.owner.email, 'owner');
      await membership(TRIP, people.member.email, 'member');
      await setDoc(doc(f, 'tours', FAMILY, 'family_tasks', 't1'), task(people.member.email));
    });
  });

  test('a family member adds an item under their own email only', async () => {
    await assertSucceeds(setDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't2'), task(people.member.email, { kind: 'todo', title: 'Call the plumber' })));
    await assertFails(setDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't3'), task(people.owner.email)));
    await assertFails(setDoc(doc(db('outsider'), 'tours', FAMILY, 'family_tasks', 't4'), task(people.outsider.email)));
  });

  test('a trip has no family shopping list', async () => {
    await assertFails(setDoc(doc(db('member'), 'tours', TRIP, 'family_tasks', 't2'), task(people.member.email)));
  });

  test('every field is checked on create', async () => {
    const me = people.member.email;
    const bad = [
      { title: '' },
      { title: 'x'.repeat(121) },
      { kind: 'errand' },
      { done: 'yes' },
      { assigneeEmail: 42 },
      { surprise: true },
    ];
    for (let i = 0; i < bad.length; i++) {
      await assertFails(setDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', `bad${i}`), task(me, bad[i])));
    }
  });

  test('any member ticks an item, and the tick is recorded as their own', async () => {
    await assertSucceeds(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { done: true, doneByEmail: people.other.email }));
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { done: true, doneByEmail: people.owner.email }));
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { done: true, doneByEmail: null }));
  });

  test('unticking clears who ticked it, and a non-creator cannot leave a name on an open item', async () => {
    await assertSucceeds(updateDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't1'), { done: true, doneByEmail: people.member.email }));
    // The creator may edit their own item in full; another member may only untick.
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { done: false, doneByEmail: people.other.email }));
    await assertSucceeds(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { done: false, doneByEmail: null }));
  });

  test('ticking changes only the done state, not the item itself', async () => {
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { done: true, doneByEmail: people.other.email, title: 'Sugar' }));
  });

  test('the creator and an admin edit an item; another member cannot', async () => {
    await assertSucceeds(updateDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't1'), { title: 'Basmati rice' }));
    await assertSucceeds(updateDoc(doc(db('admin'), 'tours', FAMILY, 'family_tasks', 't1'), { assigneeEmail: people.other.email }));
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1'), { title: 'Hijack' }));
  });

  test('nobody hands an item to another person, even its creator', async () => {
    await assertFails(updateDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't1'), { createdByEmail: people.other.email }));
  });

  test('the creator and an admin delete an item; another member cannot', async () => {
    await assertFails(deleteDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1')));
    await assertSucceeds(deleteDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't1')));
    await assertSucceeds(setDoc(doc(db('member'), 'tours', FAMILY, 'family_tasks', 't5'), task(people.member.email)));
    await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', FAMILY, 'family_tasks', 't5')));
  });

  test('only members of the circle read its items', async () => {
    await assertSucceeds(getDoc(doc(db('other'), 'tours', FAMILY, 'family_tasks', 't1')));
    await assertFails(getDoc(doc(db('outsider'), 'tours', FAMILY, 'family_tasks', 't1')));
    await assertSucceeds(getDocs(collection(db('member'), 'tours', FAMILY, 'family_tasks')));
    await assertFails(getDocs(collection(db('outsider'), 'tours', FAMILY, 'family_tasks')));
  });
});
