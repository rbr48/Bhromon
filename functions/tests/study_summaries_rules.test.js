// The revisions of a chapter summary, and the revision an admin pins on the chapter. Runs against the Firestore
// emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_summaries_rules"
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
  deleteField,
  serverTimestamp,
  Timestamp,
  writeBatch,
  increment,
} = require('firebase/firestore');

// Starting the emulator and loading the rules can take longer than Jest's default five-second hook timeout.
jest.setTimeout(120000);

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'summarygroup';
const BOOK = 'b1';
const CHAPTER = 'ch1';
const REVISION = 'rev1';
const people = {
  owner: { uid: 'sgowner', email: 'sgowner@x.com' },
  admin: { uid: 'sgadmin', email: 'sgadmin@x.com' },
  member: { uid: 'sgmem', email: 'sgmem@x.com' },
  outsider: { uid: 'sgeve', email: 'sgeve@x.com' },
};

const created = () => Timestamp.fromDate(new Date('2026-11-02T09:00:00Z'));

const bookRef = (f, id = BOOK) => doc(f, 'tours', STUDY, 'study_books', id);
const chapterRef = (f, id = CHAPTER) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'chapters', id);
const revisionRef = (f, id, chapterId = CHAPTER) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'chapters', chapterId, 'summaries', id);

const chapterFields = (extra = {}) => ({
  number: 1,
  title: 'Chapter one',
  pageFrom: null,
  pageTo: null,
  dueOn: null,
  guide: [],
  ...extra,
});

const reportRef = (f, id, email, chapterId = CHAPTER) =>
  doc(f, 'tours', STUDY, 'study_books', BOOK, 'chapters', chapterId, 'summaries', id, 'reports', email);

// A new revision is shown and has no reports, as firestore.rules requires of a create.
const revisionFields = (by, extra = {}) => ({
  text: 'Anna and Vronsky meet at the station.',
  editorEmail: by,
  editorName: 'Name',
  createdAt: serverTimestamp(),
  hidden: false,
  reportCount: 0,
  ...extra,
});

describe('chapter summaries: revisions and the pinned revision', () => {
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
        inviteCode: 'SUMMARY001',
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
      await setDoc(bookRef(f), {
        title: 'Anna Karenina',
        author: null,
        notes: null,
        status: 'toRead',
        statusByEmail: null,
        createdByEmail: people.admin.email,
        approval: 'listed',
        declineNote: null,
      });
      await setDoc(chapterRef(f), chapterFields());
      await setDoc(revisionRef(f, REVISION), {
        text: 'The first summary.',
        editorEmail: people.admin.email,
        editorName: 'Admin',
        createdAt: created(),
      });
    });
  });

  describe('adding a revision', () => {
    test('a member adds a revision in their own name', async () => {
      await assertSucceeds(
        setDoc(revisionRef(db('member'), 'rev2'), revisionFields(people.member.email)),
      );
    });

    test('a member cannot add a revision in someone else’s name', async () => {
      await assertFails(
        setDoc(revisionRef(db('member'), 'rev3'), revisionFields(people.admin.email)),
      );
    });

    test('the time of a revision is the server time, not one the client sets', async () => {
      await assertFails(
        setDoc(
          revisionRef(db('member'), 'rev4'),
          revisionFields(people.member.email, {
            createdAt: Timestamp.fromDate(new Date('2026-11-01T00:00:00Z')),
          }),
        ),
      );
    });

    test('a revision holds up to 4,000 characters and no more', async () => {
      await assertSucceeds(
        setDoc(
          revisionRef(db('member'), 'rev5'),
          revisionFields(people.member.email, { text: 'x'.repeat(4000) }),
        ),
      );
      await assertFails(
        setDoc(
          revisionRef(db('member'), 'rev6'),
          revisionFields(people.member.email, { text: 'x'.repeat(4001) }),
        ),
      );
    });

    test('a restore is a new revision that names the one it restores', async () => {
      await assertSucceeds(
        setDoc(
          revisionRef(db('member'), 'rev7'),
          revisionFields(people.member.email, {
            text: 'The first summary.',
            restoredFromId: REVISION,
          }),
        ),
      );
      await assertFails(
        setDoc(
          revisionRef(db('member'), 'rev8'),
          revisionFields(people.member.email, { restoredFromId: 42 }),
        ),
      );
    });
  });

  describe('keeping revisions', () => {
    test('the words of a revision are never changed, by anyone and even when an admin hides it', async () => {
      await assertFails(updateDoc(revisionRef(db('admin'), REVISION), { text: 'Changed' }));
      await assertFails(updateDoc(revisionRef(db('member'), REVISION), { text: 'Changed' }));
      await assertFails(updateDoc(revisionRef(db('admin'), REVISION), { hidden: true, text: 'Changed' }));
    });

    test('only an admin removes a revision', async () => {
      await assertFails(deleteDoc(revisionRef(db('member'), REVISION)));
      await assertSucceeds(deleteDoc(revisionRef(db('admin'), REVISION)));
    });

    test('a member reads the revisions; an outsider does not', async () => {
      await assertSucceeds(getDoc(revisionRef(db('member'), REVISION)));
      await assertFails(getDoc(revisionRef(db('outsider'), REVISION)));
    });
  });

  describe('reporting and hiding a revision', () => {
    // A member reports a revision: the report, the count and the first report time move in one batch.
    const reportBatch = (who, id, { firstReport = true, count = 1 } = {}) => {
      const f = db(who);
      const batch = writeBatch(f);
      batch.set(reportRef(f, id, people[who].email), { reason: 'wrong', createdAt: serverTimestamp() });
      batch.update(revisionRef(f, id), {
        reportCount: increment(count),
        ...(firstReport ? { reportedAt: serverTimestamp() } : {}),
      });
      return batch.commit();
    };

    // The stored revision, read with the rules off, since the rules are checked on the other calls.
    const stored = async (id) => {
      let data;
      await env.withSecurityRulesDisabled(async (ctx) => {
        data = (await getDoc(revisionRef(ctx.firestore(), id))).data();
      });
      return data;
    };

    test('a member reports another member’s revision: it is counted and its first report time is set', async () => {
      await assertSucceeds(reportBatch('member', REVISION));
      const data = await stored(REVISION);
      expect(data.reportCount).toBe(1);
      expect(data.reportedAt).toBeTruthy();
    });

    test('a second report moves only the count, and keeps the first report time', async () => {
      await assertSucceeds(reportBatch('member', REVISION));
      const first = (await stored(REVISION)).reportedAt;
      await assertSucceeds(reportBatch('owner', REVISION, { firstReport: false }));
      const data = await stored(REVISION);
      expect(data.reportCount).toBe(2);
      expect(data.reportedAt.isEqual(first)).toBe(true);
    });

    test('a member cannot report their own revision', async () => {
      await assertSucceeds(setDoc(revisionRef(db('member'), 'mine'), revisionFields(people.member.email)));
      await assertFails(reportBatch('member', 'mine'));
    });

    test('a report moves the count by exactly one, and a report alone is refused', async () => {
      await assertFails(reportBatch('member', REVISION, { count: 2 }));
      await assertFails(setDoc(reportRef(db('member'), REVISION, people.member.email), {
        reason: 'wrong',
        createdAt: serverTimestamp(),
      }));
    });

    test('a new revision cannot start hidden or already reported', async () => {
      await assertFails(setDoc(revisionRef(db('member'), 'h1'), revisionFields(people.member.email, { hidden: true })));
      await assertFails(setDoc(revisionRef(db('member'), 'h2'), revisionFields(people.member.email, { reportCount: 1 })));
    });

    test('an admin hides a revision, and shows it again, which clears its report time', async () => {
      await assertSucceeds(reportBatch('member', REVISION));
      await assertSucceeds(updateDoc(revisionRef(db('admin'), REVISION), { hidden: true }));
      expect((await stored(REVISION)).hidden).toBe(true);
      await assertSucceeds(updateDoc(revisionRef(db('admin'), REVISION), { hidden: false, reportedAt: deleteField() }));
      const data = await stored(REVISION);
      expect(data.hidden).toBe(false);
      expect(data.reportedAt).toBeUndefined();
    });

    test('a member cannot hide or show a revision', async () => {
      await assertFails(updateDoc(revisionRef(db('member'), REVISION), { hidden: true }));
    });

    test('the reporter and the admins read a report; another member does not', async () => {
      await assertSucceeds(reportBatch('owner', REVISION));
      await assertSucceeds(getDoc(reportRef(db('owner'), REVISION, people.owner.email)));
      await assertSucceeds(getDoc(reportRef(db('admin'), REVISION, people.owner.email)));
      await assertFails(getDoc(reportRef(db('member'), REVISION, people.owner.email)));
    });
  });

  describe('the pinned revision', () => {
    test('an admin pins a revision on the chapter, and unpins it', async () => {
      await assertSucceeds(updateDoc(chapterRef(db('admin')), { pinnedSummaryId: REVISION }));
      await assertSucceeds(updateDoc(chapterRef(db('admin')), { pinnedSummaryId: deleteField() }));
    });

    test('a member cannot pin a revision', async () => {
      await assertFails(updateDoc(chapterRef(db('member')), { pinnedSummaryId: REVISION }));
    });

    test('a pin is a short revision id, not some other value', async () => {
      await assertFails(updateDoc(chapterRef(db('admin')), { pinnedSummaryId: 42 }));
      await assertFails(updateDoc(chapterRef(db('admin')), { pinnedSummaryId: 'x'.repeat(41) }));
    });
  });
});
