// Mess bazar duty schedule security rules tests.
// Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/mess_bazar_rules.test.js"
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
  Timestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const MESS = 'messclub';
const NON_MESS = 'familyclub';
const people = {
  owner: { uid: 'mbowner', email: 'mbowner@x.com' },
  admin: { uid: 'mbadmin', email: 'mbadmin@x.com' },
  member: { uid: 'mbmem', email: 'mbmem@x.com' },
  other: { uid: 'mbother', email: 'mbother@x.com' },
  outsider: { uid: 'mbeve', email: 'mbeve@x.com' },
};

const schedule = (by, extra = {}) => ({
  dateKey: '2026-11-10',
  assignedEmails: [people.member.email],
  assignedNames: ['Mess Member'],
  note: 'Buy fish and vegetables',
  estimatedBudgetPaisa: 150000,
  isCompleted: false,
  updatedByEmail: by,
  updatedAt: Timestamp.now(),
  ...extra,
});

const bazarRef = (f, tourId = MESS, dateKey = '2026-11-10') =>
  doc(f, 'tours', tourId, 'mess_bazar_schedule', dateKey);

describe('Mess bazar duty schedule Firestore rules', () => {
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

      // Mess tour
      await setDoc(doc(f, 'tours', MESS), {
        name: 'Green Mess',
        kind: 'family',
        preset: 'mess',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'MESS0001',
      });

      // Non-mess tour (family circle)
      await setDoc(doc(f, 'tours', NON_MESS), {
        name: 'Rahman Family',
        kind: 'family',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'FAM00001',
      });

      const membership = (tourId, email, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${email}`), {
          tourId,
          email,
          role,
          status: 'active',
          displayName: email,
        });

      for (const tourId of [MESS, NON_MESS]) {
        await membership(tourId, people.owner.email, 'owner');
        await membership(tourId, people.admin.email, 'admin');
        await membership(tourId, people.member.email, 'member');
        await membership(tourId, people.other.email, 'member');
      }

      // Seed default schedule on MESS
      await setDoc(bazarRef(f, MESS, '2026-11-10'), schedule(people.admin.email));
    });
  });

  test('non-mess tour rejects reads and writes', async () => {
    // Admin cannot create bazar duty in a non-mess tour
    await assertFails(
      setDoc(bazarRef(db('admin'), NON_MESS, '2026-11-10'), schedule(people.admin.email))
    );
    // Member of non-mess tour cannot read
    await assertFails(getDoc(bazarRef(db('member'), NON_MESS, '2026-11-10')));
    // Outsider cannot read non-mess tour
    await assertFails(getDoc(bazarRef(db('outsider'), NON_MESS, '2026-11-10')));
  });

  test('mess member can read', async () => {
    // Assigned member can read
    await assertSucceeds(getDoc(bazarRef(db('member'), MESS, '2026-11-10')));
    // Another mess member can read
    await assertSucceeds(getDoc(bazarRef(db('other'), MESS, '2026-11-10')));
    // Admin can read
    await assertSucceeds(getDoc(bazarRef(db('admin'), MESS, '2026-11-10')));
    // Outsider cannot read
    await assertFails(getDoc(bazarRef(db('outsider'), MESS, '2026-11-10')));
  });

  test('non-admin cannot create new duty assignment', async () => {
    // Assigned member (regular member) cannot create
    await assertFails(
      setDoc(bazarRef(db('member'), MESS, '2026-11-11'), schedule(people.member.email, { dateKey: '2026-11-11' }))
    );
    // Other member cannot create
    await assertFails(
      setDoc(bazarRef(db('other'), MESS, '2026-11-11'), schedule(people.other.email, { dateKey: '2026-11-11' }))
    );
    // Outsider cannot create
    await assertFails(
      setDoc(bazarRef(db('outsider'), MESS, '2026-11-11'), schedule(people.outsider.email, { dateKey: '2026-11-11' }))
    );
  });

  test('admin can create and assign members', async () => {
    // Admin creates schedule
    await assertSucceeds(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-11'),
        schedule(people.admin.email, {
          dateKey: '2026-11-11',
          assignedEmails: [people.member.email, people.other.email],
          assignedNames: ['Member A', 'Member B'],
        })
      )
    );
    // Owner creates schedule
    await assertSucceeds(
      setDoc(
        bazarRef(db('owner'), MESS, '2026-11-12'),
        schedule(people.owner.email, {
          dateKey: '2026-11-12',
          assignedEmails: [people.member.email],
        })
      )
    );

    // Validation checks on create
    // Mismatched dateKey
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        schedule(people.admin.email, { dateKey: '2026-11-14' })
      )
    );
    // More than 20 assigned emails
    const tooMany = Array.from({ length: 21 }, (_, i) => `user${i}@x.com`);
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        schedule(people.admin.email, { dateKey: '2026-11-13', assignedEmails: tooMany })
      )
    );
    // Note longer than 500 characters
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        schedule(people.admin.email, { dateKey: '2026-11-13', note: 'x'.repeat(501) })
      )
    );
    // Negative estimated budget
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        schedule(people.admin.email, { dateKey: '2026-11-13', estimatedBudgetPaisa: -100 })
      )
    );
    // Non-bool isCompleted
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        schedule(people.admin.email, { dateKey: '2026-11-13', isCompleted: 'done' })
      )
    );
    // Spoofed updatedByEmail
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        schedule(people.member.email, { dateKey: '2026-11-13' })
      )
    );
    // Unexpected extra field
    await assertFails(
      setDoc(
        bazarRef(db('admin'), MESS, '2026-11-13'),
        {
          ...schedule(people.admin.email, { dateKey: '2026-11-13' }),
          rogueField: 'exploit',
        }
      )
    );
  });

  test('assigned member can update note and mark completed', async () => {
    // Assigned member updates note
    await assertSucceeds(
      updateDoc(bazarRef(db('member'), MESS, '2026-11-10'), {
        note: 'Bought 2kg Hilsha fish and 5kg potatoes',
        updatedByEmail: people.member.email,
      })
    );

    // Assigned member marks completed and logs actual expense
    await assertSucceeds(
      updateDoc(bazarRef(db('member'), MESS, '2026-11-10'), {
        isCompleted: true,
        actualExpensePaisa: 142000,
        expenseId: 'exp_bazar_001',
        updatedByEmail: people.member.email,
      })
    );
  });

  test('non-assigned member cannot update duty assignment', async () => {
    // 'other' is an active mess member, but NOT in assignedEmails for 2026-11-10
    await assertFails(
      updateDoc(bazarRef(db('other'), MESS, '2026-11-10'), {
        note: 'Unauthorized note update',
        updatedByEmail: people.other.email,
      })
    );

    // 'other' cannot mark completed
    await assertFails(
      updateDoc(bazarRef(db('other'), MESS, '2026-11-10'), {
        isCompleted: true,
        updatedByEmail: people.other.email,
      })
    );

    // Outsider cannot update
    await assertFails(
      updateDoc(bazarRef(db('outsider'), MESS, '2026-11-10'), {
        isCompleted: true,
        updatedByEmail: people.outsider.email,
      })
    );
  });

  test('assigned member cannot reassign to another member', async () => {
    // Assigned member attempts to reassign duty to 'other'
    await assertFails(
      updateDoc(bazarRef(db('member'), MESS, '2026-11-10'), {
        assignedEmails: [people.other.email],
        updatedByEmail: people.member.email,
      })
    );

    // Assigned member attempts to add another member to assignments
    await assertFails(
      updateDoc(bazarRef(db('member'), MESS, '2026-11-10'), {
        assignedEmails: [people.member.email, people.other.email],
        updatedByEmail: people.member.email,
      })
    );

    // Admin CAN reassign members
    await assertSucceeds(
      updateDoc(bazarRef(db('admin'), MESS, '2026-11-10'), {
        assignedEmails: [people.other.email],
        updatedByEmail: people.admin.email,
      })
    );
  });

  test('admin can delete assignment', async () => {
    // Assigned member cannot delete
    await assertFails(deleteDoc(bazarRef(db('member'), MESS, '2026-11-10')));

    // Non-assigned member cannot delete
    await assertFails(deleteDoc(bazarRef(db('other'), MESS, '2026-11-10')));

    // Outsider cannot delete
    await assertFails(deleteDoc(bazarRef(db('outsider'), MESS, '2026-11-10')));

    // Admin can delete
    await assertSucceeds(deleteDoc(bazarRef(db('admin'), MESS, '2026-11-10')));

    // Seed another one for owner delete test
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(bazarRef(ctx.firestore(), MESS, '2026-11-15'), schedule(people.admin.email, { dateKey: '2026-11-15' }));
    });

    // Owner can delete
    await assertSucceeds(deleteDoc(bazarRef(db('owner'), MESS, '2026-11-15')));
  });
});
