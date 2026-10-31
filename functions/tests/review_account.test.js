// The Play review account keeps only a digest of its code. The script and the sign-in
// function must agree on that digest. Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/review_account"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
if (!getApps().length) initializeApp({ projectId: PROJECT_ID });

const { otpDigest } = require('../src/lib/otp');
const { reviewDigest, setReviewAccount } = require('../scripts/setReviewAccount');

const CODE = 'a-long-random-review-code';

describe('the Play review account', () => {
  let db;

  beforeAll(() => {
    db = getFirestore();
  });

  beforeEach(async () => {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    });
  });

  test('the script and the sign-in function compute the same digest', () => {
    expect(reviewDigest('tester@bhromon.fun', CODE)).toBe(otpDigest('tester@bhromon.fun', CODE));
  });

  test('only the digest of the code is stored', async () => {
    await setReviewAccount(db, { email: 'Tester@Bhromon.fun', code: CODE });
    const stored = (await db.doc('config/auth').get()).data();

    expect(stored.reviewEmail).toBe('tester@bhromon.fun');
    expect(stored.reviewDigest).toBe(otpDigest('tester@bhromon.fun', CODE));
    expect(JSON.stringify(stored)).not.toContain(CODE);
  });

  test('a short code is refused', async () => {
    await expect(setReviewAccount(db, { email: 'tester@bhromon.fun', code: '123456' })).rejects.toThrow(/16/);
  });

  test('clearing the account removes it', async () => {
    await setReviewAccount(db, { email: 'tester@bhromon.fun', code: CODE });
    await setReviewAccount(db, { email: undefined });
    const stored = (await db.doc('config/auth').get()).data();
    expect(stored.reviewEmail).toBeUndefined();
    expect(stored.reviewDigest).toBeUndefined();
  });
});
