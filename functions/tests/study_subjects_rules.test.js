// A study group's subjects: the list an admin keeps, the modules an admin turns on, the posts
// members add in them, and the helpful marks on those posts. Runs against the Firestore
// emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_subjects_rules"
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
  deleteField,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'subjectclub';
const HOUSEHOLD = 'subjectfamily';
const SUBJECT = 'phy101';
const PROPOSED = 'chem';
const TIP = 'tip-admin';
const MEMBER_TIP = 'tip-member';
const WAITING = 'sugg-waiting';
const people = {
  owner: { uid: 'subowner', email: 'subowner@x.com' },
  admin: { uid: 'subadmin', email: 'subadmin@x.com' },
  member: { uid: 'submem', email: 'submem@x.com' },
  other: { uid: 'subother', email: 'subother@x.com' },
  outsider: { uid: 'subeve', email: 'subeve@x.com' },
};

const subject = (by, extra = {}) => ({
  title: 'Physics 101',
  code: 'PHY 101',
  description: null,
  examDate: null,
  approval: 'listed',
  declineNote: null,
  createdByEmail: by,
  ...extra,
});

const moduleSettings = (extra = {}) => ({ enabled: true, name: 'Exam tips', postPolicy: 'members', ...extra });

// A post as it was stored earlier: a fixed time, so the server-time rule does not apply.
const post = (by, extra = {}) => ({
  text: 'Solve the past papers before the mock test.',
  title: null,
  url: null,
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-01T10:00:00Z')),
  helpfulCount: 0,
  shown: true,
  pinned: false,
  ...extra,
});

// A post as it is written now: the server stamps the time, as the app does.
const newPost = (by, extra = {}) => ({ ...post(by), createdAt: serverTimestamp(), ...extra });

const subjectRef = (f, id = SUBJECT, tour = STUDY) => doc(f, 'tours', tour, 'study_subjects', id);
const moduleRef = (f, key, id = SUBJECT, tour = STUDY) => doc(f, 'tours', tour, 'study_subjects', id, 'modules', key);
const postRef = (f, kind, postId, id = SUBJECT, tour = STUDY) => doc(f, 'tours', tour, 'study_subjects', id, kind, postId);
const markRef = (f, kind, postId, voterEmail, id = SUBJECT, tour = STUDY) =>
  doc(f, 'tours', tour, 'study_subjects', id, kind, postId, 'helpful', voterEmail);

describe('study subjects, modules and posts', () => {
  let env;
  const db = (who) =>
    env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

  // A member marks a post helpful: the mark and the count change in one batch.
  const mark = (who, kind, postId, id = SUBJECT) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.set(markRef(f, kind, postId, people[who].email, id), { createdAt: serverTimestamp() });
    batch.update(postRef(f, kind, postId, id), { helpfulCount: increment(1) });
    return batch.commit();
  };
  // A member takes the mark back: the mark goes and the count falls in one batch.
  const unmark = (who, kind, postId, id = SUBJECT) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.delete(markRef(f, kind, postId, people[who].email, id));
    batch.update(postRef(f, kind, postId, id), { helpfulCount: increment(-1) });
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
        inviteCode: 'SUBJ00001',
      });
      await setDoc(doc(f, 'tours', HOUSEHOLD), {
        name: 'Rahman family',
        kind: 'family',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'SUBJ00002',
      });
      const membership = (tourId, email, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), { tourId, email, role, status: 'active', displayName: email });
      for (const tourId of [STUDY, HOUSEHOLD]) {
        await membership(tourId, people.owner.email, 'owner');
        await membership(tourId, people.admin.email, 'admin');
        await membership(tourId, people.member.email, 'member');
        await membership(tourId, people.other.email, 'member');
      }
      // A listed subject with its modules, one listed and one proposed.
      await setDoc(subjectRef(f), subject(people.admin.email));
      await setDoc(moduleRef(f, 'tips'), moduleSettings());
      await setDoc(moduleRef(f, 'suggestions'), moduleSettings({ name: 'Suggestions', postPolicy: 'approval' }));
      await setDoc(postRef(f, 'tips', TIP), post(people.admin.email));
      await setDoc(postRef(f, 'tips', MEMBER_TIP), post(people.member.email));
      await setDoc(postRef(f, 'suggestions', WAITING), post(people.member.email, { shown: false, text: 'Try the free course.' }));
      // A proposal, with its modules set up, to show that a proposal takes no posts.
      await setDoc(subjectRef(f, PROPOSED), subject(people.member.email, { title: 'Chemistry', code: null, approval: 'proposed' }));
      await setDoc(moduleRef(f, 'tips', PROPOSED), moduleSettings());
    });
  });

  describe('the subject list', () => {
    test('a member proposes a subject under their own email', async () => {
      await assertSucceeds(setDoc(subjectRef(db('member'), 'bio'), subject(people.member.email, { title: 'Biology', code: null, approval: 'proposed' })));
    });

    test('a member cannot list a subject, nor propose one under someone else\'s email', async () => {
      await assertFails(setDoc(subjectRef(db('member'), 'bio'), subject(people.member.email, { title: 'Biology' })));
      await assertFails(setDoc(subjectRef(db('member'), 'bio'), subject(people.owner.email, { approval: 'proposed' })));
    });

    test('an admin lists a subject at once', async () => {
      await assertSucceeds(setDoc(subjectRef(db('admin'), 'bio'), subject(people.admin.email, { title: 'Biology' })));
    });

    test('a member cannot change a proposal\'s approval', async () => {
      await assertFails(updateDoc(subjectRef(db('member'), PROPOSED), { approval: 'listed' }));
    });

    test('an admin lists a proposal, and declines one with a note only when it is declined', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin'), PROPOSED), { approval: 'listed', declineNote: deleteField() }));
      await assertFails(updateDoc(subjectRef(db('admin'), PROPOSED), { approval: 'listed', declineNote: 'Not this course' }));
      await assertSucceeds(updateDoc(subjectRef(db('admin'), PROPOSED), { approval: 'declined', declineNote: 'Not this course' }));
    });

    test('the proposer edits their own subject, and no other member does', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('member'), PROPOSED), { title: 'Chemistry 1' }));
      await assertFails(updateDoc(subjectRef(db('other'), PROPOSED), { title: 'Hijacked' }));
    });

    test('a subject cannot be handed to someone else', async () => {
      await assertFails(updateDoc(subjectRef(db('member'), PROPOSED), { createdByEmail: people.other.email }));
    });

    test('a title can be any length', async () => {
      await assertSucceeds(setDoc(subjectRef(db('admin'), 'long'), subject(people.admin.email, { title: 'x'.repeat(81) })));
      await assertSucceeds(setDoc(subjectRef(db('admin'), 'fits'), subject(people.admin.email, { title: 'x'.repeat(80) })));
    });

    test('subjects are kept only in a study group', async () => {
      await assertFails(setDoc(subjectRef(db('admin'), 'x', HOUSEHOLD), subject(people.admin.email)));
    });

    test('members read the subjects, and outsiders read nothing', async () => {
      await assertSucceeds(getDoc(subjectRef(db('member'))));
      await assertFails(getDoc(subjectRef(db('outsider'))));
    });
  });

  describe('archiving a subject', () => {
    test('an admin archives a listed subject, and restores it', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: true }));
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: false }));
    });

    test('a member cannot archive a subject, nor restore one', async () => {
      await assertFails(updateDoc(subjectRef(db('member')), { archived: true }));
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: true }));
      await assertFails(updateDoc(subjectRef(db('member')), { archived: false }));
    });

    test('the member who proposed a subject cannot archive it once an admin lists it', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin'), PROPOSED), { approval: 'listed', declineNote: deleteField() }));
      await assertFails(updateDoc(subjectRef(db('member'), PROPOSED), { archived: true }));
    });

    test('only a listed subject can be archived', async () => {
      await assertFails(updateDoc(subjectRef(db('admin'), PROPOSED), { archived: true }));
      await assertFails(
        updateDoc(subjectRef(db('admin'), PROPOSED), { approval: 'declined', declineNote: 'Not this course', archived: true })
      );
    });

    test('the archived flag is true or false, and a subject is never created archived', async () => {
      await assertFails(updateDoc(subjectRef(db('admin')), { archived: 'yes' }));
      await assertFails(setDoc(subjectRef(db('admin'), 'arch'), subject(people.admin.email, { archived: true })));
      await assertSucceeds(setDoc(subjectRef(db('admin'), 'live'), subject(people.admin.email, { archived: false })));
    });

    test('an archived subject takes no new post, from a member or an admin, and a restored one takes posts again', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: true }));
      await assertFails(setDoc(postRef(db('member'), 'tips', 'late'), newPost(people.member.email)));
      await assertFails(setDoc(postRef(db('admin'), 'tips', 'late-admin'), newPost(people.admin.email)));
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: false }));
      await assertSucceeds(setDoc(postRef(db('member'), 'tips', 'late'), newPost(people.member.email)));
    });

    test('an archived subject keeps its content, which members still read', async () => {
      await assertSucceeds(updateDoc(subjectRef(db('admin')), { archived: true }));
      await assertSucceeds(getDoc(postRef(db('member'), 'tips', MEMBER_TIP)));
    });
  });

  describe('the modules of a subject', () => {
    test('only an admin turns a live module on, and a member cannot', async () => {
      await assertFails(setDoc(moduleRef(db('member'), 'tips'), moduleSettings({ enabled: false })));
      await assertSucceeds(setDoc(moduleRef(db('admin'), 'tips'), moduleSettings({ enabled: false })));
    });

    test('a module that is not live yet cannot be turned on', async () => {
      await assertFails(setDoc(moduleRef(db('admin'), 'flashcards'), moduleSettings()));
    });

    test('a post policy is one of the three', async () => {
      await assertFails(setDoc(moduleRef(db('admin'), 'tips'), moduleSettings({ postPolicy: 'everyone' })));
    });

    test('a module takes only its three fields', async () => {
      await assertFails(setDoc(moduleRef(db('admin'), 'tips'), { ...moduleSettings(), colour: 'red' }));
    });

    test('a module name is at least 1 character, with no upper limit', async () => {
      await assertFails(setDoc(moduleRef(db('admin'), 'tips'), moduleSettings({ name: '' })));
      await assertSucceeds(setDoc(moduleRef(db('admin'), 'tips'), moduleSettings({ name: 'x'.repeat(41) })));
      await assertSucceeds(setDoc(moduleRef(db('admin'), 'tips'), moduleSettings({ name: 'x'.repeat(40) })));
    });

    test('members read the modules', async () => {
      await assertSucceeds(getDoc(moduleRef(db('member'), 'tips')));
    });
  });

  describe('posting in a module', () => {
    test('a member posts a tip, which the module shows at once', async () => {
      await assertSucceeds(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email)));
    });

    test('a member cannot post in a module that is off', async () => {
      await assertSucceeds(setDoc(moduleRef(db('admin'), 'tips'), moduleSettings({ enabled: false })));
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email)));
    });

    test('a member cannot post in an admin-only module, but an admin can', async () => {
      await assertSucceeds(setDoc(moduleRef(db('admin'), 'suggestions'), moduleSettings({ name: 'Suggestions', postPolicy: 'admins' })));
      await assertFails(setDoc(postRef(db('member'), 'suggestions', 'new-sugg'), newPost(people.member.email)));
      await assertSucceeds(setDoc(postRef(db('admin'), 'suggestions', 'new-sugg'), newPost(people.admin.email)));
    });

    test('a member\'s post waits when the module asks for approval', async () => {
      await assertFails(setDoc(postRef(db('member'), 'suggestions', 'new-sugg'), newPost(people.member.email, { shown: true })));
      await assertSucceeds(setDoc(postRef(db('member'), 'suggestions', 'new-sugg'), newPost(people.member.email, { shown: false })));
    });

    test('a proposal takes no posts until an admin lists it', async () => {
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip', PROPOSED), newPost(people.member.email)));
    });

    test('a post is written under the writer\'s own email', async () => {
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.other.email)));
    });

    test('a new post carries no marks and no pin', async () => {
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { helpfulCount: 3 })));
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { pinned: true })));
    });

    test('a link is https', async () => {
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { url: 'http://example.com/paper' })));
      await assertSucceeds(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { url: 'https://example.com/paper' })));
    });

    test('the post carries the server time, not a time the writer chose', async () => {
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { createdAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')) })));
    });

    test('a post text can be any length', async () => {
      await assertFails(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { text: '' })));
      await assertSucceeds(setDoc(postRef(db('member'), 'tips', 'new-tip'), newPost(people.member.email, { text: 'x'.repeat(1001) })));
    });

    test('an outsider reads and writes no posts', async () => {
      await assertFails(getDoc(postRef(db('outsider'), 'tips', TIP)));
      await assertFails(setDoc(postRef(db('outsider'), 'tips', 'new-tip'), newPost(people.outsider.email)));
    });
  });

  describe('helpful marks', () => {
    test('a member marks another member\'s post, and the count rises with the mark', async () => {
      await assertSucceeds(mark('other', 'tips', MEMBER_TIP));
      const f = db('admin');
      const snap = await getDoc(postRef(f, 'tips', MEMBER_TIP));
      expect(snap.data().helpfulCount).toBe(1);
    });

    test('a count cannot rise without this member\'s mark', async () => {
      await assertFails(updateDoc(postRef(db('other'), 'tips', TIP), { helpfulCount: increment(1) }));
    });

    test('a mark cannot be written without the count rising with it', async () => {
      await assertFails(setDoc(markRef(db('other'), 'tips', TIP, people.other.email), { createdAt: serverTimestamp() }));
    });

    test('a member marks a post once', async () => {
      await assertSucceeds(mark('other', 'tips', MEMBER_TIP));
      await assertFails(mark('other', 'tips', MEMBER_TIP));
    });

    test('a member cannot mark their own post', async () => {
      await assertFails(mark('member', 'tips', MEMBER_TIP));
    });

    test('a member takes their own mark back', async () => {
      await assertSucceeds(mark('other', 'tips', MEMBER_TIP));
      await assertSucceeds(unmark('other', 'tips', MEMBER_TIP));
      const snap = await getDoc(postRef(db('admin'), 'tips', MEMBER_TIP));
      expect(snap.data().helpfulCount).toBe(0);
    });

    test('a member cannot take away another member\'s mark', async () => {
      await assertSucceeds(mark('other', 'tips', TIP));
      const f = db('member');
      const batch = writeBatch(f);
      batch.delete(markRef(f, 'tips', TIP, people.other.email));
      batch.update(postRef(f, 'tips', TIP), { helpfulCount: increment(-1) });
      await assertFails(batch.commit());
    });

    test('a count moves by one, not by two', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(markRef(f, 'tips', TIP, people.other.email), { createdAt: serverTimestamp() });
      batch.update(postRef(f, 'tips', TIP), { helpfulCount: increment(2) });
      await assertFails(batch.commit());
    });

    test('an unshown post takes no mark', async () => {
      await assertFails(mark('other', 'suggestions', WAITING));
    });

    test('a mark holds only its time', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(markRef(f, 'tips', TIP, people.other.email), { createdAt: serverTimestamp(), by: 'other' });
      batch.update(postRef(f, 'tips', TIP), { helpfulCount: increment(1) });
      await assertFails(batch.commit());
    });
  });

  describe('editing and removing a post', () => {
    test('an author changes the words of their own post', async () => {
      await assertSucceeds(updateDoc(postRef(db('member'), 'tips', MEMBER_TIP), { text: 'Revised tip.' }));
    });

    test('an author cannot show or pin their own post', async () => {
      await assertFails(updateDoc(postRef(db('member'), 'suggestions', WAITING), { shown: true }));
      await assertFails(updateDoc(postRef(db('member'), 'tips', MEMBER_TIP), { pinned: true }));
    });

    test('another member cannot change the words of a post', async () => {
      await assertFails(updateDoc(postRef(db('other'), 'tips', MEMBER_TIP), { text: 'Changed.' }));
    });

    test('an admin shows a waiting post, and pins one', async () => {
      await assertSucceeds(updateDoc(postRef(db('admin'), 'suggestions', WAITING), { shown: true }));
      await assertSucceeds(updateDoc(postRef(db('admin'), 'tips', TIP), { pinned: true }));
    });

    test('a post keeps its author', async () => {
      await assertFails(updateDoc(postRef(db('member'), 'tips', MEMBER_TIP), { createdByEmail: people.other.email }));
    });

    test('an author removes their own post, another member cannot, and an admin can', async () => {
      await assertSucceeds(deleteDoc(postRef(db('member'), 'tips', MEMBER_TIP)));
      await assertFails(deleteDoc(postRef(db('other'), 'tips', TIP)));
      await assertSucceeds(setDoc(postRef(db('member'), 'tips', 'mine'), newPost(people.member.email)));
      await assertSucceeds(deleteDoc(postRef(db('admin'), 'tips', 'mine')));
    });
  });
});
