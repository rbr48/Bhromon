// A study group's learning tools: quizzes on a chapter, their questions, a member's private attempts, and the
// glossary. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_learning_rules"
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

// Starting the emulator and loading the rules can take longer than Jest's default five-second hook timeout.
jest.setTimeout(120000);

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'learnclub';
const BOOK = 'b1';
const UNLISTED = 'p1';
const QUIZ = 'q1';
const APPROVED_Q = 'qa1';
const PROPOSED_Q = 'qp1';
const APPROVED_T = 't1';
const PROPOSED_T = 't2';
const people = {
  owner: { uid: 'lcowner', email: 'lcowner@x.com' },
  admin: { uid: 'lcadmin', email: 'lcadmin@x.com' },
  member: { uid: 'lcmem', email: 'lcmem@x.com' },
  other: { uid: 'lcother', email: 'lcother@x.com' },
  outsider: { uid: 'lceve', email: 'lceve@x.com' },
};

const created = () => Timestamp.fromDate(new Date('2026-11-02T09:00:00Z'));

const questionFields = (by, extra = {}) => ({
  type: 'single',
  text: 'Who wrote the novel?',
  explanation: 'The novel is by Tolstoy.',
  choices: ['Tolstoy', 'Dostoevsky'],
  answerIndex: 0,
  modelAnswer: null,
  approved: false,
  proposedByEmail: by,
  createdAt: created(),
  ...extra,
});

const termFields = (by, extra = {}) => ({
  term: 'Vronsky',
  definition: 'The officer Anna loves.',
  chapterId: null,
  approved: false,
  createdByEmail: by,
  createdAt: created(),
  ...extra,
});

const quizFields = (by, extra = {}) => ({
  chapterId: 'c1',
  title: 'Chapter one',
  createdByEmail: by,
  takerCount: 0,
  ...extra,
});

const bookRef = (f, id = BOOK) => doc(f, 'tours', STUDY, 'study_books', id);
const quizRef = (f, id = QUIZ, bookId = BOOK) =>
  doc(f, 'tours', STUDY, 'study_books', bookId, 'quizzes', id);
const questionRef = (f, id, quizId = QUIZ) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'quizzes', quizId, 'questions', id);
const attemptRef = (f, email, quizId = QUIZ) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'quizzes', quizId, 'attempts', email);
const termRef = (f, id) => doc(f, 'tours', STUDY, 'study_books', BOOK, 'glossary', id);

const attemptFields = (extra = {}) => ({
  best: 60,
  last: 60,
  attempts: 1,
  updatedAt: serverTimestamp(),
  ...extra,
});

describe('study learning tools: quizzes, questions, attempts and the glossary', () => {
  let env;
  const db = (who) =>
    env
      .authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true })
      .firestore();

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
        name: 'Reading group',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'LRNCLUB01',
      });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${STUDY}__${email}`), {
          tourId: STUDY,
          email,
          role,
          status: 'active',
          displayName: email,
        });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      await setDoc(bookRef(f, BOOK), {
        title: 'Anna Karenina',
        author: null,
        notes: null,
        status: 'toRead',
        statusByEmail: null,
        createdByEmail: people.admin.email,
        approval: 'listed',
        declineNote: null,
      });
      await setDoc(bookRef(f, UNLISTED), {
        title: 'A proposed book',
        author: null,
        notes: null,
        status: 'toRead',
        statusByEmail: null,
        createdByEmail: people.member.email,
        approval: 'proposed',
        declineNote: null,
      });
      await setDoc(quizRef(f), quizFields(people.admin.email));
      await setDoc(questionRef(f, APPROVED_Q), questionFields(people.admin.email, { approved: true }));
      await setDoc(questionRef(f, PROPOSED_Q), questionFields(people.member.email));
      await setDoc(termRef(f, APPROVED_T), termFields(people.admin.email, { approved: true }));
      await setDoc(termRef(f, PROPOSED_T), termFields(people.member.email));
    });
  });

  describe('quizzes', () => {
    test('an admin writes a quiz on a listed book; a member does not', async () => {
      await assertSucceeds(
        setDoc(quizRef(db('admin'), 'q2'), quizFields(people.admin.email)),
      );
      await assertFails(
        setDoc(quizRef(db('member'), 'q3'), quizFields(people.member.email)),
      );
    });

    test('a quiz starts with no takers, and not on an unlisted book', async () => {
      await assertFails(
        setDoc(quizRef(db('admin'), 'q4'), quizFields(people.admin.email, { takerCount: 3 })),
      );
      await assertFails(
        setDoc(quizRef(db('admin'), 'q5', UNLISTED), quizFields(people.admin.email)),
      );
    });

    test('a member cannot change the title, only the taker count, and only with an attempt', async () => {
      await assertFails(updateDoc(quizRef(db('member')), { title: 'Renamed' }));
      await assertFails(updateDoc(quizRef(db('member')), { takerCount: increment(1) }));
    });

    test('a member’s first attempt moves the taker count up by one in the same batch', async () => {
      const f = db('member');
      const batch = writeBatch(f);
      batch.set(attemptRef(f, people.member.email), attemptFields());
      batch.update(quizRef(f), { takerCount: increment(1) });
      await assertSucceeds(batch.commit());
    });

    test('an attempt without the taker count moving is refused', async () => {
      await assertFails(
        setDoc(attemptRef(db('member'), people.member.email), attemptFields()),
      );
    });
  });

  describe('questions', () => {
    test('a member proposes a question in their own name, not yet approved', async () => {
      await assertSucceeds(
        setDoc(questionRef(db('member'), 'qn1'), {
          ...questionFields(people.member.email),
          createdAt: serverTimestamp(),
        }),
      );
    });

    test('a member cannot propose an approved question, or one in someone else’s name', async () => {
      await assertFails(
        setDoc(questionRef(db('member'), 'qn2'), {
          ...questionFields(people.member.email, { approved: true }),
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(
        setDoc(questionRef(db('member'), 'qn3'), {
          ...questionFields(people.admin.email),
          createdAt: serverTimestamp(),
        }),
      );
    });

    test('an admin approves a proposal; a member cannot', async () => {
      await assertFails(updateDoc(questionRef(db('member'), PROPOSED_Q), { approved: true }));
      await assertSucceeds(updateDoc(questionRef(db('admin'), PROPOSED_Q), { approved: true }));
    });

    test('a member withdraws their own proposal, but not an approved question or someone else’s', async () => {
      await assertSucceeds(deleteDoc(questionRef(db('member'), PROPOSED_Q)));
      await assertFails(deleteDoc(questionRef(db('member'), APPROVED_Q)));
      await assertFails(deleteDoc(questionRef(db('other'), PROPOSED_Q)));
    });

    test('a single-answer question needs its choices and a right answer in range', async () => {
      await assertFails(
        setDoc(questionRef(db('member'), 'qn4'), {
          ...questionFields(people.member.email, { answerIndex: 5 }),
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(
        setDoc(questionRef(db('member'), 'qn5'), {
          ...questionFields(people.member.email, { choices: ['Only one'] }),
          createdAt: serverTimestamp(),
        }),
      );
    });
  });

  describe('private attempts', () => {
    test('only the member reads their own attempt', async () => {
      const f = db('member');
      const batch = writeBatch(f);
      batch.set(attemptRef(f, people.member.email), attemptFields({ best: 80, last: 80 }));
      batch.update(quizRef(f), { takerCount: increment(1) });
      await batch.commit();
      await assertSucceeds(getDoc(attemptRef(db('member'), people.member.email)));
      await assertFails(getDoc(attemptRef(db('other'), people.member.email)));
      await assertFails(getDoc(attemptRef(db('admin'), people.member.email)));
    });

    test('a retake counts up by one and keeps the record’s time', async () => {
      const f = db('member');
      const first = writeBatch(f);
      first.set(attemptRef(f, people.member.email), attemptFields());
      first.update(quizRef(f), { takerCount: increment(1) });
      await first.commit();
      await assertSucceeds(
        updateDoc(attemptRef(f, people.member.email), {
          best: 90,
          last: 90,
          attempts: 2,
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(attemptRef(f, people.member.email), {
          best: 90,
          last: 90,
          attempts: 5,
          updatedAt: serverTimestamp(),
        }),
      );
    });

    test('a member cannot write someone else’s attempt', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(attemptRef(f, people.member.email), attemptFields());
      batch.update(quizRef(f), { takerCount: increment(1) });
      await assertFails(batch.commit());
    });
  });

  describe('the glossary', () => {
    test('a member proposes a term in their own name, not yet approved', async () => {
      await assertSucceeds(
        setDoc(termRef(db('other'), 'tn1'), {
          ...termFields(people.other.email),
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(
        setDoc(termRef(db('other'), 'tn2'), {
          ...termFields(people.other.email, { approved: true }),
          createdAt: serverTimestamp(),
        }),
      );
    });

    test('an admin approves a term; a member cannot', async () => {
      await assertFails(updateDoc(termRef(db('member'), PROPOSED_T), { approved: true }));
      await assertSucceeds(updateDoc(termRef(db('admin'), PROPOSED_T), { approved: true }));
    });

    test('a member withdraws their own proposed term only', async () => {
      await assertSucceeds(deleteDoc(termRef(db('member'), PROPOSED_T)));
      await assertFails(deleteDoc(termRef(db('member'), APPROVED_T)));
    });

    test('everyone in the group reads the glossary; an outsider does not', async () => {
      await assertSucceeds(getDoc(termRef(db('other'), APPROVED_T)));
      await assertFails(getDoc(termRef(db('outsider'), APPROVED_T)));
    });
  });
});
