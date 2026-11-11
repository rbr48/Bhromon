// Family shopping and to-do items. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/family_tasks_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  writeBatch,
  serverTimestamp,
} = require('firebase/firestore');

jest.setTimeout(120000);

const PROJECT_ID = 'bhromon-rules-test-project';
const FAMILY = 'famtasks';
const TRIP = 'triptasks';
const people = {
  owner: { uid: 'town', email: 'town@x.com' },
  admin: { uid: 'tadm', email: 'tadm@x.com' },
  member: { uid: 'tmem', email: 'tmem@x.com' },
  other: { uid: 'toth', email: 'toth@x.com' },
  outsider: { uid: 'teve', email: 'teve@x.com' },
  former: { uid: 'tfor', email: 'tfor@x.com' },
};

// The Dhaka day, as the rules count it: UTC plus six hours, written yyyymmdd.
function dhakaDayKey(now = new Date()) {
  const d = new Date(now.getTime() + 6 * 3600 * 1000);
  return String(d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate());
}

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
  // One Firestore instance per signed-in person: a batch and the references it writes must share it.
  const instances = {};
  const db = (who) => {
    if (!instances[who]) {
      instances[who] = env
        .authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true })
        .firestore();
    }
    return instances[who];
  };
  const itemRef = (who, id, tourId = FAMILY) => doc(db(who), 'tours', tourId, 'family_tasks', id);
  const counterRef = (who, tourId = FAMILY, day = dhakaDayKey()) =>
    doc(db(who), 'tours', tourId, 'family_task_daily', `${people[who].email}__${day}`);

  // A new item, written with its member's count for the day in one batch, as the app does.
  const create = (who, id, fields = {}, count = 1) => {
    const batch = writeBatch(db(who));
    batch.set(itemRef(who, id), { ...task(people[who].email, { createdAt: serverTimestamp() }), ...fields });
    batch.set(counterRef(who), { count, email: people[who].email });
    return batch.commit();
  };

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
      const membership = (tourId, email, role, status = 'active') =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), { tourId, email, role, status, displayName: email });
      await membership(FAMILY, people.owner.email, 'owner');
      await membership(FAMILY, people.admin.email, 'admin');
      await membership(FAMILY, people.member.email, 'member');
      await membership(FAMILY, people.other.email, 'member');
      await membership(FAMILY, people.former.email, 'member', 'left');
      await membership(TRIP, people.owner.email, 'owner');
      await membership(TRIP, people.member.email, 'member');
      await setDoc(doc(f, 'tours', FAMILY, 'family_tasks', 't1'), { ...task(people.member.email), createdAt: new Date(1000) });
      await setDoc(doc(f, 'tours', FAMILY, 'family_tasks', 't6'), { ...task(people.member.email, { title: 'Eggs' }), createdAt: new Date(2000) });
    });
  });

  describe('adding an item', () => {
    test('a family member adds an item under their own email only', async () => {
      await assertSucceeds(create('member', 't2', { kind: 'todo', title: 'Call the plumber' }));
      await assertFails(create('member', 't3', { createdByEmail: people.owner.email }));
      await assertFails(create('outsider', 't4', { createdByEmail: people.outsider.email }));
    });

    test('an item is written with the day count in the same batch', async () => {
      await assertFails(setDoc(itemRef('member', 't2'), task(people.member.email, { createdAt: serverTimestamp() })));
    });

    test('a trip has no family shopping list', async () => {
      const batch = writeBatch(db('member'));
      batch.set(itemRef('member', 't2', TRIP), task(people.member.email));
      batch.set(counterRef('member', TRIP), { count: 1, email: people.member.email });
      await assertFails(batch.commit());
    });

    test('every field is checked on create', async () => {
      const bad = [
        { title: '' },
        { title: 'x'.repeat(121) },
        { title: '   ' },
        { title: '\t \n' },
        { kind: 'errand' },
        { done: 'yes' },
        { assigneeEmail: 42 },
        { surprise: true },
        { createdAt: 'yesterday' },
      ];
      for (let i = 0; i < bad.length; i++) {
        await assertFails(create('member', `bad${i}`, bad[i]));
      }
    });

    test('a new item is open: it has no tick, no name and no time', async () => {
      await assertFails(create('member', 'c1', { done: true, doneByEmail: people.member.email }));
      await assertFails(create('member', 'c2', { done: true, doneByEmail: null }));
      await assertFails(create('member', 'c3', { done: false, doneByEmail: people.other.email }));
      await assertFails(create('member', 'c4', { doneAt: serverTimestamp() }));
    });

    test('a new item cannot be ticked for someone else from the start', async () => {
      await assertFails(create('member', 'c5', { done: true, doneByEmail: people.owner.email, doneAt: serverTimestamp() }));
    });

    test('an item carries the server time, and no other time', async () => {
      await assertSucceeds(create('member', 'time1', { createdAt: serverTimestamp() }));
      const batch = writeBatch(db('member'));
      batch.set(itemRef('member', 'time2'), task(people.member.email, { createdAt: new Date(0) }));
      batch.set(counterRef('member'), { count: 2, email: people.member.email });
      await assertFails(batch.commit());
    });

    test('an assignee must be an active member of the circle', async () => {
      await assertSucceeds(create('member', 'a1', { assigneeEmail: people.other.email }));
      await assertFails(create('member', 'a2', { assigneeEmail: 'ghost@x.com' }, 2));
      await assertFails(create('member', 'a3', { assigneeEmail: people.former.email }, 3));
    });

    test('a title must hold a character that is not a space', async () => {
      await assertSucceeds(create('member', 'ok1', { title: '  Milk  ' }));
      await assertFails(create('member', 'ws1', { title: '    ' }, 2));
    });
  });

  describe('ticking', () => {
    test('any member ticks an open item under their own name', async () => {
      await assertSucceeds(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: people.other.email, doneAt: serverTimestamp() }));
    });

    test('a tick must be the ticker\'s own name and time', async () => {
      await assertFails(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: people.owner.email }));
      await assertFails(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: null }));
      await assertFails(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: people.other.email, doneAt: new Date(0) }));
    });

    test('a taken item cannot be taken over by another member', async () => {
      await assertSucceeds(updateDoc(itemRef('member', 't1'), { done: true, doneByEmail: people.member.email }));
      await assertFails(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: people.other.email }));
    });

    test('anyone unticks a taken item, and the untick clears the name and the time', async () => {
      await assertSucceeds(updateDoc(itemRef('member', 't1'), { done: true, doneByEmail: people.member.email, doneAt: serverTimestamp() }));
      await assertFails(updateDoc(itemRef('other', 't1'), { done: false, doneByEmail: people.other.email }));
      await assertFails(updateDoc(itemRef('other', 't1'), { done: false, doneByEmail: null, doneAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(itemRef('other', 't1'), { done: false, doneByEmail: null, doneAt: null }));
    });

    test('the creator cannot forge a tick through an edit', async () => {
      await assertFails(updateDoc(itemRef('member', 't1'), { done: true, doneByEmail: people.owner.email }));
      await assertFails(updateDoc(itemRef('member', 't1'), { done: true, doneByEmail: people.member.email, title: 'Sugar' }));
    });

    test('ticking changes only the tick fields, not the item', async () => {
      await assertFails(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: people.other.email, title: 'Sugar' }));
      await assertFails(updateDoc(itemRef('other', 't1'), { done: true, doneByEmail: people.other.email, kind: 'todo' }));
    });
  });

  describe('editing and removing', () => {
    test('the creator and an admin edit text, kind and assignee; another member cannot', async () => {
      await assertSucceeds(updateDoc(itemRef('member', 't1'), { title: 'Basmati rice' }));
      await assertSucceeds(updateDoc(itemRef('admin', 't1'), { assigneeEmail: people.other.email }));
      await assertSucceeds(updateDoc(itemRef('admin', 't1'), { kind: 'todo' }));
      await assertFails(updateDoc(itemRef('other', 't1'), { title: 'Hijack' }));
    });

    test('an edit cannot hand an item to another person, even by its creator', async () => {
      await assertFails(updateDoc(itemRef('member', 't1'), { createdByEmail: people.other.email }));
    });

    test('an edit cannot change when the item was created', async () => {
      await assertFails(updateDoc(itemRef('member', 't6'), { createdAt: new Date(5000) }));
      await assertSucceeds(updateDoc(itemRef('member', 't6'), { title: 'Eggs (dozen)' }));
    });

    test('an edit cannot assign the item to someone who is not in the circle', async () => {
      await assertFails(updateDoc(itemRef('member', 't1'), { assigneeEmail: 'ghost@x.com' }));
    });

    test('the creator and an admin delete an item; another member cannot', async () => {
      await assertFails(deleteDoc(itemRef('other', 't1')));
      await assertSucceeds(deleteDoc(itemRef('member', 't1')));
      await assertSucceeds(create('member', 't5'));
      await assertSucceeds(deleteDoc(itemRef('admin', 't5')));
    });
  });

  describe('the day count', () => {
    test('a member can read their own count, and no one else\'s', async () => {
      await create('member', 'r1');
      await assertSucceeds(getDoc(counterRef('member')));
      const theirs = doc(db('member'), 'tours', FAMILY, 'family_task_daily', `${people.other.email}__${dhakaDayKey()}`);
      await assertFails(getDoc(theirs));
    });

    test('a member cannot write another member\'s count, or delete their own', async () => {
      const batch = writeBatch(db('other'));
      batch.set(itemRef('other', 'o1'), task(people.other.email, { createdAt: serverTimestamp() }));
      batch.set(doc(db('other'), 'tours', FAMILY, 'family_task_daily', `${people.member.email}__${dhakaDayKey()}`),
        { count: 1, email: people.member.email });
      await assertFails(batch.commit());
      await create('member', 'r2');
      await assertFails(deleteDoc(counterRef('member')));
    });

    test('a member starts at most 200 items a Dhaka day', async () => {
      // Seed the day's count at 199, as if 199 items were already started today.
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'tours', FAMILY, 'family_task_daily', `${people.member.email}__${dhakaDayKey()}`),
          { count: 199, email: people.member.email });
      });
      await assertSucceeds(create('member', 'lim1', {}, 200));
      await assertFails(create('member', 'lim2', {}, 201));
    });

    test('the count must go up by exactly one for each item', async () => {
      await create('member', 'step1');
      await assertFails(create('member', 'step2', {}, 3));
      await assertSucceeds(create('member', 'step2', {}, 2));
    });
  });

  test('only members of the circle read its items', async () => {
    await assertSucceeds(getDoc(itemRef('other', 't1')));
    await assertFails(getDoc(doc(db('outsider'), 'tours', FAMILY, 'family_tasks', 't1')));
    await assertSucceeds(getDocs(collection(db('member'), 'tours', FAMILY, 'family_tasks')));
    await assertFails(getDocs(collection(db('outsider'), 'tours', FAMILY, 'family_tasks')));
  });
});
