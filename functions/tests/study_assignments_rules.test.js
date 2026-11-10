// A study group's assignments: who may add one under a subject and under which post policy, who may change, show or
// remove one, and each member's own finished marks. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_assignments_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  where,
  setDoc,
  updateDoc,
  deleteDoc,
  arrayUnion,
  arrayRemove,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

jest.setTimeout(120000);

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'assignclub';
const SUBJECT = 'bio101';
const ADMIN_ITEM = 'lab-admin';
const MEMBER_ITEM = 'lab-member';
const WAITING = 'lab-waiting';
const OTHERS_WAITING = 'lab-others-waiting';
const people = {
  owner: { uid: 'asowner', email: 'asowner@x.com' },
  admin: { uid: 'asadmin', email: 'asadmin@x.com' },
  member: { uid: 'asmem', email: 'asmem@x.com' },
  other: { uid: 'asother', email: 'asother@x.com' },
  outsider: { uid: 'aseve', email: 'aseve@x.com' },
};

const subject = (by, extra = {}) => ({ title: 'Biology', code: null, approval: 'listed', declineNote: null, createdByEmail: by, archived: false, ...extra });
const moduleSettings = (extra = {}) => ({ enabled: true, name: 'Assignments', postPolicy: 'members', ...extra });

// An assignment as it was stored earlier: a fixed time, so the server-time rule does not apply.
const item = (by, extra = {}) => ({
  title: 'Lab report 3',
  details: null,
  url: null,
  dueAt: null,
  shown: true,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-01T10:00:00Z')),
  ...extra,
});
// An assignment added now: its time is the server's, as the rule requires.
const newItem = (by, extra = {}) => ({ ...item(by), createdAt: serverTimestamp(), ...extra });

const subjectRef = (f) => doc(f, 'tours', STUDY, 'study_subjects', SUBJECT);
const moduleRef = (f, key = 'assignments') => doc(f, 'tours', STUDY, 'study_subjects', SUBJECT, 'modules', key);
const itemRef = (f, id) => doc(f, 'tours', STUDY, 'study_subjects', SUBJECT, 'assignments', id);
const itemsCol = (f) => collection(f, 'tours', STUDY, 'study_subjects', SUBJECT, 'assignments');
const markRef = (f, email) => doc(f, 'tours', STUDY, 'study_subjects', SUBJECT, 'assignment_marks', email);

describe('assignments and their finished marks', () => {
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
        name: 'Study group',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'ASGN00001',
      });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${STUDY}__${email}`), { tourId: STUDY, email, role, status: 'active', displayName: email });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      await setDoc(subjectRef(f), subject(people.admin.email));
      await setDoc(moduleRef(f), moduleSettings());
      await setDoc(itemRef(f, ADMIN_ITEM), item(people.admin.email, { title: 'Lab report 1' }));
      await setDoc(itemRef(f, MEMBER_ITEM), item(people.member.email));
      await setDoc(itemRef(f, WAITING), item(people.member.email, { title: 'Lab report 4', shown: false }));
      await setDoc(itemRef(f, OTHERS_WAITING), item(people.other.email, { title: 'Lab report 5', shown: false }));
    });
  });

  describe('adding an assignment', () => {
    test('a member adds one under their own email, shown at once under the members policy', async () => {
      await assertSucceeds(setDoc(itemRef(db('member'), 'new1'), newItem(people.member.email)));
    });

    test('a member cannot add one under another member\'s email', async () => {
      await assertFails(setDoc(itemRef(db('member'), 'new2'), newItem(people.other.email)));
    });

    test('under the approval policy a member\'s one waits, and only an admin\'s is shown at once', async () => {
      await assertSucceeds(setDoc(moduleRef(db('admin')), moduleSettings({ postPolicy: 'approval' })));
      await assertFails(setDoc(itemRef(db('member'), 'new3'), newItem(people.member.email, { shown: true })));
      await assertSucceeds(setDoc(itemRef(db('member'), 'new4'), newItem(people.member.email, { shown: false })));
      await assertSucceeds(setDoc(itemRef(db('admin'), 'new5'), newItem(people.admin.email, { shown: true })));
    });

    test('under the admins policy only an admin adds one', async () => {
      await assertSucceeds(setDoc(moduleRef(db('admin')), moduleSettings({ postPolicy: 'admins' })));
      await assertFails(setDoc(itemRef(db('member'), 'new6'), newItem(people.member.email)));
      await assertSucceeds(setDoc(itemRef(db('admin'), 'new7'), newItem(people.admin.email)));
    });

    test('nothing is added while the module is off, by a member or an admin', async () => {
      await assertSucceeds(setDoc(moduleRef(db('admin')), moduleSettings({ enabled: false })));
      await assertFails(setDoc(itemRef(db('member'), 'new8'), newItem(people.member.email)));
      await assertFails(setDoc(itemRef(db('admin'), 'new9'), newItem(people.admin.email)));
    });

    test('nothing is added to an archived subject', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: true }));
      await assertFails(setDoc(itemRef(db('member'), 'new10'), newItem(people.member.email)));
    });

    test('a title is needed, and a link must be https', async () => {
      await assertFails(setDoc(itemRef(db('member'), 'new11'), newItem(people.member.email, { title: '' })));
      await assertFails(setDoc(itemRef(db('member'), 'new12'), newItem(people.member.email, { url: 'http://x.org/brief' })));
      await assertSucceeds(setDoc(itemRef(db('member'), 'new13'), newItem(people.member.email, { url: 'https://x.org/brief' })));
    });

    test('a due day is a date, and the fields are only the ones the app writes', async () => {
      await assertSucceeds(setDoc(itemRef(db('member'), 'new14'), newItem(people.member.email, { dueAt: Timestamp.fromDate(new Date('2026-12-20T00:00:00Z')) })));
      await assertFails(setDoc(itemRef(db('member'), 'new15'), newItem(people.member.email, { dueAt: 'soon' })));
      await assertFails(setDoc(itemRef(db('member'), 'new16'), newItem(people.member.email, { colour: 'red' })));
    });
  });

  describe('changing and removing an assignment', () => {
    test('an author changes the words, the link and the due day', async () => {
      await assertSucceeds(
        updateDoc(itemRef(db('member'), MEMBER_ITEM), {
          title: 'Lab report 3 (revised)',
          details: 'Two pages',
          url: 'https://x.org/brief',
          dueAt: Timestamp.fromDate(new Date('2026-12-20T00:00:00Z')),
        })
      );
    });

    test('another member cannot change it', async () => {
      await assertFails(updateDoc(itemRef(db('other'), MEMBER_ITEM), { title: 'Hijacked' }));
    });

    test('an author cannot show or hide it, and cannot hand it to someone else', async () => {
      await assertFails(updateDoc(itemRef(db('member'), WAITING), { shown: true }));
      await assertFails(updateDoc(itemRef(db('member'), MEMBER_ITEM), { createdByEmail: people.other.email }));
    });

    test('an admin shows a waiting one, and changes any', async () => {
      await assertSucceeds(updateDoc(itemRef(db('admin'), WAITING), { shown: true }));
      await assertSucceeds(updateDoc(itemRef(db('admin'), MEMBER_ITEM), { title: 'Lab report 3 (admin)' }));
    });

    test('an author removes their own; another member cannot; an admin can', async () => {
      await assertFails(deleteDoc(itemRef(db('other'), MEMBER_ITEM)));
      await assertSucceeds(deleteDoc(itemRef(db('member'), MEMBER_ITEM)));
      await assertSucceeds(deleteDoc(itemRef(db('admin'), ADMIN_ITEM)));
    });

    test('a member reads a shown assignment and their own, an admin reads every one, and an outsider reads none', async () => {
      await assertSucceeds(getDoc(itemRef(db('member'), ADMIN_ITEM)));
      await assertSucceeds(getDoc(itemRef(db('member'), WAITING)));
      await assertFails(getDoc(itemRef(db('member'), OTHERS_WAITING)));
      await assertSucceeds(getDoc(itemRef(db('admin'), OTHERS_WAITING)));
      await assertFails(getDoc(itemRef(db('outsider'), ADMIN_ITEM)));
    });

    test('a member lists the shown ones and their own waiting ones, but not everyone\'s', async () => {
      const shown = query(itemsCol(db('member')), where('shown', '==', true));
      await assertSucceeds(getDocs(shown));
      const own = query(itemsCol(db('member')), where('createdByEmail', '==', people.member.email));
      await assertSucceeds(getDocs(own));
      await assertFails(getDocs(itemsCol(db('member'))));
    });

    test('an admin lists every assignment in one query', async () => {
      await assertSucceeds(getDocs(itemsCol(db('admin'))));
    });
  });

  describe('finished marks', () => {
    test('a member marks an assignment finished in their own document', async () => {
      await assertSucceeds(setDoc(markRef(db('member'), people.member.email), { done: [ADMIN_ITEM] }));
      await assertSucceeds(updateDoc(markRef(db('member'), people.member.email), { done: arrayUnion(MEMBER_ITEM) }));
      await assertSucceeds(updateDoc(markRef(db('member'), people.member.email), { done: arrayRemove(ADMIN_ITEM) }));
    });

    test('a member cannot write another member\'s marks, nor read them', async () => {
      await assertFails(setDoc(markRef(db('member'), people.other.email), { done: [ADMIN_ITEM] }));
      await assertSucceeds(setDoc(markRef(db('other'), people.other.email), { done: [ADMIN_ITEM] }));
      await assertFails(getDoc(markRef(db('member'), people.other.email)));
    });

    test('the marks hold only a list of done ids', async () => {
      await assertFails(setDoc(markRef(db('member'), people.member.email), { done: 'lab' }));
      await assertFails(setDoc(markRef(db('member'), people.member.email), { done: [ADMIN_ITEM], extra: 1 }));
    });

    test('a member can clear their own marks', async () => {
      await assertSucceeds(setDoc(markRef(db('member'), people.member.email), { done: [ADMIN_ITEM] }));
      await assertSucceeds(deleteDoc(markRef(db('member'), people.member.email)));
    });

    test('marks are kept in an archived subject, which takes no new assignment', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: true }));
      await assertSucceeds(setDoc(markRef(db('member'), people.member.email), { done: [ADMIN_ITEM] }));
      await assertSucceeds(getDoc(markRef(db('member'), people.member.email)));
    });
  });
});
