// A study or book club's shared book list and reading plan. Runs against the Firestore
// emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, Timestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'studyclub';
const HOUSEHOLD = 'studyfamily';
const MESS = 'studymess';
const people = {
  owner: { uid: 'sowner', email: 'sowner@x.com' },
  admin: { uid: 'sadmin', email: 'sadmin@x.com' },
  member: { uid: 'smem', email: 'smem@x.com' },
  other: { uid: 'sother', email: 'sother@x.com' },
  outsider: { uid: 'seve', email: 'seve@x.com' },
};

const book = (by, extra = {}) => ({
  title: 'Anna Karenina',
  author: 'Leo Tolstoy',
  notes: null,
  status: 'toRead',
  statusByEmail: null,
  createdByEmail: by,
  ...extra,
});

const session = (by, extra = {}) => ({
  title: 'Chapters 1 to 3',
  bookId: null,
  startsAt: Timestamp.fromDate(new Date('2026-11-20T18:00:00Z')),
  place: null,
  notes: null,
  createdByEmail: by,
  ...extra,
});

describe('study group rules', () => {
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
      await setDoc(doc(f, 'tours', STUDY), { name: 'Book club', kind: 'family', preset: 'study', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'STUDY0001' });
      await setDoc(doc(f, 'tours', HOUSEHOLD), { name: 'Rahman family', kind: 'family', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'SFAM00001' });
      await setDoc(doc(f, 'tours', MESS), { name: 'Mess', kind: 'family', preset: 'mess', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: 'SMESS0001' });
      const membership = (tourId, email, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), { tourId, email, role, status: 'active', displayName: email });
      for (const tourId of [STUDY, HOUSEHOLD, MESS]) {
        await membership(tourId, people.owner.email, 'owner');
        await membership(tourId, people.admin.email, 'admin');
        await membership(tourId, people.member.email, 'member');
        await membership(tourId, people.other.email, 'member');
      }
      await setDoc(doc(f, 'tours', STUDY, 'study_books', 'b1'), book(people.member.email));
      await setDoc(doc(f, 'tours', STUDY, 'reading_sessions', 's1'), session(people.member.email));
    });
  });

  test('a member adds a book under their own email, and no one else\'s', async () => {
    await assertSucceeds(setDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b2'), book(people.member.email, { title: 'Emma' })));
    await assertFails(setDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b3'), book(people.owner.email)));
    await assertFails(setDoc(doc(db('outsider'), 'tours', STUDY, 'study_books', 'b4'), book(people.outsider.email)));
  });

  test('books and sessions are written only in a study group', async () => {
    const me = people.member.email;
    await assertFails(setDoc(doc(db('member'), 'tours', HOUSEHOLD, 'study_books', 'b2'), book(me)));
    await assertFails(setDoc(doc(db('member'), 'tours', MESS, 'study_books', 'b2'), book(me)));
    await assertFails(setDoc(doc(db('member'), 'tours', HOUSEHOLD, 'reading_sessions', 's2'), session(me)));
    await assertFails(setDoc(doc(db('member'), 'tours', MESS, 'reading_sessions', 's2'), session(me)));
  });

  test('every field of a book is checked on create', async () => {
    const me = people.member.email;
    const bad = [
      { title: '' },
      { title: 'x'.repeat(121) },
      { author: 'x'.repeat(121) },
      { notes: 'x'.repeat(501) },
      { status: 'paused' },
      { statusByEmail: people.owner.email },
      { surprise: true },
    ];
    for (let i = 0; i < bad.length; i++) {
      await assertFails(setDoc(doc(db('member'), 'tours', STUDY, 'study_books', `bad${i}`), book(me, bad[i])));
    }
  });

  test('any member moves a book along its statuses, under their own name', async () => {
    // A status change with no name is refused: the stored name is still empty.
    await assertFails(updateDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1'), { status: 'reading' }));
    // Another person's name on the change is refused.
    await assertFails(updateDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1'), { status: 'reading', statusByEmail: people.owner.email }));
    await assertSucceeds(updateDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1'), { status: 'reading', statusByEmail: people.other.email }));
    // The name on the status is now another member's, so the creator cannot take the change over.
    await assertFails(updateDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b1'), { status: 'finished' }));
    // Moving a status does not let a member change the details.
    await assertFails(updateDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1'), { status: 'finished', statusByEmail: people.other.email, title: 'Sugar' }));
  });

  test('the creator or an admin changes a book\'s details', async () => {
    await assertSucceeds(updateDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b1'), { title: 'Anna Karenina (Garnett)' }));
    // Another member cannot change the details.
    await assertFails(updateDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1'), { title: 'Mine now' }));
    await assertSucceeds(updateDoc(doc(db('admin'), 'tours', STUDY, 'study_books', 'b1'), { title: 'Anna', status: 'reading', statusByEmail: people.admin.email }));
    // Another member's name is now on the status, so an admin cannot change the status under it.
    await assertSucceeds(updateDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1'), { status: 'finished', statusByEmail: people.other.email }));
    await assertFails(updateDoc(doc(db('admin'), 'tours', STUDY, 'study_books', 'b1'), { title: 'Anna again', status: 'reading' }));
  });

  test('a book cannot be handed to someone else', async () => {
    await assertFails(updateDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b1'), { createdByEmail: people.other.email }));
  });

  test('only the creator or an admin removes a book', async () => {
    await assertSucceeds(setDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b5'), book(people.member.email)));
    await assertFails(deleteDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b5')));
    await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', STUDY, 'study_books', 'b5')));
    await assertSucceeds(deleteDoc(doc(db('member'), 'tours', STUDY, 'study_books', 'b1')));
  });

  test('a member plans a session under their own email, and no one else\'s', async () => {
    await assertSucceeds(setDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's2'), session(people.member.email, { bookId: 'b1', place: 'Library' })));
    await assertFails(setDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's3'), session(people.owner.email)));
    await assertFails(setDoc(doc(db('outsider'), 'tours', STUDY, 'reading_sessions', 's4'), session(people.outsider.email)));
  });

  test('every field of a session is checked on create', async () => {
    const me = people.member.email;
    const bad = [
      { title: '' },
      { title: 'x'.repeat(121) },
      { startsAt: '2026-11-20' },
      { place: 'x'.repeat(121) },
      { notes: 'x'.repeat(501) },
      { bookId: 'x'.repeat(101) },
      { surprise: true },
    ];
    for (let i = 0; i < bad.length; i++) {
      await assertFails(setDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', `bad${i}`), session(me, bad[i])));
    }
    // A session needs a start time at all.
    const noStart = session(me);
    delete noStart.startsAt;
    await assertFails(setDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 'nostart'), noStart));
  });

  test('a session is changed by its creator or an admin, not by others', async () => {
    await assertFails(updateDoc(doc(db('other'), 'tours', STUDY, 'reading_sessions', 's1'), { title: 'Chapters 4 to 6' }));
    await assertSucceeds(updateDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's1'), { title: 'Chapters 4 to 6' }));
    await assertSucceeds(updateDoc(doc(db('admin'), 'tours', STUDY, 'reading_sessions', 's1'), { place: 'Cafe' }));
    await assertFails(updateDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's1'), { createdByEmail: people.other.email }));
  });

  test('only the creator or an admin removes a session', async () => {
    await assertFails(deleteDoc(doc(db('other'), 'tours', STUDY, 'reading_sessions', 's1')));
    await assertSucceeds(deleteDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's1')));
  });

  test('outsiders read nothing, and members read the book list and the plan', async () => {
    await assertFails(getDoc(doc(db('outsider'), 'tours', STUDY, 'study_books', 'b1')));
    await assertSucceeds(getDoc(doc(db('other'), 'tours', STUDY, 'study_books', 'b1')));
    await assertFails(getDoc(doc(db('outsider'), 'tours', STUDY, 'reading_sessions', 's1')));
    await assertSucceeds(getDoc(doc(db('other'), 'tours', STUDY, 'reading_sessions', 's1')));
  });
});
