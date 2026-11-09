// A study group's materials: notes, files, links and recordings filed under a book, approved by an admin
// unless the group publishes directly, reported and hidden, and opened once per member. Runs against the
// Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_materials_rules"
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

// Starting the emulator and loading the rules can take longer than Jest's default five seconds.
jest.setTimeout(60000);

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'materialclub';
const BOOK = 'b1';
const PROPOSAL = 'p1';
const PUBLISHED = 'm1';
const PENDING = 'm2';
const HIDDEN = 'm3';
const OTHERS = 'm4';
const FILE_HEX = 'a'.repeat(32);
const people = {
  owner: { uid: 'mtowner', email: 'mtowner@x.com' },
  admin: { uid: 'mtadmin', email: 'mtadmin@x.com' },
  member: { uid: 'mtmem', email: 'mtmem@x.com' },
  other: { uid: 'mtother', email: 'mtother@x.com' },
  outsider: { uid: 'mteve', email: 'mteve@x.com' },
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

// A link material as the app writes it. The server time is set per write.
const linkFields = (by, extra = {}) => ({
  title: 'Chapter 1 notes',
  kind: 'link',
  bookId: BOOK,
  chapterId: null,
  url: 'https://example.com/notes',
  status: 'pending',
  rightsConfirmed: true,
  reportCount: 0,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-02T09:00:00Z')),
  ...extra,
});

const fileFields = (by, extra = {}) => ({
  title: 'Summary of chapter 2',
  kind: 'file',
  bookId: BOOK,
  chapterId: null,
  url: `https://bhromon.fun/media/${STUDY}/study/${FILE_HEX}.pdf`,
  sizeBytes: 2 * 1024 * 1024,
  status: 'pending',
  rightsConfirmed: true,
  reportCount: 0,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-02T09:00:00Z')),
  ...extra,
});

const noteFields = (by, extra = {}) => ({
  title: 'My summary',
  kind: 'note',
  bookId: BOOK,
  chapterId: null,
  body: 'Anna meets Vronsky at the station.',
  status: 'published',
  rightsConfirmed: true,
  reportCount: 0,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-02T09:00:00Z')),
  ...extra,
});

const materialRef = (f, id = PUBLISHED) => doc(f, 'tours', STUDY, 'study_materials', id);
const reportRef = (f, materialId, email) =>
  doc(f, 'tours', STUDY, 'study_materials', materialId, 'reports', email);
const openRef = (f, materialId, email) =>
  doc(f, 'tours', STUDY, 'study_materials', materialId, 'opens', email);
const tourRef = (f) => doc(f, 'tours', STUDY);
const bookRef = (f, id = BOOK) => doc(f, 'tours', STUDY, 'study_books', id);

describe('study materials: filing, approval, rights, reports, opens and removal', () => {
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
      await setDoc(tourRef(f), {
        name: 'Reading group',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'MATER0001',
      });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${STUDY}__${email}`), { tourId: STUDY, email, role, status: 'active', displayName: email });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      await setDoc(bookRef(f, BOOK), bookFields(people.admin.email));
      await setDoc(bookRef(f, PROPOSAL), bookFields(people.member.email, { approval: 'proposed' }));
      await setDoc(materialRef(f, PUBLISHED), noteFields(people.member.email));
      await setDoc(materialRef(f, PENDING), linkFields(people.member.email));
      await setDoc(
        materialRef(f, HIDDEN),
        noteFields(people.member.email, {
          status: 'hidden',
          reportCount: 1,
          reportedAt: Timestamp.fromDate(new Date('2026-11-02T10:00:00Z')),
        }),
      );
      await setDoc(materialRef(f, OTHERS), noteFields(people.other.email));
    });
  });

  describe('filing a material', () => {
    test('a member files a link as pending under their own email', async () => {
      await assertSucceeds(setDoc(materialRef(db('other'), 'new1'), { ...linkFields(people.other.email), createdAt: serverTimestamp() }));
    });

    test('a member cannot file under someone else\'s email', async () => {
      await assertFails(setDoc(materialRef(db('other'), 'new2'), { ...linkFields(people.member.email), createdAt: serverTimestamp() }));
    });

    test('a member cannot publish a material when the group approves them first', async () => {
      await assertFails(setDoc(materialRef(db('other'), 'new3'), { ...linkFields(people.other.email, { status: 'published' }), createdAt: serverTimestamp() }));
    });

    test('an admin files a material as published at once', async () => {
      await assertSucceeds(setDoc(materialRef(db('admin'), 'new4'), { ...linkFields(people.admin.email, { status: 'published' }), createdAt: serverTimestamp() }));
    });

    test('a group that publishes directly lets a member publish at once', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(tourRef(ctx.firestore()), { studyPolicy: { materialsNeedApproval: false } }, { merge: true });
      });
      await assertSucceeds(setDoc(materialRef(db('other'), 'new5'), { ...linkFields(people.other.email, { status: 'published' }), createdAt: serverTimestamp() }));
    });

    test('a material is filed under a listed book only', async () => {
      await assertFails(setDoc(materialRef(db('other'), 'new6'), { ...linkFields(people.other.email, { bookId: PROPOSAL }), createdAt: serverTimestamp() }));
    });

    test('rights must be confirmed', async () => {
      await assertFails(setDoc(materialRef(db('other'), 'new7'), { ...linkFields(people.other.email, { rightsConfirmed: false }), createdAt: serverTimestamp() }));
    });

    test('a material starts with no reports and the server time', async () => {
      await assertFails(setDoc(materialRef(db('other'), 'new8'), { ...linkFields(people.other.email), createdAt: serverTimestamp(), reportCount: 1 }));
      await assertFails(setDoc(materialRef(db('other'), 'new9'), { ...linkFields(people.other.email), createdAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')) }));
    });

    test('a link is an http or https address of at most 2000 characters', async () => {
      await assertFails(setDoc(materialRef(db('other'), 'new10'), { ...linkFields(people.other.email, { url: 'ftp://example.com/x' }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'new11'), { ...linkFields(people.other.email, { url: `https://example.com/${'x'.repeat(2000)}` }), createdAt: serverTimestamp() }));
      await assertSucceeds(setDoc(materialRef(db('other'), 'new12'), { ...linkFields(people.other.email, { url: 'http://example.com/x' }), createdAt: serverTimestamp() }));
    });

    test('a file is stored in this group\'s study folder, with an extension and size of its kind', async () => {
      await assertSucceeds(setDoc(materialRef(db('other'), 'f1'), { ...fileFields(people.other.email), createdAt: serverTimestamp() }));
      // Another group\'s folder, another folder, or a kind\'s extension it does not have.
      await assertFails(setDoc(materialRef(db('other'), 'f2'), { ...fileFields(people.other.email, { url: `https://bhromon.fun/media/someoneelse/study/${FILE_HEX}.pdf` }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'f3'), { ...fileFields(people.other.email, { url: `https://bhromon.fun/media/${STUDY}/posts/${FILE_HEX}.pdf` }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'f4'), { ...fileFields(people.other.email, { url: `https://bhromon.fun/media/${STUDY}/study/${FILE_HEX}.exe` }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'f5'), { ...fileFields(people.other.email, { kind: 'image' }), createdAt: serverTimestamp() }));
    });

    test('a file is at most its kind\'s limit: 10 MB images, 25 MB audio, 100 MB video, 50 MB files', async () => {
      const mb = 1024 * 1024;
      await assertSucceeds(setDoc(materialRef(db('other'), 'g1'), { ...fileFields(people.other.email, { kind: 'file', sizeBytes: 50 * mb }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'g2'), { ...fileFields(people.other.email, { kind: 'file', sizeBytes: 50 * mb + 1 }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'g3'), { ...fileFields(people.other.email, { kind: 'image', url: `https://bhromon.fun/media/${STUDY}/study/${FILE_HEX}.jpg`, sizeBytes: 10 * mb + 1 }), createdAt: serverTimestamp() }));
      await assertSucceeds(setDoc(materialRef(db('other'), 'g4'), { ...fileFields(people.other.email, { kind: 'video', url: `https://bhromon.fun/media/${STUDY}/study/${FILE_HEX}.mp4`, sizeBytes: 100 * mb }), createdAt: serverTimestamp() }));
      await assertFails(setDoc(materialRef(db('other'), 'g5'), { ...fileFields(people.other.email, { kind: 'audio', url: `https://bhromon.fun/media/${STUDY}/study/${FILE_HEX}.mp3`, sizeBytes: 25 * mb + 1 }), createdAt: serverTimestamp() }));
    });

    test('a note is text of 1 to 20000 characters, with no file', async () => {
      await assertSucceeds(setDoc(materialRef(db('other'), 'n1'), { ...noteFields(people.other.email, { status: 'pending' }), createdAt: serverTimestamp(), body: 'x'.repeat(20000) }));
      await assertFails(setDoc(materialRef(db('other'), 'n2'), { ...noteFields(people.other.email, { status: 'pending' }), createdAt: serverTimestamp(), body: 'x'.repeat(20001) }));
      await assertFails(setDoc(materialRef(db('other'), 'n3'), { ...noteFields(people.other.email, { status: 'pending' }), createdAt: serverTimestamp(), url: 'https://example.com/x' }));
    });
  });

  describe('approval and editing', () => {
    test('the uploader edits the title of their own pending material', async () => {
      await assertSucceeds(updateDoc(materialRef(db('member'), PENDING), { title: 'Chapter 1 notes, revised' }));
    });

    test('another member cannot edit someone else\'s title', async () => {
      await assertFails(updateDoc(materialRef(db('other'), PENDING), { title: 'Mine now' }));
      await assertFails(updateDoc(materialRef(db('other'), PUBLISHED), { title: 'Mine now' }));
    });

    test('the uploader cannot publish their own pending material', async () => {
      await assertFails(updateDoc(materialRef(db('member'), PENDING), { status: 'published' }));
    });

    test('an admin publishes a pending material and restores a hidden one', async () => {
      await assertSucceeds(updateDoc(materialRef(db('admin'), PENDING), { status: 'published' }));
      await assertSucceeds(updateDoc(materialRef(db('admin'), HIDDEN), { status: 'published' }));
    });

    test('a material\'s book, kind, address and author do not change after filing', async () => {
      await assertFails(updateDoc(materialRef(db('admin'), PENDING), { url: 'https://example.com/other' }));
      await assertFails(updateDoc(materialRef(db('admin'), PENDING), { kind: 'note', body: 'x', url: null }));
      await assertFails(updateDoc(materialRef(db('admin'), PENDING), { createdByEmail: people.admin.email }));
    });
  });

  describe('reports', () => {
    // A member reports a material: the report, the count and the hiding change in one batch.
    const report = (who, materialId, { reason = 'copyright', first = true } = {}) => {
      const f = db(who);
      const batch = writeBatch(f);
      batch.set(reportRef(f, materialId, people[who].email), { reason, createdAt: serverTimestamp() });
      const change = { reportCount: increment(1), status: 'hidden' };
      if (first) change.reportedAt = serverTimestamp();
      batch.update(materialRef(f, materialId), change);
      return batch.commit();
    };

    test('a member reports a published material and it is hidden at once', async () => {
      await assertSucceeds(report('other', PUBLISHED));
      const snap = await getDoc(materialRef(db('admin'), PUBLISHED));
      expect(snap.data().status).toBe('hidden');
      expect(snap.data().reportCount).toBe(1);
    });

    test('a report that does not hide the material is refused', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(reportRef(f, PUBLISHED, people.other.email), { reason: 'wrong', createdAt: serverTimestamp() });
      batch.update(materialRef(f, PUBLISHED), { reportCount: increment(1) });
      await assertFails(batch.commit());
    });

    test('a report whose count does not rise by one is refused', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(reportRef(f, PUBLISHED, people.other.email), { reason: 'wrong', createdAt: serverTimestamp() });
      batch.update(materialRef(f, PUBLISHED), { status: 'hidden', reportCount: increment(2), reportedAt: serverTimestamp() });
      await assertFails(batch.commit());
    });

    test('the uploader cannot report their own material', async () => {
      await assertFails(report('member', PUBLISHED));
    });

    test('a pending material cannot be reported', async () => {
      await assertFails(report('other', PENDING));
    });

    test('a second report keeps the time of the first', async () => {
      await assertSucceeds(report('other', HIDDEN, { reason: 'personal', first: false }));
    });

    test('the reporter and an admin read a report; no other member does', async () => {
      await assertSucceeds(report('other', PUBLISHED));
      await assertSucceeds(getDoc(reportRef(db('other'), PUBLISHED, people.other.email)));
      await assertSucceeds(getDoc(reportRef(db('admin'), PUBLISHED, people.other.email)));
      await assertFails(getDoc(reportRef(db('member'), PUBLISHED, people.other.email)));
    });

    test('a reason is one of the listed reasons', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(reportRef(f, PUBLISHED, people.other.email), { reason: 'rude', createdAt: serverTimestamp() });
      batch.update(materialRef(f, PUBLISHED), { reportCount: increment(1), status: 'hidden', reportedAt: serverTimestamp() });
      await assertFails(batch.commit());
    });

    test('a hidden material is read by its uploader and an admin; the app hides it from other members', async () => {
      await assertSucceeds(getDoc(materialRef(db('member'), HIDDEN)));
      await assertSucceeds(getDoc(materialRef(db('admin'), HIDDEN)));
      // The rules cannot filter list reads, so a member can still read it by id. The app hides it.
      await assertSucceeds(getDoc(materialRef(db('other'), HIDDEN)));
    });
  });

  describe('opens', () => {
    test('a member marks a published material opened, once, for themselves', async () => {
      await assertSucceeds(setDoc(openRef(db('other'), PUBLISHED, people.other.email), { openedAt: serverTimestamp() }));
      await assertFails(setDoc(openRef(db('other'), PUBLISHED, people.member.email), { openedAt: serverTimestamp() }));
      await assertFails(updateDoc(openRef(db('other'), PUBLISHED, people.other.email), { openedAt: serverTimestamp() }));
    });

    test('a pending or hidden material is not marked opened', async () => {
      await assertFails(setDoc(openRef(db('other'), PENDING, people.other.email), { openedAt: serverTimestamp() }));
      await assertFails(setDoc(openRef(db('other'), HIDDEN, people.other.email), { openedAt: serverTimestamp() }));
    });

    test('a member reads only their own mark; an admin reads them all', async () => {
      await assertSucceeds(setDoc(openRef(db('other'), PUBLISHED, people.other.email), { openedAt: serverTimestamp() }));
      await assertSucceeds(getDoc(openRef(db('other'), PUBLISHED, people.other.email)));
      await assertFails(getDoc(openRef(db('member'), PUBLISHED, people.other.email)));
      await assertSucceeds(getDoc(openRef(db('admin'), PUBLISHED, people.other.email)));
    });
  });

  describe('removal', () => {
    test('the uploader removes their own material', async () => {
      await assertSucceeds(deleteDoc(materialRef(db('member'), PENDING)));
    });

    test('another member cannot remove it; an admin can', async () => {
      await assertFails(deleteDoc(materialRef(db('other'), PENDING)));
      await assertSucceeds(deleteDoc(materialRef(db('admin'), PENDING)));
    });

    test('an admin clears reports and opens, and no member can clear a report', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(reportRef(ctx.firestore(), HIDDEN, people.other.email), { reason: 'exam', createdAt: Timestamp.fromDate(new Date('2026-11-02T10:00:00Z')) });
      });
      await assertFails(deleteDoc(reportRef(db('other'), HIDDEN, people.other.email)));
      await assertFails(deleteDoc(reportRef(db('member'), HIDDEN, people.other.email)));
      await assertSucceeds(deleteDoc(reportRef(db('admin'), HIDDEN, people.other.email)));
    });
  });

  describe('the group\'s policy', () => {
    test('an admin sets whether materials wait for approval; a member does not', async () => {
      await assertSucceeds(updateDoc(tourRef(db('admin')), { studyPolicy: { materialsNeedApproval: false } }));
      await assertFails(updateDoc(tourRef(db('member')), { studyPolicy: { materialsNeedApproval: false } }));
    });

    test('the policy holds one boolean only', async () => {
      await assertFails(updateDoc(tourRef(db('admin')), { studyPolicy: { materialsNeedApproval: 'no' } }));
      await assertFails(updateDoc(tourRef(db('admin')), { studyPolicy: { materialsNeedApproval: false, onlyAdminsPost: true } }));
    });

    test('a group with no study preset has no policy', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'tours', 'plainclub'), {
          name: 'Trip',
          kind: 'tour',
          preset: null,
          ownerEmail: people.owner.email,
          ownerUid: people.owner.uid,
          inviteCode: 'PLAIN0001',
        });
      });
      const f = db('owner');
      await assertFails(updateDoc(doc(f, 'tours', 'plainclub'), { studyPolicy: { materialsNeedApproval: false } }));
    });
  });
});
