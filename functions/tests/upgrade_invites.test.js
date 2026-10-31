// Six-character invite codes move to eight-character ones, and the tour follows. Needs the
// Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/upgrade_invites"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
if (!getApps().length) initializeApp({ projectId: PROJECT_ID });

const { findLegacyInvites, upgradeLegacyInviteCodes, newInviteCode } = require('../scripts/upgradeLegacyInviteCodes');

describe('upgrading legacy invite codes', () => {
  let db;

  beforeAll(() => {
    db = getFirestore();
  });

  beforeEach(async () => {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    });
    await db.doc('tours/t1').set({ name: 'Sajek', ownerEmail: 'owner@x.com', inviteCode: 'OLD666' });
    await db.doc('invites/OLD666').set({ tourId: 't1', code: 'OLD666' });
    await db.doc('tours/t2').set({ name: 'Sylhet', ownerEmail: 'owner@x.com', inviteCode: 'NEWCODE1' });
    await db.doc('invites/NEWCODE1').set({ tourId: 't2', code: 'NEWCODE1' });
  }, 30000);

  test('a dry run finds the legacy codes and changes nothing', async () => {
    const result = await upgradeLegacyInviteCodes(db, { apply: false });
    expect(result).toEqual({ found: 1, moved: 0 });
    expect((await db.doc('invites/OLD666').get()).exists).toBe(true);
    expect((await db.doc('tours/t1').get()).get('inviteCode')).toBe('OLD666');
  });

  test('apply gives the tour an eight-character code and retires the old one', async () => {
    const result = await upgradeLegacyInviteCodes(db, { apply: true });
    expect(result).toEqual({ found: 1, moved: 1 });

    expect((await db.doc('invites/OLD666').get()).exists).toBe(false);
    const tour = (await db.doc('tours/t1').get()).data();
    expect(tour.inviteCode).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    const invite = await db.doc(`invites/${tour.inviteCode}`).get();
    expect(invite.get('tourId')).toBe('t1');
    expect(invite.get('code')).toBe(tour.inviteCode);

    expect((await db.doc('invites/NEWCODE1').get()).exists).toBe(true);
    expect(await findLegacyInvites(db)).toEqual([]);
  });

  test('new codes come from the app alphabet and are eight characters', () => {
    for (let i = 0; i < 50; i++) expect(newInviteCode()).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  });
});
