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
  deleteField,
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

  describe('reporting a problem and a working', () => {
    const problemReportRef = (f, problemId, reporterEmail, subjectId = SUBJECT) =>
      doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', problemId, 'reports', reporterEmail);
    const workReportRef = (f, problemId, solverEmail, reporterEmail, subjectId = SUBJECT) =>
      doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problems', problemId, 'solutions', solverEmail, 'reports', reporterEmail);

    // A member reports a problem. The report and the hiding of the problem are written in one batch. Only the
    // first report sets the report time.
    const reportProblemBatch = (who, problemId, { reason = 'unclear', first = true } = {}) => {
      const f = db(who);
      const batch = writeBatch(f);
      batch.set(problemReportRef(f, problemId, people[who].email), { reason, createdAt: serverTimestamp() });
      batch.update(problemRef(f, problemId), {
        shown: false,
        reportCount: increment(1),
        ...(first ? { reportedAt: serverTimestamp() } : {}),
      });
      return batch.commit();
    };

    // A member reports a working. The report and the hiding of the working are written in one batch.
    const reportWorkBatch = (who, problemId, solverEmail, { reason = 'wrong', first = true } = {}) => {
      const f = db(who);
      const batch = writeBatch(f);
      batch.set(workReportRef(f, problemId, solverEmail, people[who].email), { reason, createdAt: serverTimestamp() });
      batch.update(workRef(f, problemId, solverEmail), {
        reportCount: increment(1),
        ...(first ? { reportedAt: serverTimestamp() } : {}),
      });
      return batch.commit();
    };

    test('a member reports a shown problem by someone else, and the report and the hiding go together', async () => {
      await assertSucceeds(reportProblemBatch('member', P_ADMIN));
    });

    test('a member cannot report their own problem, nor one an admin has not shown', async () => {
      await assertFails(reportProblemBatch('member', P_MEMBER));
      await assertFails(reportProblemBatch('other', P_WAITING));
    });

    test('a report alone, or a hiding alone, is refused', async () => {
      await assertFails(setDoc(problemReportRef(db('other'), P_ADMIN, people.other.email), {
        reason: 'spam',
        createdAt: serverTimestamp(),
      }));
      await assertFails(updateDoc(problemRef(db('other'), P_ADMIN), { reportCount: increment(1) }));
      await assertFails(updateDoc(problemRef(db('other'), P_ADMIN), {
        shown: false,
        reportCount: increment(1),
        reportedAt: serverTimestamp(),
      }));
    });

    test('the count must rise by one with the report, and the reason must be one the app knows', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(problemReportRef(f, P_ADMIN, people.other.email), { reason: 'spam', createdAt: serverTimestamp() });
      batch.update(problemRef(f, P_ADMIN), { shown: false, reportCount: increment(2), reportedAt: serverTimestamp() });
      await assertFails(batch.commit());
      await assertFails(reportProblemBatch('other', P_ADMIN, { reason: 'rude' }));
    });

    test('a member reports a problem once: a second report is refused', async () => {
      await assertSucceeds(reportProblemBatch('other', P_ADMIN));
      await assertFails(reportProblemBatch('member', P_ADMIN, { first: false }));
    });

    test('the reporter and an admin read the reports on a problem; another member does not', async () => {
      await assertSucceeds(reportProblemBatch('other', P_ADMIN));
      await assertSucceeds(getDoc(problemReportRef(db('other'), P_ADMIN, people.other.email)));
      await assertSucceeds(getDoc(problemReportRef(db('admin'), P_ADMIN, people.other.email)));
      await assertFails(getDoc(problemReportRef(db('member'), P_ADMIN, people.other.email)));
    });

    test('an admin restores a reported problem: it is shown again and its report time is cleared', async () => {
      await assertSucceeds(reportProblemBatch('other', P_ADMIN));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_ADMIN), { shown: true, reportedAt: deleteField() }));
    });

    test('a member cannot restore a reported problem', async () => {
      await assertSucceeds(reportProblemBatch('other', P_ADMIN));
      await assertFails(updateDoc(problemRef(db('other'), P_ADMIN), { shown: true, reportedAt: deleteField() }));
      await assertFails(updateDoc(problemRef(db('member'), P_ADMIN), { shown: true, reportedAt: deleteField() }));
    });

    test('a problem reported again after a restore starts a new report time', async () => {
      await assertSucceeds(reportProblemBatch('other', P_ADMIN));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_ADMIN), { shown: true, reportedAt: deleteField() }));
      await assertSucceeds(reportProblemBatch('member', P_ADMIN));
    });

    test('a new problem or working cannot be written with reports already counted', async () => {
      await assertFails(setDoc(problemRef(db('member'), 'pr-reported'), newProblem(people.member.email, {
        reportCount: 1,
        reportedAt: serverTimestamp(),
      })));
      await assertFails(setDoc(workRef(db('member'), P_NOREF, people.member.email), newWork({ reportCount: 1 })));
    });

    test('a member who has submitted their own working reports a peer\'s: the working is hidden and the report goes with it', async () => {
      await assertSucceeds(reportWorkBatch('member', P_REVIEW, people.other.email));
    });

    test('a member without a working of their own cannot report a peer\'s, and nobody reports their own', async () => {
      await assertFails(reportWorkBatch('member', P_ADMIN, people.other.email));
      await assertFails(reportWorkBatch('member', P_MEMBER, people.member.email));
    });

    test('a working report alone, without hiding the working, is refused', async () => {
      await assertFails(setDoc(workReportRef(db('member'), P_REVIEW, people.other.email, people.member.email), {
        reason: 'wrong',
        createdAt: serverTimestamp(),
      }));
      await assertFails(updateDoc(workRef(db('member'), P_REVIEW, people.other.email), { reportCount: increment(1) }));
    });

    test('a reported working takes no reviews from members, and an admin may still review it', async () => {
      // A control first: on a working that is not reported, the same member's review goes through. So the refusal
      // below is the report's doing, and not the rules' expression limit.
      await assertSucceeds(setDoc(workRef(db('other'), P_NOREF, people.other.email), newWork()));
      await assertSucceeds(setDoc(workRef(db('member'), P_NOREF, people.member.email), newWork()));
      await assertSucceeds(reviewBatch('member', P_NOREF, people.other.email, 'right'));
      // The owner is an admin-level member, so may report a peer's working without one of their own.
      await assertSucceeds(reportWorkBatch('owner', P_REVIEW, people.other.email));
      await assertFails(reviewBatch('member', P_REVIEW, people.other.email, 'right'));
      await assertSucceeds(reviewBatch('admin', P_REVIEW, people.other.email, 'right'));
    });

    test('the reporter and an admin read the reports on a working; its author does not', async () => {
      await assertSucceeds(reportWorkBatch('member', P_REVIEW, people.other.email));
      await assertSucceeds(getDoc(workReportRef(db('member'), P_REVIEW, people.other.email, people.member.email)));
      await assertSucceeds(getDoc(workReportRef(db('admin'), P_REVIEW, people.other.email, people.member.email)));
      await assertFails(getDoc(workReportRef(db('other'), P_REVIEW, people.other.email, people.member.email)));
    });

    test('an admin restores a reported working, and its report time is cleared', async () => {
      await assertSucceeds(reportWorkBatch('member', P_REVIEW, people.other.email));
      await assertSucceeds(updateDoc(workRef(db('admin'), P_REVIEW, people.other.email), { reportedAt: deleteField() }));
    });

    test('a member cannot clear the report on a working', async () => {
      await assertSucceeds(reportWorkBatch('member', P_REVIEW, people.other.email));
      await assertFails(updateDoc(workRef(db('member'), P_REVIEW, people.other.email), { reportedAt: deleteField() }));
    });

    test('the author of a reported working may still edit its words', async () => {
      await assertSucceeds(reportWorkBatch('member', P_REVIEW, people.other.email));
      await assertSucceeds(updateDoc(workRef(db('other'), P_REVIEW, people.other.email), {
        text: 'Revised after the report.',
        updatedAt: serverTimestamp(),
      }));
    });

    test('an admin removes a reported working; a member cannot', async () => {
      await assertSucceeds(reportWorkBatch('member', P_REVIEW, people.other.email));
      await assertFails(deleteDoc(workRef(db('member'), P_REVIEW, people.other.email)));
      await assertSucceeds(deleteDoc(workRef(db('admin'), P_REVIEW, people.other.email)));
    });
  });

  describe('problem sets', () => {
    const SET_ONE = 'set-one';
    const setRef = (f, setId, subjectId = SUBJECT) =>
      doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'problem_sets', setId);
    const DUE = Timestamp.fromDate(new Date('2026-11-20T00:00:00Z'));

    // A set as an admin writes it: a name, a due day, and the server's times.
    const newSet = (by, extra = {}) => ({
      title: 'Week one',
      dueAt: DUE,
      createdByEmail: by,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...extra,
    });
    // A set with no due date.
    const undatedSet = (by, extra = {}) => {
      const set = newSet(by, extra);
      delete set.dueAt;
      return set;
    };

    test('an admin makes a set under their own email, with a due date or without one', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertSucceeds(setDoc(setRef(db('admin'), 'set-undated'), undatedSet(people.admin.email)));
      await assertFails(setDoc(setRef(db('admin'), 'set-other'), newSet(people.owner.email)));
    });

    test('a member cannot make, rename or delete a set', async () => {
      await assertFails(setDoc(setRef(db('member'), 'set-member'), newSet(people.member.email)));
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertFails(updateDoc(setRef(db('member'), SET_ONE), { title: 'Renamed', updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(setRef(db('member'), SET_ONE)));
    });

    test('a set has a name of 1 to 120 characters, and a due date only as a time', async () => {
      await assertFails(setDoc(setRef(db('admin'), 'bad-empty'), newSet(people.admin.email, { title: '' })));
      await assertFails(setDoc(setRef(db('admin'), 'bad-long'), newSet(people.admin.email, { title: 'x'.repeat(121) })));
      await assertFails(setDoc(setRef(db('admin'), 'bad-due'), newSet(people.admin.email, { dueAt: '2026-11-20' })));
      await assertSucceeds(setDoc(setRef(db('admin'), 'ok-long'), newSet(people.admin.email, { title: 'x'.repeat(120) })));
    });

    test('a set is refused in a subject that is not listed, and in one whose problems module is off', async () => {
      await assertFails(setDoc(setRef(db('admin'), SET_ONE, PROPOSED), newSet(people.admin.email)));
      await assertFails(setDoc(setRef(db('admin'), SET_ONE, OFF), newSet(people.admin.email)));
    });

    test('members read the sets of their group, and an outsider reads none', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertSucceeds(getDoc(setRef(db('member'), SET_ONE)));
      await assertFails(getDoc(setRef(db('outsider'), SET_ONE)));
    });

    test('an admin renames a set, and cannot change its creator, nor save it without a new update time', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertSucceeds(updateDoc(setRef(db('admin'), SET_ONE), { title: 'Week two', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(setRef(db('admin'), SET_ONE), { title: 'Week three' }));
      await assertFails(updateDoc(setRef(db('admin'), SET_ONE), {
        createdByEmail: people.owner.email,
        updatedAt: serverTimestamp(),
      }));
    });

    test('an admin puts a problem into a set that exists, and never into one that does not', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_ADMIN), { setId: SET_ONE }));
      await assertFails(updateDoc(problemRef(db('admin'), P_NOREF), { setId: 'no-such-set' }));
      await assertFails(updateDoc(problemRef(db('admin'), P_NOREF), { setId: 'x'.repeat(41) }));
    });

    test('a member cannot put a problem into a set, and cannot post a problem already in one', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertFails(updateDoc(problemRef(db('member'), P_MEMBER), { setId: SET_ONE }));
      await assertFails(setDoc(problemRef(db('member'), 'pr-in-set'), newProblem(people.member.email, { setId: SET_ONE })));
    });

    test('an admin takes a problem out of its set', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_ADMIN), { setId: SET_ONE }));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_ADMIN), { setId: deleteField() }));
    });

    test('an admin deletes a set and clears its problems in one batch', async () => {
      await assertSucceeds(setDoc(setRef(db('admin'), SET_ONE), newSet(people.admin.email)));
      await assertSucceeds(updateDoc(problemRef(db('admin'), P_ADMIN), { setId: SET_ONE }));
      const f = db('admin');
      const batch = writeBatch(f);
      batch.update(problemRef(f, P_ADMIN), { setId: deleteField() });
      batch.delete(setRef(f, SET_ONE));
      await assertSucceeds(batch.commit());
    });
  });
});
