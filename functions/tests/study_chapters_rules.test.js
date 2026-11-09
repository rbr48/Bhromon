// A study group's book chapters, the votes on a proposed book, the members' read marks, and the
// chapters a reading session names. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_chapters_rules"
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
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'chapterclub';
const BOOK = 'b1';
const PROPOSAL = 'p1';
const CHAPTER = 'c1';
const people = {
  owner: { uid: 'chowner', email: 'chowner@x.com' },
  admin: { uid: 'chadmin', email: 'chadmin@x.com' },
  member: { uid: 'chmem', email: 'chmem@x.com' },
  other: { uid: 'chother', email: 'chother@x.com' },
  outsider: { uid: 'cheve', email: 'cheve@x.com' },
};

const book = (by, extra = {}) => ({
  title: 'Anna Karenina',
  author: null,
  notes: null,
  status: 'toRead',
  statusByEmail: null,
  createdByEmail: by,
  approval: 'listed',
  declineNote: null,
  ...extra,
});

const chapter = (extra = {}) => ({
  number: 1,
  title: 'Part one',
  pageFrom: 1,
  pageTo: 20,
  dueOn: Timestamp.fromDate(new Date('2026-11-15T00:00:00Z')),
  guide: ['Why does the first line matter?'],
  ...extra,
});

const session = (by, extra = {}) => ({
  title: 'Chapter 1',
  bookId: BOOK,
  startsAt: Timestamp.fromDate(new Date('2026-11-20T18:00:00Z')),
  place: null,
  notes: null,
  createdByEmail: by,
  ...extra,
});

const bookRef = (f, id = BOOK) => doc(f, 'tours', STUDY, 'study_books', id);
const chapterRef = (f, id = CHAPTER, bookId = BOOK) =>
  doc(f, 'tours', STUDY, 'study_books', bookId, 'chapters', id);
const readRef = (f, email, chapterId = CHAPTER, bookId = BOOK) =>
  doc(f, 'tours', STUDY, 'study_books', bookId, 'chapters', chapterId, 'reads', email);
const voteRef = (f, email, bookId = PROPOSAL) =>
  doc(f, 'tours', STUDY, 'study_books', bookId, 'votes', email);

describe('study chapters, votes and read marks', () => {
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
      await setDoc(doc(f, 'tours', STUDY), {
        name: 'Book club',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'CHAP00001',
      });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${STUDY}__${email}`), { tourId: STUDY, email, role, status: 'active', displayName: email });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      await setDoc(bookRef(f, BOOK), book(people.admin.email));
      await setDoc(bookRef(f, PROPOSAL), book(people.member.email, { approval: 'proposed' }));
      await setDoc(chapterRef(f, CHAPTER), chapter());
    });
  });

  describe('votes on a proposed book', () => {
    test('a member votes for a proposal under their own email', async () => {
      await assertSucceeds(setDoc(voteRef(db('other'), people.other.email), { createdAt: serverTimestamp() }));
    });

    test('a member cannot vote for someone else', async () => {
      await assertFails(setDoc(voteRef(db('other'), people.member.email), { createdAt: serverTimestamp() }));
    });

    test('a vote is only for a proposal, not a listed book', async () => {
      await assertFails(setDoc(voteRef(db('other'), people.other.email, BOOK), { createdAt: serverTimestamp() }));
    });

    test('a vote holds only its time', async () => {
      await assertFails(setDoc(voteRef(db('other'), people.other.email), { createdAt: serverTimestamp(), by: 'x' }));
    });

    test('a member votes once', async () => {
      await assertSucceeds(setDoc(voteRef(db('other'), people.other.email), { createdAt: serverTimestamp() }));
      await assertFails(setDoc(voteRef(db('other'), people.other.email), { createdAt: serverTimestamp() }));
    });

    test('a member takes their own vote back, and cannot take away another', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(voteRef(ctx.firestore(), people.other.email), { createdAt: Timestamp.now() });
      });
      await assertFails(deleteDoc(voteRef(db('member'), people.other.email)));
      await assertSucceeds(deleteDoc(voteRef(db('other'), people.other.email)));
    });

    test('an outsider reads no votes', async () => {
      await assertFails(getDoc(voteRef(db('outsider'), people.outsider.email)));
    });
  });

  describe('chapters', () => {
    test('an admin adds a chapter, and a member cannot', async () => {
      await assertSucceeds(setDoc(chapterRef(db('admin'), 'c2'), chapter({ number: 2, title: 'Part two', pageFrom: null, pageTo: null, guide: [] })));
      await assertFails(setDoc(chapterRef(db('member'), 'c3'), chapter({ number: 3 })));
    });

    test('a chapter number is 1 to 500, and its title is set', async () => {
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ number: 0 })));
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ number: 501 })));
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ title: '' })));
      await assertSucceeds(setDoc(chapterRef(db('admin'), 'c2'), chapter({ number: 500 })));
    });

    test('pages come in a pair, and the last page is not before the first', async () => {
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ pageFrom: 20, pageTo: 10 })));
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ pageFrom: 5, pageTo: null })));
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ pageFrom: null, pageTo: 9 })));
      await assertSucceeds(setDoc(chapterRef(db('admin'), 'c2'), chapter({ pageFrom: 21, pageTo: 21 })));
    });

    test('a chapter keeps up to five guide questions', async () => {
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), chapter({ guide: ['1', '2', '3', '4', '5', '6'] })));
      await assertSucceeds(setDoc(chapterRef(db('admin'), 'c2'), chapter({ guide: ['1', '2', '3', '4', '5'] })));
    });

    test('a chapter takes only its own fields', async () => {
      await assertFails(setDoc(chapterRef(db('admin'), 'c2'), { ...chapter(), reads: 3 }));
    });

    test('an admin changes a chapter\'s due date, and a member cannot', async () => {
      await assertSucceeds(updateDoc(chapterRef(db('admin')), { dueOn: Timestamp.fromDate(new Date('2026-11-22T00:00:00Z')) }));
      await assertFails(updateDoc(chapterRef(db('member')), { dueOn: Timestamp.fromDate(new Date('2026-11-30T00:00:00Z')) }));
    });

    test('an admin removes a chapter, and a member cannot', async () => {
      await assertFails(deleteDoc(chapterRef(db('member'))));
      await assertSucceeds(deleteDoc(chapterRef(db('admin'))));
    });

    test('members read the chapters, and outsiders read nothing', async () => {
      await assertSucceeds(getDoc(chapterRef(db('member'))));
      await assertFails(getDoc(chapterRef(db('outsider'))));
    });
  });

  describe('read marks', () => {
    test('a member marks a chapter read in their own name', async () => {
      await assertSucceeds(setDoc(readRef(db('member'), people.member.email), { readAt: serverTimestamp(), counted: false }));
    });

    test('a read mark takes the server time, not one the member chose', async () => {
      await assertFails(setDoc(readRef(db('member'), people.member.email), {
        readAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')),
        counted: false,
      }));
    });

    test('a member cannot mark a chapter read for someone else', async () => {
      await assertFails(setDoc(readRef(db('member'), people.other.email), { readAt: serverTimestamp(), counted: false }));
    });

    test('a read is marked on a listed book only', async () => {
      await assertFails(setDoc(readRef(db('member'), people.member.email, CHAPTER, PROPOSAL), { readAt: serverTimestamp(), counted: false }));
    });

    test('an uncounted mark is private to its member; a counted one is visible to the group', async () => {
      await assertSucceeds(setDoc(readRef(db('member'), people.member.email), { readAt: serverTimestamp(), counted: false }));
      await assertSucceeds(getDoc(readRef(db('member'), people.member.email)));
      await assertFails(getDoc(readRef(db('other'), people.member.email)));
      await assertSucceeds(updateDoc(readRef(db('member'), people.member.email), { counted: true }));
      await assertSucceeds(getDoc(readRef(db('other'), people.member.email)));
    });

    test('a member changes only whether their mark counts', async () => {
      await assertSucceeds(setDoc(readRef(db('member'), people.member.email), { readAt: serverTimestamp(), counted: false }));
      await assertSucceeds(updateDoc(readRef(db('member'), people.member.email), { counted: true }));
      await assertFails(updateDoc(readRef(db('member'), people.member.email), { readAt: serverTimestamp() }));
      await assertFails(updateDoc(readRef(db('member'), people.member.email), { counted: 'yes' }));
    });

    test('a member takes their own mark back, and cannot take away another', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(readRef(ctx.firestore(), people.other.email), { readAt: Timestamp.now(), counted: true });
      });
      await assertFails(deleteDoc(readRef(db('member'), people.other.email)));
      await assertSucceeds(deleteDoc(readRef(db('other'), people.other.email)));
    });
  });

  describe('a reading session names its chapters', () => {
    test('a session names up to ten chapters of its book', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's1'), session(people.member.email, { chapterIds: [CHAPTER] })));
      const many = Array.from({ length: 11 }, (_, i) => `c${i}`);
      await assertFails(setDoc(doc(db('member'), 'tours', STUDY, 'reading_sessions', 's2'), session(people.member.email, { chapterIds: many })));
    });
  });
});
