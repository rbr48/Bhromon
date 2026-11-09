// A study group's discussions: threads on a book, the replies in them, the helpful marks and reports on
// replies, the accepted answer, pins and locks. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_threads_rules"
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
  writeBatch,
  increment,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'threadclub';
const BOOK = 'b1';
const PROPOSAL = 'p1';
const OPEN = 't1';
const LOCKED = 't2';
const MINE = 'r1';
const THEIRS = 'r2';
const LOCKED_REPLY = 'r3';
const people = {
  owner: { uid: 'thowner', email: 'thowner@x.com' },
  admin: { uid: 'thadmin', email: 'thadmin@x.com' },
  member: { uid: 'thmem', email: 'thmem@x.com' },
  other: { uid: 'thother', email: 'thother@x.com' },
  outsider: { uid: 'theve', email: 'theve@x.com' },
};

const bookFields = (by, extra = {}) => ({
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

const threadFields = (by, extra = {}) => ({
  title: 'Why the train?',
  body: 'The train appears three times.',
  pageRef: 'p. 34',
  chapterId: null,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-02T09:00:00Z')),
  pinned: false,
  locked: false,
  acceptedReplyId: null,
  ...extra,
});

const replyFields = (by, extra = {}) => ({
  text: 'It marks the turning point.',
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-02T10:00:00Z')),
  helpfulCount: 0,
  reportCount: 0,
  ...extra,
});

const bookRef = (f, id = BOOK) => doc(f, 'tours', STUDY, 'study_books', id);
const threadRef = (f, id = OPEN, bookId = BOOK) =>
  doc(f, 'tours', STUDY, 'study_books', bookId, 'threads', id);
const replyRef = (f, id, threadId = OPEN, bookId = BOOK) =>
  doc(f, 'tours', STUDY, 'study_books', bookId, 'threads', threadId, 'replies', id);
const helpfulRef = (f, replyId, email, threadId = OPEN) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'threads', threadId, 'replies', replyId, 'helpful', email);
const reportRef = (f, replyId, email, threadId = OPEN) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'threads', threadId, 'replies', replyId, 'reports', email);

describe('study discussions: threads, replies, helpful marks and reports', () => {
  let env;
  const db = (who) =>
    env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

  // A member marks a reply helpful: the mark and the count change in one batch.
  const markHelpful = (who, replyId, threadId = OPEN) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.set(helpfulRef(f, replyId, people[who].email, threadId), { createdAt: serverTimestamp() });
    batch.update(replyRef(f, replyId, threadId), { helpfulCount: increment(1) });
    return batch.commit();
  };
  // A member takes the mark back: the mark goes and the count falls in one batch.
  const unmarkHelpful = (who, replyId, threadId = OPEN) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.delete(helpfulRef(f, replyId, people[who].email, threadId));
    batch.update(replyRef(f, replyId, threadId), { helpfulCount: increment(-1) });
    return batch.commit();
  };
  // A member reports a reply: the report and the count change in one batch.
  const report = (who, replyId, reason = 'wrong', threadId = OPEN) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.set(reportRef(f, replyId, people[who].email, threadId), { reason, createdAt: serverTimestamp() });
    batch.update(replyRef(f, replyId, threadId), { reportCount: increment(1) });
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
      await setDoc(doc(f, 'tours', STUDY), {
        name: 'Book club',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'THRD00001',
      });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${STUDY}__${email}`), { tourId: STUDY, email, role, status: 'active', displayName: email });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      await setDoc(bookRef(f, BOOK), bookFields(people.admin.email));
      await setDoc(bookRef(f, PROPOSAL), bookFields(people.member.email, { approval: 'proposed' }));
      await setDoc(threadRef(f, OPEN), threadFields(people.member.email));
      await setDoc(threadRef(f, LOCKED), threadFields(people.other.email, { locked: true }));
      await setDoc(replyRef(f, MINE), replyFields(people.member.email));
      await setDoc(replyRef(f, THEIRS), replyFields(people.other.email));
      await setDoc(replyRef(f, LOCKED_REPLY, LOCKED), replyFields(people.other.email));
    });
  });

  describe('starting a thread', () => {
    test('a member starts a thread on a listed book under their own email', async () => {
      await assertSucceeds(setDoc(threadRef(db('other'), 'new1'), { ...threadFields(people.other.email), createdAt: serverTimestamp() }));
    });

    test('a member cannot start a thread under someone else\'s email', async () => {
      await assertFails(setDoc(threadRef(db('other'), 'new2'), { ...threadFields(people.member.email), createdAt: serverTimestamp() }));
    });

    test('a thread is started on a listed book only', async () => {
      await assertFails(setDoc(threadRef(db('other'), 'new3', PROPOSAL), { ...threadFields(people.other.email), createdAt: serverTimestamp() }));
    });

    test('a thread starts unpinned, unlocked and unanswered', async () => {
      await assertFails(setDoc(threadRef(db('other'), 'new4'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), pinned: true }));
      await assertFails(setDoc(threadRef(db('other'), 'new5'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), locked: true }));
      await assertFails(setDoc(threadRef(db('other'), 'new6'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), acceptedReplyId: THEIRS }));
    });

    test('a title and a body can be any length', async () => {
      await assertFails(setDoc(threadRef(db('other'), 'new7'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), title: '' }));
      await assertSucceeds(setDoc(threadRef(db('other'), 'new8'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), title: 'x'.repeat(121) }));
      await assertSucceeds(setDoc(threadRef(db('other'), 'new9'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), body: 'x'.repeat(2001) }));
      await assertSucceeds(setDoc(threadRef(db('other'), 'new10'), { ...threadFields(people.other.email), createdAt: serverTimestamp(), body: 'x'.repeat(2000) }));
    });

    test('a thread carries the server time', async () => {
      await assertFails(setDoc(threadRef(db('other'), 'new11'), { ...threadFields(people.other.email), createdAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')) }));
    });

    test('an outsider reads no thread', async () => {
      await assertFails(getDoc(threadRef(db('outsider'))));
    });
  });

  describe('accepting an answer, pinning and locking', () => {
    test('the member who asked accepts a reply, and takes the acceptance back', async () => {
      await assertSucceeds(updateDoc(threadRef(db('member')), { acceptedReplyId: THEIRS }));
      await assertSucceeds(updateDoc(threadRef(db('member')), { acceptedReplyId: null }));
    });

    test('an accepted answer must be a reply that exists', async () => {
      await assertFails(updateDoc(threadRef(db('member')), { acceptedReplyId: 'missing' }));
    });

    test('another member cannot accept an answer to someone else\'s question', async () => {
      await assertFails(updateDoc(threadRef(db('other')), { acceptedReplyId: THEIRS }));
    });

    test('the asker changes nothing but the acceptance', async () => {
      await assertFails(updateDoc(threadRef(db('member')), { title: 'Changed' }));
      await assertFails(updateDoc(threadRef(db('member')), { pinned: true }));
      await assertFails(updateDoc(threadRef(db('member')), { locked: true }));
    });

    test('an admin pins and locks a thread, and accepts an answer on the asker\'s behalf', async () => {
      await assertSucceeds(updateDoc(threadRef(db('admin')), { pinned: true }));
      await assertSucceeds(updateDoc(threadRef(db('admin')), { locked: true }));
      await assertSucceeds(updateDoc(threadRef(db('admin')), { acceptedReplyId: THEIRS }));
    });

    test('a member cannot pin or lock a thread', async () => {
      await assertFails(updateDoc(threadRef(db('other')), { pinned: true }));
      await assertFails(updateDoc(threadRef(db('other')), { locked: false }));
    });

    test('an author or an admin removes a thread; another member cannot', async () => {
      await assertFails(deleteDoc(threadRef(db('other'))));
      await assertSucceeds(deleteDoc(threadRef(db('admin'))));
    });
  });

  describe('replying', () => {
    test('a member replies to an open thread under their own email', async () => {
      await assertSucceeds(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.other.email), createdAt: serverTimestamp() }));
    });

    test('nobody replies to a locked thread', async () => {
      await assertFails(setDoc(replyRef(db('member'), 'new-reply', LOCKED), { ...replyFields(people.member.email), createdAt: serverTimestamp() }));
    });

    test('a reply starts with no votes and no reports', async () => {
      await assertFails(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.other.email), createdAt: serverTimestamp(), helpfulCount: 1 }));
      await assertFails(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.other.email), createdAt: serverTimestamp(), reportCount: 1 }));
    });

    test('a reply is 1 to 1000 characters', async () => {
      await assertFails(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.other.email), createdAt: serverTimestamp(), text: '' }));
      await assertFails(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.other.email), createdAt: serverTimestamp(), text: 'x'.repeat(1001) }));
      await assertSucceeds(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.other.email), createdAt: serverTimestamp(), text: 'x'.repeat(1000) }));
    });

    test('a member cannot reply under someone else\'s email', async () => {
      await assertFails(setDoc(replyRef(db('other'), 'new-reply'), { ...replyFields(people.member.email), createdAt: serverTimestamp() }));
    });

    test('an author edits the text of their own reply; nothing else changes', async () => {
      await assertSucceeds(updateDoc(replyRef(db('member'), MINE), { text: 'It marks the turning point. Edited.' }));
      await assertFails(updateDoc(replyRef(db('member'), MINE), { helpfulCount: 5 }));
      await assertFails(updateDoc(replyRef(db('other'), MINE), { text: 'Not mine' }));
    });

    test('an author or an admin removes a reply; another member cannot', async () => {
      await assertFails(deleteDoc(replyRef(db('other'), MINE)));
      await assertSucceeds(deleteDoc(replyRef(db('admin'), MINE)));
    });
  });

  describe('helpful marks', () => {
    test('a member marks another member\'s reply helpful, and the count rises with the mark', async () => {
      await assertSucceeds(markHelpful('member', THEIRS));
      const snap = await getDoc(replyRef(db('admin'), THEIRS));
      expect(snap.data().helpfulCount).toBe(1);
    });

    test('a count cannot rise without the member\'s mark', async () => {
      await assertFails(updateDoc(replyRef(db('member'), THEIRS), { helpfulCount: increment(1) }));
    });

    test('a member cannot mark their own reply', async () => {
      await assertFails(markHelpful('member', MINE));
    });

    test('a member marks a reply once, and takes the mark back', async () => {
      await assertSucceeds(markHelpful('member', THEIRS));
      await assertFails(markHelpful('member', THEIRS));
      await assertSucceeds(unmarkHelpful('member', THEIRS));
      const snap = await getDoc(replyRef(db('admin'), THEIRS));
      expect(snap.data().helpfulCount).toBe(0);
    });

    test('a member cannot take away another member\'s mark', async () => {
      await assertSucceeds(markHelpful('member', THEIRS));
      // Signed in as another member, remove the mark that belongs to the first member.
      const f = db('other');
      const batch = writeBatch(f);
      batch.delete(helpfulRef(f, THEIRS, people.member.email));
      batch.update(replyRef(f, THEIRS), { helpfulCount: increment(-1) });
      await assertFails(batch.commit());
    });
  });

  describe('reports', () => {
    test('a member reports another member\'s reply once, and the count rises with the report', async () => {
      await assertSucceeds(report('member', THEIRS, 'unclear'));
      await assertFails(report('member', THEIRS, 'unclear'));
      const snap = await getDoc(replyRef(db('admin'), THEIRS));
      expect(snap.data().reportCount).toBe(1);
    });

    test('a report has one of the reasons', async () => {
      await assertFails(report('member', THEIRS, 'bogus'));
    });

    test('a member cannot report their own reply', async () => {
      await assertFails(report('member', MINE, 'spam'));
    });

    test('a report is written with the count, not alone', async () => {
      const f = db('member');
      await assertFails(setDoc(reportRef(f, THEIRS, people.member.email), { reason: 'spam', createdAt: serverTimestamp() }));
    });

    test('the reporter and an admin read a report; other members do not', async () => {
      await assertSucceeds(report('member', THEIRS, 'spam'));
      await assertSucceeds(getDoc(reportRef(db('member'), THEIRS, people.member.email)));
      await assertSucceeds(getDoc(reportRef(db('admin'), THEIRS, people.member.email)));
      await assertFails(getDoc(reportRef(db('other'), THEIRS, people.member.email)));
    });
  });
});
