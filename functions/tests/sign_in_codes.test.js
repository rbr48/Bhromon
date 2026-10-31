// Sign-in codes: no code without a mail provider, a minute between codes, a few codes an
// hour per email, a lockout after wrong guesses, and expired codes refused. Needs the
// Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/sign_in_codes"
const admin = require('firebase-admin');

const PROJECT_ID = 'bhromon-rules-test-project';
if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });

const otp = require('../src/lib/otp');
const { sendOtpEmail } = require('../src/sendOtpEmail');
const { verifyOtp } = require('../src/verifyOtp');

const EMAIL = 'ann@x.com';
const CODE = '123456';

describe('sign-in codes', () => {
  let db;

  beforeAll(() => {
    db = admin.firestore();
  });

  beforeEach(async () => {
    await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, {
      method: 'DELETE',
    });
    jest.restoreAllMocks();
    delete process.env.FUNCTIONS_EMULATOR;
  });

  afterAll(() => {
    delete process.env.FUNCTIONS_EMULATOR;
  });

  const send = (email = EMAIL) => sendOtpEmail.run({ email }, {});
  const verify = (code, email = EMAIL) => verifyOtp.run({ email, otp: code }, {});
  const rejection = (promise) => promise.then(
    () => {
      throw new Error('expected the call to be refused');
    },
    (error) => error,
  );

  test('no code goes out when no mail provider is set, outside the emulator', async () => {
    const error = await rejection(send());
    expect(error.code).toBe('failed-precondition');
    expect((await db.doc(`otps/${EMAIL}`).get()).exists).toBe(false);
  });

  test('the code is stored as a digest, and a second code waits a minute', async () => {
    process.env.FUNCTIONS_EMULATOR = 'true';
    jest.spyOn(otp, 'generateOtpCode').mockReturnValue(CODE);

    await expect(send()).resolves.toMatchObject({ success: true });
    const stored = (await db.doc(`otps/${EMAIL}`).get()).data();
    expect(stored.digest).toBe(otp.otpDigest(EMAIL, CODE));
    expect(JSON.stringify(stored)).not.toContain(CODE);

    const error = await rejection(send());
    expect(error.code).toBe('resource-exhausted');
  });

  test('five wrong codes lock the email out, even when the right code comes next', async () => {
    process.env.FUNCTIONS_EMULATOR = 'true';
    jest.spyOn(otp, 'generateOtpCode').mockReturnValue(CODE);
    await send();

    for (let attempt = 1; attempt <= 4; attempt++) {
      expect((await rejection(verify('000000'))).code).toBe('permission-denied');
    }
    expect((await rejection(verify('000000'))).code).toBe('resource-exhausted');
    expect((await rejection(verify(CODE))).code).toBe('resource-exhausted');
    expect((await rejection(send())).code).toBe('resource-exhausted');
  });

  test('an expired code is refused and removed', async () => {
    await db.doc(`otps/${EMAIL}`).set({
      digest: otp.otpDigest(EMAIL, CODE),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
      attempts: 0,
    });
    expect((await rejection(verify(CODE))).code).toBe('failed-precondition');
    expect((await db.doc(`otps/${EMAIL}`).get()).exists).toBe(false);
  });

  test('a code that was never issued is refused', async () => {
    expect((await rejection(verify(CODE))).code).toBe('not-found');
  });

  test('an email gets only a few codes an hour, whatever the wait between them', async () => {
    const now = Date.now();
    await db.doc(`otps/${EMAIL}`).set({
      digest: otp.otpDigest(EMAIL, CODE),
      expiresAt: admin.firestore.Timestamp.fromMillis(now - 1000),
      attempts: 0,
      windowStart: admin.firestore.Timestamp.fromMillis(now - 60 * 1000),
      codesInWindow: otp.OTP_CODES_PER_EMAIL_PER_HOUR,
    });
    process.env.FUNCTIONS_EMULATOR = 'true';
    expect((await rejection(send())).code).toBe('resource-exhausted');
  });

  test('the whole service has a cost brake on codes in an hour', async () => {
    await db.doc('otp_limits/overall').set({
      windowStart: admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 1000),
      count: otp.OTP_CODES_PER_HOUR_OVERALL,
    });
    process.env.FUNCTIONS_EMULATOR = 'true';
    expect((await rejection(send())).code).toBe('resource-exhausted');
  });
});
