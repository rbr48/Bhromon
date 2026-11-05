// MFS (bKash / Nagad / Rocket / Upay) payment rules: expenses, transfers, settlements and the
// per-group TrxID registry. Runs against the Firestore emulator on port 8080:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/mfs_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, setDoc, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'mfs1';
const people = {
  owner: { uid: 'own', email: 'own@x.com' },
  admin: { uid: 'adm', email: 'adm@x.com' },
  member: { uid: 'mem', email: 'mem@x.com' },
  other: { uid: 'oth', email: 'oth@x.com' },
  outsider: { uid: 'eve', email: 'eve@x.com' },
};

// A bKash record that a member writes: unverified, ten-character TrxID.
const bkash = (overrides = {}) => ({
  provider: 'bkash',
  trxId: 'BKL890XYZ1',
  senderMaskedPhone: '017******12',
  receiverMaskedPhone: '019******34',
  feePaisa: 1850,
  feeAbsorbedByGroup: false,
  status: 'unverified',
  ...overrides,
});

describe('MFS payment rules', () => {
  let env;
  const db = (who) => env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Mess', ownerEmail: people.owner.email, ownerUid: people.owner.uid, preset: 'mess' });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${TOUR}__${email}`), { tourId: TOUR, email, role, status: 'active' });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      // A member's unverified bKash expense, and their unverified settlement with another member.
      await setDoc(doc(f, 'tours', TOUR, 'expenses', 'e-member'), {
        addedByEmail: people.member.email, amountPaisa: 50000, title: 'Rice', mfsInfo: bkash(),
      });
      await setDoc(doc(f, 'tours', TOUR, 'settlements', 's-member'), {
        tourId: TOUR, addedByEmail: people.member.email, fromMemberId: people.member.email,
        toMemberId: people.other.email, amountPaisa: 20000, mfsInfo: bkash(),
      });
    });
  });

  describe('expenses', () => {
    test('a member records their own payment as unverified', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e1'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea', mfsInfo: bkash(),
      }));
    });

    test('a member cannot record a payment already marked verified', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e2'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea',
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.member.uid }),
      }));
    });

    test('an admin can record a verified payment', async () => {
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'expenses', 'e3'), {
        addedByEmail: people.admin.email, amountPaisa: 2000, title: 'Tickets',
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      }));
    });

    test('a TrxID with the wrong length for bKash is refused', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e4'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea', mfsInfo: bkash({ trxId: 'BKL890XY' }),
      }));
    });

    test('a provider outside the supported list is refused', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e5'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea', mfsInfo: bkash({ provider: 'paypal' }),
      }));
    });

    test('MFS details may carry only the known fields', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e6'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea', mfsInfo: bkash({ amountPaisa: 1 }),
      }));
    });

    test('cash spending needs no TrxID and still records', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e7'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea',
        mfsInfo: { provider: 'cash', trxId: null, feePaisa: 0, feeAbsorbedByGroup: false, status: 'unverified' },
      }));
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e8'), {
        addedByEmail: people.member.email, amountPaisa: 1000, title: 'Tea',
      }));
    });

    test('a member cannot verify their own payment', async () => {
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e-member'), {
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.member.uid }),
      }));
    });

    test('an admin can verify a member payment', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR, 'expenses', 'e-member'), {
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      }));
    });

    test('a member cannot change a payment once an admin has verified it', async () => {
      await assertSucceeds(updateDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e-member'), { amountPaisa: 52000 }));
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR, 'expenses', 'e-member'), {
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      }));
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e-member'), { amountPaisa: 1000 }));
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e-member'), {
        mfsInfo: bkash({ trxId: 'BKL890XYZ2', status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      }));
    });

    test('an outsider cannot record a payment', async () => {
      const outsider = env.authenticatedContext('eve', { email: people.outsider.email, email_verified: true }).firestore();
      await assertFails(setDoc(doc(outsider, 'tours', TOUR, 'expenses', 'e9'), {
        addedByEmail: people.outsider.email, amountPaisa: 1000, title: 'Tea', mfsInfo: bkash(),
      }));
    });
  });

  describe('transfers', () => {
    test('a member cannot record a transfer already verified', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'transfers', 't1'), {
        addedByEmail: people.member.email, fromId: people.member.email, toId: people.other.email,
        amountPaisa: 1000, mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.member.uid }),
      }));
    });

    test('a transfer without MFS details still records as before', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'transfers', 't2'), {
        addedByEmail: people.member.email, fromId: people.member.email, toId: people.other.email, amountPaisa: 1000,
      }));
    });
  });

  describe('settlements', () => {
    test('a member records a settlement they took part in', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'settlements', 's1'), {
        tourId: TOUR, addedByEmail: people.member.email, fromMemberId: people.member.email,
        toMemberId: people.other.email, amountPaisa: 5000, mfsInfo: bkash(),
      }));
    });

    test('a member cannot record a settlement between two other people', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'settlements', 's2'), {
        tourId: TOUR, addedByEmail: people.member.email, fromMemberId: people.other.email,
        toMemberId: people.admin.email, amountPaisa: 5000, mfsInfo: bkash(),
      }));
    });

    test('an admin can record a settlement between any two members', async () => {
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'settlements', 's3'), {
        tourId: TOUR, addedByEmail: people.admin.email, fromMemberId: people.other.email,
        toMemberId: people.member.email, amountPaisa: 5000, mfsInfo: bkash(),
      }));
    });

    test('a member cannot mark their own settlement verified', async () => {
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'settlements', 's-member'), {
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.member.uid }),
      }));
    });

    test('a member can correct the notes on their own unverified settlement', async () => {
      await assertSucceeds(updateDoc(doc(db('member'), 'tours', TOUR, 'settlements', 's-member'), {
        notes: 'bKash, paid for rice',
      }));
    });

    test('an admin verifies a settlement', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR, 'settlements', 's-member'), {
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      }));
    });

    test('a member cannot change a settlement once an admin has verified it', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR, 'settlements', 's-member'), {
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      }));
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'settlements', 's-member'), {
        notes: 'changed after verification',
      }));
    });

    test('an author cannot delete a settlement once it is verified', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'tours', TOUR, 'settlements', 's-done'), {
          tourId: TOUR, addedByEmail: people.member.email, fromMemberId: people.member.email,
          toMemberId: people.other.email, amountPaisa: 900, mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid }),
        });
      });
      await assertFails(deleteDoc(doc(db('member'), 'tours', TOUR, 'settlements', 's-done')));
    });
  });

  describe('samity payments', () => {
    const SAM = 'sam-mfs';
    const CYCLE0 = '000';
    const id = `${CYCLE0}__${people.member.email}`;
    const payment = (extra = {}) => ({
      cycleKey: CYCLE0,
      email: people.member.email,
      amountTaka: 500,
      recordedByEmail: people.member.email,
      updatedAt: serverTimestamp(),
      ...extra,
    });

    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        const f = ctx.firestore();
        await setDoc(doc(f, 'tours', SAM), {
          name: 'Mohalla samity', kind: 'family', preset: 'samity',
          ownerEmail: people.owner.email, ownerUid: people.owner.uid,
          samity: { contributionTaka: 1000, startMonth: '2026-01', dueDay: 10, payoutOrder: [people.member.email, people.other.email] },
        });
        const membership = (email, role) =>
          setDoc(doc(f, 'memberships', `${SAM}__${email}`), { tourId: SAM, email, role, status: 'active', displayName: email });
        await membership(people.owner.email, 'owner');
        await membership(people.admin.email, 'admin');
        await membership(people.member.email, 'member');
      });
    });

    test('a member records a bKash payment as unverified', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', SAM, 'samity_payments', id), payment({ mfsInfo: bkash() })));
    });

    test('a member cannot record a payment already marked verified', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', SAM, 'samity_payments', id), payment({
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.member.uid }),
      })));
    });

    test('once an admin verifies a payment, the member cannot change it', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', SAM, 'samity_payments', id), payment({ mfsInfo: bkash() })));
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', SAM, 'samity_payments', id), payment({
        recordedByEmail: people.admin.email,
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      })));
      await assertFails(setDoc(doc(db('member'), 'tours', SAM, 'samity_payments', id), payment({
        amountTaka: 300,
        mfsInfo: bkash({ status: 'verified', verifiedByUserId: people.admin.uid, verifiedByName: 'Admin' }),
      })));
    });
  });

  describe('per-group TrxID registry', () => {
    const entry = (overrides = {}) => ({
      trxId: 'BKL890XYZ1', provider: 'bkash', recordType: 'expense', recordId: 'e-member',
      amountPaisa: 50000, addedByEmail: people.member.email, createdAt: serverTimestamp(), ...overrides,
    });

    test('a member registers the TrxID of their own payment', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'mfs_trx_registry', 'BKL890XYZ1'), entry()));
    });

    test('an entry must be stored under its own TrxID', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'mfs_trx_registry', 'OTHERTRX1'), entry()));
    });

    test('an entry cannot be rewritten', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'tours', TOUR, 'mfs_trx_registry', 'BKL890XYZ1'), entry());
      });
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'mfs_trx_registry', 'BKL890XYZ1'), { recordId: 'e-other' }));
    });

    test('an outsider cannot register a TrxID', async () => {
      const outsider = env.authenticatedContext('eve', { email: people.outsider.email, email_verified: true }).firestore();
      await assertFails(setDoc(doc(outsider, 'tours', TOUR, 'mfs_trx_registry', 'BKL890XYZ1'), entry({ addedByEmail: people.outsider.email })));
    });
  });
});
