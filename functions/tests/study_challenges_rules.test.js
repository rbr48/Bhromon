// A study group's weekly challenge: one challenge a week per subject, set by an admin, and each member's own join of it.
// Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_challenges_rules"
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
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');

// Starting the emulator and loading the rules can take longer than Jest's default five-second hook timeout.
jest.setTimeout(120000);

const PROJECT_ID = 'bhromon-rules-test-project';
const STUDY = 'challengeclub';
const SUBJECT = 'calc101';
const OFF = 'calc3';
const WEEK = '2026-11-09';
const NEXT_WEEK = '2026-11-16';
const people = {
  owner: { uid: 'chowner', email: 'chowner@x.com' },
  admin: { uid: 'chadmin', email: 'chadmin@x.com' },
  member: { uid: 'chmem', email: 'chmem@x.com' },
  other: { uid: 'choth', email: 'choth@x.com' },
  outsider: { uid: 'cheve', email: 'cheve@x.com' },
};

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

const moduleSettings = (extra = {}) => ({ enabled: true, name: 'Weekly challenge', postPolicy: 'admins', ...extra });

// A challenge as it was stored earlier: a fixed time, so the server-time rule does not apply.
const challenge = (by, extra = {}) => ({
  kind: 'problems',
  target: 5,
  setByEmail: by,
  setAt: Timestamp.fromDate(new Date('2026-11-09T06:00:00Z')),
  ...extra,
});

// A challenge as an admin writes it now: the server stamps the time, as the app does.
const newChallenge = (by, extra = {}) => ({
  kind: 'problems',
  target: 5,
  setByEmail: by,
  setAt: serverTimestamp(),
  ...extra,
});

const subjectRef = (f, id = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', id);
const moduleRef = (f, id = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', id, 'modules', 'challenges');
const challengeRef = (f, weekKey, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'challenges', weekKey);
const joinRef = (f, weekKey, email, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'challenges', weekKey, 'joins', email);
const joinsCollection = (f, weekKey, subjectId = SUBJECT) =>
  collection(f, 'tours', STUDY, 'study_subjects', subjectId, 'challenges', weekKey, 'joins');

describe('weekly challenges and member joins', () => {
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
        inviteCode: 'CHAL00001',
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

      // A listed subject whose challenges module is on, with this week's challenge and another member's join.
      await setDoc(subjectRef(f), subject(people.admin.email));
      await setDoc(moduleRef(f), moduleSettings());
      await setDoc(challengeRef(f, WEEK), challenge(people.admin.email));
      await setDoc(joinRef(f, WEEK, people.other.email), { joinedAt: Timestamp.fromDate(new Date('2026-11-09T07:00:00Z')) });

      // A subject whose challenges module is off, with a challenge that was set before it was switched off.
      await setDoc(subjectRef(f, OFF), subject(people.admin.email, { title: 'Calculus 3' }));
      await setDoc(moduleRef(f, OFF), moduleSettings({ enabled: false }));
      await setDoc(challengeRef(f, WEEK, OFF), challenge(people.admin.email));
    });
  });

  describe('setting a challenge', () => {
    test('an admin sets the challenge for a week, with its kind, target and the admin as the setter', async () => {
      await assertSucceeds(setDoc(challengeRef(db('admin'), NEXT_WEEK), newChallenge(people.admin.email, { kind: 'findings', target: 3 })));
    });

    test('an owner sets a challenge as an admin does', async () => {
      await assertSucceeds(setDoc(challengeRef(db('owner'), NEXT_WEEK), newChallenge(people.owner.email, { kind: 'cards', target: 10 })));
    });

    test('a member cannot set a challenge', async () => {
      await assertFails(setDoc(challengeRef(db('member'), NEXT_WEEK), newChallenge(people.member.email)));
    });

    test('an admin cannot set a challenge when the challenges module is off', async () => {
      await assertFails(setDoc(challengeRef(db('admin'), NEXT_WEEK, OFF), newChallenge(people.admin.email)));
    });

    test('the kind is one of problems, findings and cards', async () => {
      await assertSucceeds(setDoc(challengeRef(db('admin'), NEXT_WEEK), newChallenge(people.admin.email, { kind: 'cards' })));
      await assertFails(setDoc(challengeRef(db('admin'), '2026-11-30'), newChallenge(people.admin.email, { kind: 'quizzes' })));
    });

    test('the target is a whole number from one to twenty', async () => {
      await assertSucceeds(setDoc(challengeRef(db('admin'), NEXT_WEEK), newChallenge(people.admin.email, { target: 1 })));
      await assertSucceeds(setDoc(challengeRef(db('admin'), '2026-11-23'), newChallenge(people.admin.email, { target: 20 })));
      await assertFails(setDoc(challengeRef(db('admin'), '2026-11-30'), newChallenge(people.admin.email, { target: 0 })));
      await assertFails(setDoc(challengeRef(db('admin'), '2026-12-07'), newChallenge(people.admin.email, { target: 21 })));
      await assertFails(setDoc(challengeRef(db('admin'), '2026-12-14'), newChallenge(people.admin.email, { target: 2.5 })));
      await assertFails(setDoc(challengeRef(db('admin'), '2026-12-21'), newChallenge(people.admin.email, { target: 'five' })));
    });

    test('the setter is the admin who writes it, and the time is the server\'s', async () => {
      await assertFails(setDoc(challengeRef(db('admin'), NEXT_WEEK), newChallenge(people.owner.email)));
      await assertFails(setDoc(challengeRef(db('admin'), NEXT_WEEK), challenge(people.admin.email)));
    });

    test('a challenge carries no fields beyond its kind, target, setter and time', async () => {
      await assertFails(setDoc(challengeRef(db('admin'), NEXT_WEEK), newChallenge(people.admin.email, { title: 'Extra' })));
    });

    test('the week id is a date in yyyy-MM-dd form', async () => {
      await assertFails(setDoc(challengeRef(db('admin'), 'bogus'), newChallenge(people.admin.email)));
      await assertFails(setDoc(challengeRef(db('admin'), '2026-1-9'), newChallenge(people.admin.email)));
    });

    test('an admin changes the kind and target of the week\'s challenge, and a member cannot', async () => {
      await assertSucceeds(updateDoc(challengeRef(db('admin'), WEEK), {
        kind: 'findings',
        target: 3,
        setByEmail: people.admin.email,
        setAt: serverTimestamp(),
      }));
      await assertFails(updateDoc(challengeRef(db('member'), WEEK), {
        kind: 'cards',
        target: 1,
        setByEmail: people.member.email,
        setAt: serverTimestamp(),
      }));
    });

    test('an admin removes a challenge, and a member cannot', async () => {
      await assertFails(deleteDoc(challengeRef(db('member'), WEEK)));
      await assertSucceeds(deleteDoc(challengeRef(db('admin'), WEEK)));
    });
  });

  describe('reading a challenge', () => {
    test('an active member reads the challenge, and an outsider does not', async () => {
      await assertSucceeds(getDoc(challengeRef(db('member'), WEEK)));
      await assertFails(getDoc(challengeRef(db('outsider'), WEEK)));
    });
  });

  describe('joining a challenge', () => {
    test('a member joins for themselves, once the challenge is set', async () => {
      await assertSucceeds(setDoc(joinRef(db('member'), WEEK, people.member.email), { joinedAt: serverTimestamp() }));
    });

    test('a member cannot join for someone else', async () => {
      await assertFails(setDoc(joinRef(db('member'), WEEK, people.other.email), { joinedAt: serverTimestamp() }));
      await assertFails(setDoc(joinRef(db('admin'), WEEK, people.member.email), { joinedAt: serverTimestamp() }));
    });

    test('a join carries only the time it was made', async () => {
      await assertFails(setDoc(joinRef(db('member'), WEEK, people.member.email), { joinedAt: serverTimestamp(), note: 'x' }));
      await assertFails(setDoc(joinRef(db('member'), WEEK, people.member.email), { joinedAt: Timestamp.fromDate(new Date('2026-11-09T07:00:00Z')) }));
    });

    test('a member cannot join a week that has no challenge', async () => {
      await assertFails(setDoc(joinRef(db('member'), NEXT_WEEK, people.member.email), { joinedAt: serverTimestamp() }));
    });

    test('a member cannot join when the challenges module is off', async () => {
      await assertFails(setDoc(joinRef(db('member'), WEEK, people.member.email, OFF), { joinedAt: serverTimestamp() }));
    });

    test('a member leaves for themselves, and cannot remove another member\'s join', async () => {
      await assertFails(deleteDoc(joinRef(db('member'), WEEK, people.other.email)));
      await assertSucceeds(setDoc(joinRef(db('member'), WEEK, people.member.email), { joinedAt: serverTimestamp() }));
      await assertSucceeds(deleteDoc(joinRef(db('member'), WEEK, people.member.email)));
    });

    test('members see who has joined, and an outsider does not', async () => {
      await assertSucceeds(getDocs(joinsCollection(db('member'), WEEK)));
      await assertFails(getDocs(joinsCollection(db('outsider'), WEEK)));
    });
  });
});
