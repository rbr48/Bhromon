// Closing an account takes the person out of their tours. Needs the Firestore
// emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/account_tours"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { leaveAllTours } = require('../src/lib/accountTours');

const PROJECT_ID = 'bhromon-rules-test-project';

describe('closing an account leaves its tours', () => {
  let db;

  beforeAll(() => {
    if (!getApps().length) initializeApp({ projectId: PROJECT_ID });
    db = getFirestore();
  });

  beforeEach(async () => {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    });
  });

  const row = (tourId, email, uid, role, joinedAt) =>
    db.doc(`memberships/${tourId}__${email}`).set({
      tourId,
      email,
      uid,
      role,
      status: 'active',
      joinedAt: new Date(joinedAt),
    });

  test('a tour the person owns passes to its earliest admin', async () => {
    await db.doc('tours/a').set({ name: 'Sajek', ownerEmail: 'owner@x.com', ownerUid: 'uid-owner', inviteCode: 'AAAAAAAA' });
    await row('a', 'owner@x.com', 'uid-owner', 'owner', '2026-01-01');
    await row('a', 'bob@x.com', 'uid-bob', 'member', '2026-01-02');
    await row('a', 'ann@x.com', 'uid-ann', 'admin', '2026-01-05');

    await leaveAllTours(db, 'Owner@X.com');

    const tour = (await db.doc('tours/a').get()).data();
    expect(tour.ownerEmail).toBe('ann@x.com');
    expect(tour.ownerUid).toBe('uid-ann');
    expect((await db.doc('memberships/a__ann@x.com').get()).data().role).toBe('owner');
    expect((await db.doc('memberships/a__owner@x.com').get()).exists).toBe(false);
    // Everyone else in the tour is left as they were.
    expect((await db.doc('memberships/a__bob@x.com').get()).data().role).toBe('member');
  });

  test('a tour with nobody else in it is deleted with the account', async () => {
    await db.doc('tours/b').set({ name: 'Family', ownerEmail: 'owner@x.com', ownerUid: 'uid-owner', inviteCode: 'BBBBBBBB' });
    await row('b', 'owner@x.com', 'uid-owner', 'owner', '2026-01-01');

    await leaveAllTours(db, 'owner@x.com');

    expect((await db.doc('tours/b').get()).exists).toBe(false);
  });

  test('a tour someone else owns only loses the person\'s row', async () => {
    await db.doc('tours/c').set({ name: 'Sylhet', ownerEmail: 'carol@x.com', ownerUid: 'uid-carol', inviteCode: 'CCCCCCCC' });
    await row('c', 'carol@x.com', 'uid-carol', 'owner', '2026-01-01');
    await row('c', 'owner@x.com', 'uid-owner', 'member', '2026-01-03');

    await leaveAllTours(db, 'owner@x.com');

    expect((await db.doc('tours/c').get()).data().ownerEmail).toBe('carol@x.com');
    expect((await db.doc('memberships/c__owner@x.com').get()).exists).toBe(false);
    expect((await db.doc('memberships/c__carol@x.com').get()).data().role).toBe('owner');
  });

  test('a person with no tours closes cleanly', async () => {
    await expect(leaveAllTours(db, 'nobody@x.com')).resolves.toBeUndefined();
  });
});
