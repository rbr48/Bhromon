// Family dates: birthdays, bills and school times kept by a family circle. Runs
// against the Firestore emulator on port 8080, like the other tour rules suites:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/family_dates_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const FAMILY = 'famdates';
const TRIP = 'tripdates';
const people = {
  owner: { uid: 'fown', email: 'fown@x.com' },
  admin: { uid: 'fadm', email: 'fadm@x.com' },
  member: { uid: 'fmem', email: 'fmem@x.com' },
  other: { uid: 'foth', email: 'foth@x.com' },
  outsider: { uid: 'feve', email: 'feve@x.com' },
};

const date = (by, extra = {}) => ({
  title: "Asha's birthday",
  kind: 'birthday',
  recurrence: 'yearly',
  startOn: '2000-11-03',
  nextOn: '2026-11-03',
  remindDays: 7,
  remindOn: '2026-10-27',
  note: '',
  createdByEmail: by,
  ...extra,
});

describe('family dates rules', () => {
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
      await setDoc(doc(f, 'tours', FAMILY), { name: 'Rahman family', kind: 'family', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'FAMDATE1' });
      await setDoc(doc(f, 'tours', TRIP), { name: 'Trip', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'TRIPDAT1' });
      const membership = (tourId, email, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), { tourId, email, role, status: 'active', displayName: email });
      await membership(FAMILY, people.owner.email, 'owner');
      await membership(FAMILY, people.admin.email, 'admin');
      await membership(FAMILY, people.member.email, 'member');
      await membership(FAMILY, people.other.email, 'member');
      await membership(TRIP, people.owner.email, 'owner');
      await membership(TRIP, people.member.email, 'member');
      await setDoc(doc(f, 'tours', FAMILY, 'family_dates', 'd1'), date(people.member.email));
    });
  });

  test('a family member adds a date under their own email only', async () => {
    await assertSucceeds(setDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd2'), date(people.member.email)));
    await assertFails(setDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd3'), date(people.owner.email)));
    await assertFails(setDoc(doc(db('outsider'), 'tours', FAMILY, 'family_dates', 'd4'), date(people.outsider.email)));
  });

  test('a trip has no family dates', async () => {
    await assertFails(setDoc(doc(db('member'), 'tours', TRIP, 'family_dates', 'd2'), date(people.member.email)));
  });

  test('every field is checked on create', async () => {
    const me = people.member.email;
    const bad = [
      { title: '' },
      { title: 'x'.repeat(81) },
      { kind: 'party' },
      { recurrence: 'weekly' },
      { startOn: '3 Nov 2000' },
      { nextOn: '2026-11-3' },
      { remindDays: 31 },
      { remindDays: 1.5 },
      { remindDays: '7' },
      { remindOn: 'tomorrow' },
      { note: 'x'.repeat(501) },
      { surprise: true },
    ];
    for (let i = 0; i < bad.length; i++) {
      await assertFails(setDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', `bad${i}`), date(me, bad[i])));
    }
    // A date with no reminder due carries a null remindOn.
    await assertSucceeds(setDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'ok1'), date(me, { remindOn: null })));
  });

  test('the creator edits their own date, and an admin or the owner edits any', async () => {
    await assertSucceeds(updateDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd1'), { title: 'Asha bday' }));
    await assertSucceeds(updateDoc(doc(db('admin'), 'tours', FAMILY, 'family_dates', 'd1'), { title: 'Asha birthday' }));
    await assertSucceeds(updateDoc(doc(db('owner'), 'tours', FAMILY, 'family_dates', 'd1'), { note: 'Cake' }));
    await assertFails(updateDoc(doc(db('other'), 'tours', FAMILY, 'family_dates', 'd1'), { title: 'Hijack' }));
  });

  test('nobody hands a date to another person, even its creator', async () => {
    await assertFails(updateDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd1'), { createdByEmail: people.other.email }));
    await assertFails(updateDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd1'), { title: 'x'.repeat(81) }));
  });

  test('the creator and an admin delete a date; another member cannot', async () => {
    await assertFails(deleteDoc(doc(db('other'), 'tours', FAMILY, 'family_dates', 'd1')));
    await assertSucceeds(deleteDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd1')));
    // A separate date, so the admin's delete does not touch the creator's one.
    await assertSucceeds(setDoc(doc(db('member'), 'tours', FAMILY, 'family_dates', 'd5'), date(people.member.email)));
    await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', FAMILY, 'family_dates', 'd5')));
  });

  test('only members of the circle read its dates', async () => {
    await assertSucceeds(getDoc(doc(db('other'), 'tours', FAMILY, 'family_dates', 'd1')));
    await assertFails(getDoc(doc(db('outsider'), 'tours', FAMILY, 'family_dates', 'd1')));
    await assertSucceeds(getDocs(collection(db('member'), 'tours', FAMILY, 'family_dates')));
    await assertFails(getDocs(collection(db('outsider'), 'tours', FAMILY, 'family_dates')));
  });

  test('a due-date query for the reminder job is for members only', async () => {
    await assertSucceeds(getDocs(query(collection(db('member'), 'tours', FAMILY, 'family_dates'), where('remindOn', '<=', '2026-10-31'))));
    await assertFails(getDocs(query(collection(db('outsider'), 'tours', FAMILY, 'family_dates'), where('remindOn', '<=', '2026-10-31'))));
  });
});
