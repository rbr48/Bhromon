// A study group's shared findings: a result a member reached, how it was checked, and the checks
// other members make of it. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_findings_rules"
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
const STUDY = 'findingclub';
const SUBJECT = 'stat101';
const APPROVAL = 'stat2';
const OFF = 'stat3';
const PROPOSED = 'prob';
const F_ADMIN = 'fd-admin';
const F_MEMBER = 'fd-member';
const F_WAITING = 'fd-waiting';
const F_CHECKED = 'fd-checked';
const people = {
  owner: { uid: 'fdowner', email: 'fdowner@x.com' },
  admin: { uid: 'fdadmin', email: 'fdadmin@x.com' },
  member: { uid: 'fdmem', email: 'fdmem@x.com' },
  other: { uid: 'fdother', email: 'fdother@x.com' },
  outsider: { uid: 'fdeve', email: 'fdeve@x.com' },
};

const subject = (by, extra = {}) => ({
  title: 'Statistics 101',
  code: 'STA 101',
  description: null,
  examDate: null,
  approval: 'listed',
  declineNote: null,
  createdByEmail: by,
  ...extra,
});

const moduleSettings = (extra = {}) => ({ enabled: true, name: 'Shared findings', postPolicy: 'members', ...extra });

// A finding as it was stored earlier: a fixed time, so the server-time rule does not apply.
const finding = (by, extra = {}) => ({
  text: 'The sample gives 4.2 at 25 degrees.',
  method: 'Repeated three times on the lab bench.',
  createdByEmail: by,
  createdAt: Timestamp.fromDate(new Date('2026-11-01T10:00:00Z')),
  confirmCount: 0,
  challengeCount: 0,
  shown: true,
  pinned: false,
  ...extra,
});

// A finding as it is written now: the server stamps the time, as the app does.
const newFinding = (by, extra = {}) => ({ ...finding(by), createdAt: serverTimestamp(), ...extra });

const subjectRef = (f, id = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', id);
const moduleRef = (f, id = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', id, 'modules', 'findings');
const findingRef = (f, id, subjectId = SUBJECT) => doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'findings', id);
const checkRef = (f, id, email, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'findings', id, 'checks', email);
const reportRef = (f, id, email, subjectId = SUBJECT) =>
  doc(f, 'tours', STUDY, 'study_subjects', subjectId, 'findings', id, 'reports', email);

describe('shared findings and the checks on them', () => {
  let env;
  const db = (who) =>
    env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

  // A member confirms or challenges a finding: the check and its count are written in one batch.
  const checkBatch = (who, id, verdict, subjectId = SUBJECT, extra = {}) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.set(checkRef(f, id, people[who].email, subjectId), {
      verdict,
      createdAt: serverTimestamp(),
      ...extra,
    });
    batch.update(
      findingRef(f, id, subjectId),
      verdict === 'confirm' ? { confirmCount: increment(1) } : { challengeCount: increment(1) },
    );
    return batch.commit();
  };

  // A member takes their own check back: the check goes and its count falls, in one batch.
  const withdrawBatch = (who, id, verdict, subjectId = SUBJECT) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.delete(checkRef(f, id, people[who].email, subjectId));
    batch.update(
      findingRef(f, id, subjectId),
      verdict === 'confirm' ? { confirmCount: increment(-1) } : { challengeCount: increment(-1) },
    );
    return batch.commit();
  };

  // A member reports a finding: the report, the hiding and the count move in one batch, as the app writes them.
  const reportBatch = (who, id, { firstReport = true, reason = 'wrong', count = 1, shown = false } = {}) => {
    const f = db(who);
    const batch = writeBatch(f);
    batch.set(reportRef(f, id, people[who].email), { reason, createdAt: serverTimestamp() });
    batch.update(findingRef(f, id), {
      shown,
      reportCount: increment(count),
      ...(firstReport ? { reportedAt: serverTimestamp() } : {}),
    });
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
        inviteCode: 'FIND00001',
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

      // A listed subject whose findings module is on, with one finding of each kind.
      await setDoc(subjectRef(f), subject(people.admin.email));
      await setDoc(moduleRef(f), moduleSettings());
      await setDoc(findingRef(f, F_ADMIN), finding(people.admin.email, { text: 'Admin result' }));
      await setDoc(findingRef(f, F_MEMBER), finding(people.member.email));
      await setDoc(findingRef(f, F_WAITING), finding(people.member.email, { shown: false, text: 'Waiting result' }));
      // A finding already confirmed by one member, so that member can take the check back.
      await setDoc(findingRef(f, F_CHECKED), finding(people.admin.email, { confirmCount: 1 }));
      await setDoc(checkRef(f, F_CHECKED, people.other.email), {
        verdict: 'confirm',
        createdAt: Timestamp.fromDate(new Date('2026-11-01T11:00:00Z')),
      });

      // A subject whose module waits for an admin to show each post.
      await setDoc(subjectRef(f, APPROVAL), subject(people.admin.email, { title: 'Statistics 2' }));
      await setDoc(moduleRef(f, APPROVAL), moduleSettings({ postPolicy: 'approval' }));

      // A listed subject whose findings module is off.
      await setDoc(subjectRef(f, OFF), subject(people.admin.email, { title: 'Statistics 3' }));
      await setDoc(moduleRef(f, OFF), moduleSettings({ enabled: false }));

      // A proposal, with its module on, which takes no findings until an admin lists it.
      await setDoc(subjectRef(f, PROPOSED), subject(people.member.email, { title: 'Probability', code: null, approval: 'proposed' }));
      await setDoc(moduleRef(f, PROPOSED), moduleSettings());
    });
  });

  describe('posting a finding', () => {
    test('a member posts a finding under their own email, with no checks yet', async () => {
      await assertSucceeds(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email)));
    });

    test('a member cannot post under someone else\'s email', async () => {
      await assertFails(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.owner.email)));
    });

    test('a new finding starts with no checks and is not pinned', async () => {
      await assertFails(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { confirmCount: 2 })));
      await assertFails(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { pinned: true })));
    });

    test('a finding needs a result and a method, within their limits', async () => {
      await assertFails(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { method: '' })));
      await assertSucceeds(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { text: 'x'.repeat(1001) })));
      await assertSucceeds(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { method: 'x'.repeat(501) })));
      await assertSucceeds(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { text: 'x'.repeat(1000) })));
    });

    test('a finding cannot be posted when its module is off, by a member or an admin', async () => {
      await assertFails(setDoc(findingRef(db('member'), 'fd-new', OFF), newFinding(people.member.email)));
      await assertFails(setDoc(findingRef(db('admin'), 'fd-new', OFF), newFinding(people.admin.email)));
    });

    test('a member\'s finding in an approval module waits for an admin, and an admin\'s is shown at once', async () => {
      await assertSucceeds(setDoc(findingRef(db('member'), 'fd-new', APPROVAL), newFinding(people.member.email, { shown: false })));
      await assertFails(setDoc(findingRef(db('member'), 'fd-new2', APPROVAL), newFinding(people.member.email, { shown: true })));
      await assertSucceeds(setDoc(findingRef(db('admin'), 'fd-new3', APPROVAL), newFinding(people.admin.email, { shown: true })));
      await assertFails(setDoc(findingRef(db('admin'), 'fd-new4', APPROVAL), newFinding(people.admin.email, { shown: false })));
    });

    test('a finding cannot be posted in a proposal, which no member can use until it is listed', async () => {
      await assertFails(setDoc(findingRef(db('member'), 'fd-new', PROPOSED), newFinding(people.member.email)));
    });
  });

  describe('editing and showing a finding', () => {
    test('the author changes the result and the method, and no other member does', async () => {
      await assertSucceeds(updateDoc(findingRef(db('member'), F_MEMBER), {
        text: 'Revised result',
        method: 'Ran it five times.',
      }));
      await assertFails(updateDoc(findingRef(db('other'), F_MEMBER), { text: 'Hijacked' }));
    });

    test('an author cannot show or pin their own finding', async () => {
      await assertFails(updateDoc(findingRef(db('member'), F_WAITING), { shown: true }));
      await assertFails(updateDoc(findingRef(db('member'), F_MEMBER), { pinned: true }));
    });

    test('an admin shows a waiting finding and pins one', async () => {
      await assertSucceeds(updateDoc(findingRef(db('admin'), F_WAITING), { shown: true }));
      await assertSucceeds(updateDoc(findingRef(db('admin'), F_MEMBER), { pinned: true }));
    });

    test('no one changes a finding\'s counts directly, only through a check', async () => {
      await assertFails(updateDoc(findingRef(db('member'), F_MEMBER), { confirmCount: increment(1) }));
      await assertFails(updateDoc(findingRef(db('admin'), F_MEMBER), { challengeCount: increment(1) }));
    });
  });

  describe('checking a finding', () => {
    test('a member confirms another member\'s finding: the check and its count go together', async () => {
      await assertSucceeds(checkBatch('other', F_MEMBER, 'confirm'));
    });

    test('a member challenges a finding, and the challenge count moves, not the confirmation count', async () => {
      await assertSucceeds(checkBatch('other', F_MEMBER, 'challenge', SUBJECT, { note: 'The bench was warm.' }));
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(checkRef(f, F_ADMIN, people.other.email), { verdict: 'challenge', createdAt: serverTimestamp() });
      batch.update(findingRef(f, F_ADMIN), { confirmCount: increment(1) });
      await assertFails(batch.commit());
    });

    test('a check alone, without its count, is refused', async () => {
      const f = db('other');
      await assertFails(setDoc(checkRef(f, F_MEMBER, people.other.email), {
        verdict: 'confirm',
        createdAt: serverTimestamp(),
      }));
    });

    test('a count moved alone, without a check, is refused', async () => {
      await assertFails(updateDoc(findingRef(db('other'), F_MEMBER), { confirmCount: increment(1) }));
    });

    test('a member cannot check their own finding, or one an admin has not shown', async () => {
      await assertFails(checkBatch('member', F_MEMBER, 'confirm'));
      await assertFails(checkBatch('other', F_WAITING, 'confirm'));
    });

    test('a member checks a finding once: a second check is refused', async () => {
      await assertSucceeds(checkBatch('other', F_MEMBER, 'confirm'));
      await assertFails(checkBatch('other', F_MEMBER, 'challenge'));
    });

    test('a member writes only their own check', async () => {
      const f = db('other');
      await assertFails(setDoc(checkRef(f, F_MEMBER, people.member.email), {
        verdict: 'confirm',
        createdAt: serverTimestamp(),
      }));
    });

    test('a check has a verdict of confirm or challenge, and a note of any length', async () => {
      await assertFails(checkBatch('other', F_MEMBER, 'maybe'));
      await assertSucceeds(checkBatch('other', F_MEMBER, 'confirm', SUBJECT, { note: 'x'.repeat(301) }));
      await assertSucceeds(checkBatch('other', F_MEMBER, 'confirm', SUBJECT, { note: 'x'.repeat(300) }));
    });
  });

  describe('taking a check back', () => {
    test('a member withdraws their own check: the check goes and the count falls', async () => {
      await assertSucceeds(withdrawBatch('other', F_CHECKED, 'confirm'));
    });

    test('a count falls without its check going is refused', async () => {
      await assertFails(updateDoc(findingRef(db('other'), F_CHECKED), { confirmCount: increment(-1) }));
    });

    test('a check goes without its count falling is refused', async () => {
      await assertFails(deleteDoc(checkRef(db('other'), F_CHECKED, people.other.email)));
    });

    test('a withdrawal with the wrong count is refused', async () => {
      await assertFails(withdrawBatch('other', F_CHECKED, 'challenge'));
    });

    test('no member takes away another member\'s check', async () => {
      await assertFails(deleteDoc(checkRef(db('member'), F_CHECKED, people.other.email)));
    });
  });

  describe('reading and deleting', () => {
    test('members read findings and checks, and an outsider reads neither', async () => {
      await assertSucceeds(getDoc(findingRef(db('member'), F_MEMBER)));
      await assertSucceeds(getDoc(checkRef(db('member'), F_CHECKED, people.other.email)));
      await assertFails(getDoc(findingRef(db('outsider'), F_MEMBER)));
      await assertFails(getDoc(checkRef(db('outsider'), F_CHECKED, people.other.email)));
    });

    test('the author or an admin removes a finding; another member does not', async () => {
      await assertSucceeds(deleteDoc(findingRef(db('member'), F_MEMBER)));
      await assertFails(deleteDoc(findingRef(db('other'), F_ADMIN)));
      await assertSucceeds(deleteDoc(findingRef(db('admin'), F_ADMIN)));
    });
  });

  describe('reporting a finding', () => {
    test('a member reports someone else\'s shown finding: it is hidden and its count rises with the report', async () => {
      await assertSucceeds(reportBatch('other', F_MEMBER));
      // withSecurityRulesDisabled returns nothing, so the document is read inside the callback.
      let stored;
      await env.withSecurityRulesDisabled(async (ctx) => {
        stored = (await getDoc(findingRef(ctx.firestore(), F_MEMBER))).data();
      });
      expect(stored.shown).toBe(false);
      expect(stored.reportCount).toBe(1);
      expect(stored.reportedAt).toBeTruthy();
    });

    test('a second member\'s report keeps the first report time', async () => {
      await assertSucceeds(reportBatch('other', F_ADMIN));
      // The finding is hidden now; a later report keeps it hidden and moves only the count.
      await env.withSecurityRulesDisabled(async (ctx) =>
        updateDoc(findingRef(ctx.firestore(), F_ADMIN), { shown: true }));
      await assertSucceeds(reportBatch('member', F_ADMIN, { firstReport: false }));
    });

    test('nobody reports their own finding, or one an admin has not shown', async () => {
      await assertFails(reportBatch('member', F_MEMBER));
      await assertFails(reportBatch('other', F_WAITING));
    });

    test('a report must hide the finding and move the count by exactly one', async () => {
      await assertFails(reportBatch('other', F_MEMBER, { shown: true }));
      await assertFails(reportBatch('other', F_MEMBER, { count: 2 }));
    });

    test('a report needs its count, and a count needs its report', async () => {
      await assertFails(setDoc(reportRef(db('other'), F_MEMBER, people.other.email), { reason: 'wrong', createdAt: serverTimestamp() }));
      await assertFails(updateDoc(findingRef(db('other'), F_MEMBER), {
        shown: false, reportCount: increment(1), reportedAt: serverTimestamp(),
      }));
    });

    test('a report is the member\'s own and gives a known reason', async () => {
      const f = db('other');
      const batch = writeBatch(f);
      batch.set(reportRef(f, F_MEMBER, people.member.email), { reason: 'wrong', createdAt: serverTimestamp() });
      batch.update(findingRef(f, F_MEMBER), { shown: false, reportCount: increment(1), reportedAt: serverTimestamp() });
      await assertFails(batch.commit());
      await assertFails(reportBatch('other', F_MEMBER, { reason: 'boring' }));
    });

    test('an outsider cannot report', async () => {
      await assertFails(reportBatch('outsider', F_MEMBER));
    });

    test('a hidden reported finding takes no checks', async () => {
      await assertSucceeds(reportBatch('other', F_MEMBER));
      await assertFails(checkBatch('admin', F_MEMBER, 'confirm'));
    });

    test('an admin restores a reported finding, which clears its report time', async () => {
      await assertSucceeds(reportBatch('other', F_MEMBER));
      await assertFails(updateDoc(findingRef(db('member'), F_MEMBER), { shown: true, reportedAt: null }));
      await assertSucceeds(updateDoc(findingRef(db('admin'), F_MEMBER), { shown: true, reportedAt: null }));
    });

    test('an admin cannot set a report time by hand', async () => {
      await assertFails(updateDoc(findingRef(db('admin'), F_MEMBER), { reportedAt: serverTimestamp() }));
    });

    test('a new finding carries no reports', async () => {
      await assertFails(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email, { reportCount: 1 })));
      await assertSucceeds(setDoc(findingRef(db('member'), 'fd-new'), newFinding(people.member.email)));
    });

    test('the reporter and the admins read a report; the author does not', async () => {
      await assertSucceeds(reportBatch('other', F_MEMBER));
      await assertSucceeds(getDoc(reportRef(db('other'), F_MEMBER, people.other.email)));
      await assertSucceeds(getDoc(reportRef(db('admin'), F_MEMBER, people.other.email)));
      await assertFails(getDoc(reportRef(db('member'), F_MEMBER, people.other.email)));
    });
  });
});
