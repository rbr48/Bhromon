// A study group's problems: the statements an admin or a member posts, the reference solution an admin
// writes and that opens to members at its release time, each member's own working, and the reviews of
// that working. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_problems_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const {
  doc,
  collection,
  getDoc,
  getDocs,
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
const STUDY = 'problemclub';
const SUBJECT = 'calc101';
const APPROVAL = 'calc2';
const OFF = 'calc3';
const PROPOSED = 'calc4';
const P_ADMIN = 'pr-admin';
const P_MEMBER = 'pr-member';
const P_WAITING = 'pr-waiting';
const P_SCHEDULED = 'pr-scheduled';
const P_NOREF = 'pr-noref';
const P_REVIEW = 'pr-review';
const people = {
  owner: { uid: 'prowner', email: 'prowner@x.com' },
  admin: { uid: 'pradmin', email: 'pradmin@x.com' },
  member: { uid: 'prmem', email: 'prmem@x.com' },
  other: { uid: 'proth', email: 'proth@x.com' },
  outsider: { uid: 'preve', email: 'preve@x.com' },
};

const PAST = Timestamp.fromDate(new Date('2020-01-01T00:00:00Z'));
const FUTURE = Timestamp.fromDate(new Date('2999-01-01T00:00:00Z'));

const subject = (by, extra = {}) => ({
  title: 'Calculus 101',
  code: 'MAT 101',
  description: null,
  examDate: null,
  approval: 'listed',
  declineNote: null,
  createdByEmail: by,
  ...extra,
});

const moduleSettings = (extra = {}) => ({ enabled: true, name: 'Problems', postPolicy: 'members', ...extra });

// A problem as it was stored earlier: a fixed time, so the server-time rule does not apply.
const problem = (by, extra = {}) => ({
  text: 'Find the mean of 2, 4 and 9.',
  title: null,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-01T10:00:00Z')),
  releaseAt: null,
  shown: true,
  pinned: false,
  ...extra,
});

// A problem as it is written now: the server stamps the time, as the app does.
const newProblem = (by, extra = {}) => ({ ...problem(by), createdAt: serverTimestamp(), ...extra });

// The reference solution as an admin writes it.
const reference = (by, extra = {}) => ({
  text: 'The mean is 5.',
  reviewedByEmail: by,
  updatedAt: Timestamp.fromDate(new Date('2026-11-01T11:00:00Z')),
  ...extra,
});

// A working as it was stored earlier, with its review counts.
const work = (extra = {}) => ({
  text: 'The working, step by step.',
  createdAt: Timestamp.fromDate(new Date('2026-11-01T10:00:00Z')),
  updatedAt: Timestamp.fromDate(new Date('2026-11-01T10:00:00Z')),
  rightCount: 0,
  gapCount: 0,
  ...extra,
});

// A working as it is written now: the server stamps the times, and the counts start at zero.
const newWork = (extra = {}) => ({ ...work(), createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });

const subjectRef = (f, id = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', id);
const moduleRef = (f, id = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', id, 'modules', 'problems');
const problemRef = (f, id, subjectId = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', id);
const referenceRef = (f, problemId, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', problemId, 'reference', 'solution');
const workRef = (f, problemId, solverEmail, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', problemId, 'solutions', solverEmail);
const reviewRef = (f, problemId, solverEmail, reviewerEmail, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', problemId, 'solutions', solverEmail, 'reviews', reviewerEmail);
const worksCollection = (f, problemId, subjectId = SUBJECT) =>
  collection(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', problemId, 'solutions');

describe('problems, reference solutions, working and reviews', () => {
  let env;
  const db = (who) =>
    env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

  // A member reviews a working: the review and its count are written in one batch.
  const reviewBatch = (who, problemId, solverEmail, verdict, subjectId = SUBJECT, extra = {}) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.set(reviewRef(f, problemId, solverEmail, people[who].email, subjectId), {
      verdict,
      createdAt: serverTimestamp(),
      ...extra,
    });
    batch.update(
      workRef(f, problemId, solverEmail, subjectId),
      verdict === 'right' ? { rightCount: increment(1) } : { gapCount: increment(1) },
    );
    return batch.commit();
  };

  // A member takes their own review back: the review goes and its count falls, in one batch.
  const withdrawBatch = (who, problemId, solverEmail, verdict, subjectId = SUBJECT) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.delete(reviewRef(f, problemId, solverEmail, people[who].email, subjectId));
    batch.update(
      workRef(f, problemId, solverEmail, subjectId),
      verdict === 'right' ? { rightCount: increment(-1) } : { gapCount: increment(-1) },
    );
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
        name: 'Study group',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'PROB00001',
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

      // A listed subject whose problems module is on (members post).
      await setDoc(subjectRef(f), subject(people.admin.email));
      await setDoc(moduleRef(f), moduleSettings());

      // An admin's problem, released in the past, with its reference and one working by another member.
      await setDoc(problemRef(f, P_ADMIN), problem(people.admin.email, { releaseAt: PAST }));
      await setDoc(referenceRef(f, P_ADMIN), reference(people.admin.email));
      await setDoc(workRef(f, P_ADMIN, people.other.email), work({ text: 'Another working on the first problem.' }));

      // A member's problem: the member's own working, and another member's working with the member's gap review.
      await setDoc(problemRef(f, P_MEMBER), problem(people.member.email));
      await setDoc(workRef(f, P_MEMBER, people.member.email), work({ text: 'My working on the member problem.' }));
      await setDoc(workRef(f, P_MEMBER, people.other.email), work({ text: 'Another working on the member problem.', gapCount: 1 }));
      await setDoc(reviewRef(f, P_MEMBER, people.other.email, people.member.email), {
        verdict: 'gap',
        note: 'Check the second step.',
        createdAt: Timestamp.fromDate(new Date('2026-11-01T12:00:00Z')),
      });

      // A problem waiting for an admin to show it.
      await setDoc(problemRef(f, P_WAITING), problem(people.member.email, { shown: false }));

      // A problem whose reference opens in the far future, with a reference already written.
      await setDoc(problemRef(f, P_SCHEDULED), problem(people.admin.email, { releaseAt: FUTURE }));
      await setDoc(referenceRef(f, P_SCHEDULED), reference(people.admin.email));

      // A released problem with no reference written yet.
      await setDoc(problemRef(f, P_NOREF), problem(people.admin.email, { releaseAt: PAST }));

      // A problem where the member and another member have each submitted their working, and nothing is reviewed.
      await setDoc(problemRef(f, P_REVIEW), problem(people.admin.email));
      await setDoc(workRef(f, P_REVIEW, people.member.email), work({ text: 'Member working to review.' }));
      await setDoc(workRef(f, P_REVIEW, people.other.email), work({ text: 'Other working to review.' }));

      // An approval module (members' problems wait for an admin), an off module, and a proposal.
      await setDoc(subjectRef(f, APPROVAL), subject(people.admin.email, { title: 'Calculus 2' }));
      await setDoc(moduleRef(f, APPROVAL), moduleSettings({ postPolicy: 'approval' }));
      await setDoc(subjectRef(f, OFF), subject(people.admin.email, { title: 'Calculus 3' }));
      await setDoc(moduleRef(f, OFF), moduleSettings({ enabled: false }));
      await setDoc(subjectRef(f, PROPOSED), subject(people.member.email, { title: 'Probability', code: null, approval: 'proposed' }));
      await setDoc(moduleRef(f, PROPOSED), moduleSettings());
    });
  });

  describe('posting a problem', () => {
    test('a member posts a problem under their own email, shown and unpinned', async () => {
      await assertSucceeds(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.member.email)));
    });

    test('a member cannot post under someone else\'s email, nor post one an admin has not shown', async () => {
      await assertFails(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.owner.email)));
      await assertFails(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.member.email, { shown: false })));
    });

    test('a problem statement is required and at most 1,000 characters, and a title at most 120', async () => {
      await assertFails(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.member.email, { text: '' })));
      await assertFails(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.member.email, { text: 'x'.repeat(1001) })));
      await assertFails(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.member.email, { title: 'x'.repeat(121) })));
      await assertSucceeds(setDoc(problemRef(db('member'), 'pr-new'), newProblem(people.member.email, { text: 'x'.repeat(1000) })));
    });

    test('a problem cannot be posted when its module is off, by a member or an admin', async () => {
      await assertFails(setDoc(problemRef(db('member'), 'pr-new', OFF), newProblem(people.member.email)));
      await assertFails(setDoc(problemRef(db('admin'), 'pr-new', OFF), newProblem(people.admin.email)));
    });

    test('in an approval module a member\'s problem waits for an admin, and an admin\'s is shown at once', async () => {
      await assertSucceeds(setDoc(problemRef(db('member'), 'pr-new', APPROVAL), newProblem(people.member.email, { shown: false })));
      await assertFails(setDoc(problemRef(db('member'), 'pr-new2', APPROVAL), newProblem(people.member.email, { shown: true })));
      await assertSucceeds(setDoc(problemRef(db('admin'), 'pr-new3', APPROVAL), newProblem(people.admin.email, { shown: true })));
      await assertFails(setDoc(problemRef(db('admin'), 'pr-new4', APPROVAL), newProblem(people.admin.email, { shown: false })));
    });

    test('a problem cannot be posted in a proposal, which takes no problems until it is listed', async () => {
      await assertFails(setDoc(problemRef(db('member'), 'pr-new', PROPOSED), newProblem(people.member.email)));
    });
  });

  describe('editing and scheduling a problem', () => {
    test('the author changes the statement and the title, and no other member does', async () => {
      await assertSucceeds(updateDoc(problemRef(db('member'), P_MEMBER), { text: 'Revised statement.', title: 'Mean' }));
      await assertFails(updateDoc(problemRef(db('other'), P_MEMBER), { text: 'Hijacked' }));
    });

    test('an author cannot set the release day or show a waiting problem', async () => {
      await assertFails(updateDoc(problemRef(db('member'), P_MEMBER), { releaseAt: FUTURE }));
      await assertFails(updateDoc(problemRef(db('member'), P_WAITING), { shown: true }));
    });

    test('an admin sets the release day, shows a waiting problem and pins one', async () => {
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_MEMBER), { releaseAt: PAST }));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_WAITING), { shown: true }));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_MEMBER), { pinned: true }));
    });
  });

  describe('the reference solution', () => {
    test('an admin writes it, marked with their own name as the reviewer', async () => {
      await assertSucceeds(setDoc(referenceRef(db('admin'), P_NOREF), reference(people.admin.email, {
        updatedAt: serverTimestamp(),
      })));
    });

    test('a member cannot write it, and an admin cannot write it under someone else\'s name', async () => {
      await assertFails(setDoc(referenceRef(db('member'), P_NOREF), reference(people.member.email, {
        updatedAt: serverTimestamp(),
      })));
      await assertFails(setDoc(referenceRef(db('admin'), P_NOREF), reference(people.owner.email, {
        updatedAt: serverTimestamp(),
      })));
    });

    test('a member reads it once the problem is shown and its release day has come', async () => {
      await assertSucceeds(getDoc(referenceRef(db('member'), P_ADMIN)));
    });

    test('a member cannot read it before its release day, nor for a problem an admin has not shown', async () => {
      await assertFails(getDoc(referenceRef(db('member'), P_SCHEDULED)));
      await assertFails(getDoc(referenceRef(db('member'), P_MEMBER)));
    });

    test('an admin reads it at any time', async () => {
      await assertSucceeds(getDoc(referenceRef(db('admin'), P_SCHEDULED)));
    });
  });

  describe('submitting a working', () => {
    test('a member submits their own working once, with no reviews yet', async () => {
      await assertSucceeds(setDoc(workRef(db('member'), P_NOREF, people.member.email), newWork()));
    });

    test('a member submits only under their own email, and never with reviews already counted', async () => {
      await assertFails(setDoc(workRef(db('member'), P_NOREF, people.other.email), newWork()));
      await assertFails(setDoc(workRef(db('member'), P_NOREF, people.member.email), newWork({ rightCount: 1 })));
    });

    test('a member cannot submit on a problem an admin has not shown', async () => {
      await assertFails(setDoc(workRef(db('member'), P_WAITING, people.member.email), newWork()));
    });

    test('a member cannot submit a second working on the same problem', async () => {
      await assertFails(setDoc(workRef(db('member'), P_MEMBER, people.member.email), newWork({ text: 'Second try.' })));
    });

    test('a member edits the text of their own working, and cannot change its counts', async () => {
      await assertSucceeds(updateDoc(workRef(db('member'), P_MEMBER, people.member.email), {
        text: 'Revised working.',
        updatedAt: serverTimestamp(),
      }));
      await assertFails(updateDoc(workRef(db('member'), P_MEMBER, people.member.email), { rightCount: increment(1) }));
    });

    test('no member edits another member\'s working', async () => {
      await assertFails(updateDoc(workRef(db('member'), P_MEMBER, people.other.email), {
        text: 'Changed by someone else.',
        updatedAt: serverTimestamp(),
      }));
    });
  });

  describe('reading the working of others', () => {
    test('a member who has submitted their own reads and lists the others\' working', async () => {
      await assertSucceeds(getDoc(workRef(db('member'), P_MEMBER, people.other.email)));
      await assertSucceeds(getDocs(worksCollection(db('member'), P_MEMBER)));
    });

    test('a member who has not submitted their own cannot read or list the others\' working', async () => {
      await assertFails(getDoc(workRef(db('member'), P_ADMIN, people.other.email)));
      await assertFails(getDocs(worksCollection(db('member'), P_ADMIN)));
    });

    test('a member reads their own working even before submitting any other', async () => {
      await assertSucceeds(getDoc(workRef(db('member'), P_ADMIN, people.member.email)));
    });

    test('an outsider reads no problem, reference or working', async () => {
      await assertFails(getDoc(problemRef(db('outsider'), P_MEMBER)));
      await assertFails(getDoc(referenceRef(db('outsider'), P_ADMIN)));
      await assertFails(getDoc(workRef(db('outsider'), P_MEMBER, people.member.email)));
    });
  });

  describe('reviewing a working', () => {
    test('a member reviews a peer\'s working after submitting their own: the review and its count go together', async () => {
      await assertSucceeds(reviewBatch('member', P_REVIEW, people.other.email, 'right'));
    });

    test('a review alone, without its count, is refused', async () => {
      await assertFails(setDoc(reviewRef(db('member'), P_REVIEW, people.other.email, people.member.email), {
        verdict: 'right',
        createdAt: serverTimestamp(),
      }));
    });

    test('a count moved alone, without a review, is refused', async () => {
      await assertFails(updateDoc(workRef(db('member'), P_REVIEW, people.other.email), { rightCount: increment(1) }));
    });

    test('a member does not review their own working', async () => {
      await assertFails(reviewBatch('member', P_REVIEW, people.member.email, 'right'));
    });

    test('a member without a working of their own cannot review a peer\'s', async () => {
      await assertFails(reviewBatch('member', P_ADMIN, people.other.email, 'right'));
    });

    test('the count moved must match the verdict', async () => {
      const f = db('member');
      const batch = writeBatch(f);
      batch.set(reviewRef(f, P_REVIEW, people.other.email, people.member.email), {
        verdict: 'right',
        createdAt: serverTimestamp(),
      });
      batch.update(workRef(f, P_REVIEW, people.other.email), { gapCount: increment(1) });
      await assertFails(batch.commit());
    });

    test('a note is at most 300 characters, and the verdict is right or gap', async () => {
      await assertFails(reviewBatch('member', P_REVIEW, people.other.email, 'right', SUBJECT, { note: 'x'.repeat(301) }));
      await assertFails(reviewBatch('member', P_REVIEW, people.other.email, 'maybe'));
      await assertSucceeds(reviewBatch('member', P_REVIEW, people.other.email, 'gap', SUBJECT, { note: 'x'.repeat(300) }));
    });

    test('a member reviews a working once: a second review is refused', async () => {
      await assertFails(reviewBatch('member', P_MEMBER, people.other.email, 'right'));
    });

    test('a member takes their own review back, and the count falls with it', async () => {
      await assertSucceeds(withdrawBatch('member', P_MEMBER, people.other.email, 'gap'));
    });

    test('a review goes without its count falling, or the count falls without the review going, is refused', async () => {
      await assertFails(deleteDoc(reviewRef(db('member'), P_MEMBER, people.other.email, people.member.email)));
      await assertFails(updateDoc(workRef(db('member'), P_MEMBER, people.other.email), { gapCount: increment(-1) }));
    });

    test('a withdrawal with the wrong count is refused', async () => {
      await assertFails(withdrawBatch('member', P_MEMBER, people.other.email, 'right'));
    });

    test('no member takes away another member\'s review', async () => {
      await assertFails(deleteDoc(reviewRef(db('other'), P_MEMBER, people.other.email, people.member.email)));
    });
  });

  describe('an admin reviewing a working', () => {
    test('an admin reviews a member\'s working without having submitted one: the review and its count go together', async () => {
      await assertSucceeds(reviewBatch('admin', P_REVIEW, people.other.email, 'right'));
      await assertSucceeds(reviewBatch('admin', P_REVIEW, people.member.email, 'gap'));
    });

    test('an admin does not review their own working', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(workRef(ctx.firestore(), P_REVIEW, people.admin.email), work({ text: 'The admin\'s own working.' }));
      });
      await assertFails(reviewBatch('admin', P_REVIEW, people.admin.email, 'right'));
    });

    // Removing a review is the reviewer's own act for now. The working's count must fall in the same batch, and the
    // working's update rule can only check the signed-in member's review, so an admin's removal is refused until that
    // rule has a design. See the PR notes.
    test('an admin cannot remove a member\'s review, even with the count falling in the same batch', async () => {
      const f = db('admin');
      await assertFails(deleteDoc(reviewRef(f, P_MEMBER, people.other.email, people.member.email)));
      const batch = writeBatch(f);
      batch.delete(reviewRef(f, P_MEMBER, people.other.email, people.member.email));
      batch.update(workRef(f, P_MEMBER, people.other.email), { gapCount: increment(-1) });
      await assertFails(batch.commit());
    });
  });

  describe('deleting a problem', () => {
    test('the author deletes their problem; another member does not; an admin does', async () => {
      await assertSucceeds(deleteDoc(problemRef(db('member'), P_MEMBER)));
      await assertFails(deleteDoc(problemRef(db('other'), P_ADMIN)));
      await assertSucceeds(deleteDoc(problemRef(db('admin'), P_ADMIN)));
    });
  });
});
