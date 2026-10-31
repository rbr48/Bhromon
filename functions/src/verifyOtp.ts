import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as path from 'path';
import { OTP_LOCK_MS, OTP_MAX_ATTEMPTS, digestsMatch, otpDigest, toMs } from './lib/otp';

const db = admin.firestore();

// Initialize secondary Firebase App instance for cryptographic custom token signing
let tokenSignerApp: admin.app.App | null = null;
const serviceAccountPath = path.join(__dirname, '..', 'service-account.json');
if (fs.existsSync(serviceAccountPath)) {
  try {
    tokenSignerApp = admin.app('tokenSigner');
  } catch (e) {
    try {
      const serviceAccount = require(serviceAccountPath);
      tokenSignerApp = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      }, 'tokenSigner');
    } catch (initErr) {
      console.error('Failed to initialize tokenSignerApp:', initErr);
    }
  }
}

/** The code the emulator accepts, so local sign-in works without email. Only the emulator reads it. */
const EMULATOR_CODE = '777777';

type UseOutcome = 'ok' | 'missing' | 'expired' | 'locked' | 'wrong' | 'wrong-locks';

/**
 * Spends one attempt at a code. A right code is used up. A wrong one counts toward a
 * lockout. The decision is returned from the transaction and thrown after it, because
 * a thrown error would roll back the attempt that was just counted.
 */
async function useCode(email: string, code: string): Promise<void> {
  const ref = db.collection('otps').doc(email);
  const nowMs = Date.now();
  const outcome = await db.runTransaction<UseOutcome>(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return 'missing';
    const data = snap.data() ?? {};

    const lockedUntilMs = toMs(data.lockedUntil);
    if (lockedUntilMs !== undefined && lockedUntilMs > nowMs) return 'locked';

    const expiresAtMs = toMs(data.expiresAt);
    if (expiresAtMs !== undefined && expiresAtMs < nowMs) {
      tx.delete(ref);
      return 'expired';
    }

    if (typeof data.digest === 'string' && digestsMatch(otpDigest(email, code), data.digest)) {
      tx.delete(ref);
      return 'ok';
    }

    const attempts = (Number(data.attempts) || 0) + 1;
    if (attempts >= OTP_MAX_ATTEMPTS) {
      tx.update(ref, {
        attempts,
        lockedUntil: admin.firestore.Timestamp.fromMillis(nowMs + OTP_LOCK_MS),
      });
      return 'wrong-locks';
    }
    tx.update(ref, { attempts });
    return 'wrong';
  });

  switch (outcome) {
    case 'ok':
      return;
    case 'missing':
      throw new functions.https.HttpsError(
        'not-found',
        'No verification code found for this email. Please request a new one.',
      );
    case 'expired':
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Verification code has expired. Please request a new one.',
      );
    case 'locked':
    case 'wrong-locks':
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Too many wrong codes. Wait 15 minutes, then ask for a new code.',
      );
    case 'wrong':
      throw new functions.https.HttpsError(
        'permission-denied',
        'Invalid verification code. Please try again.',
      );
  }
}

/**
 * The Play review account signs in with a code the owner sets. Only its digest is
 * stored, in config/auth, by functions/scripts/setReviewAccount.js. No code lives in
 * the source.
 */
async function isReviewCode(email: string, code: string): Promise<boolean> {
  const config = (await db.collection('config').doc('auth').get()).data() ?? {};
  return (
    typeof config.reviewEmail === 'string' &&
    config.reviewEmail === email &&
    typeof config.reviewDigest === 'string' &&
    digestsMatch(otpDigest(email, code), config.reviewDigest)
  );
}

export const verifyOtp = functions
  .region('asia-south1')
  .https.onCall(async (data) => {
    const email = typeof data?.email === 'string' ? data.email.trim().toLowerCase() : '';
    const code = typeof data?.otp === 'string' ? data.otp.trim() : '';
    if (!email || !code) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Email and OTP verification code are required',
      );
    }

    const emulator = process.env.FUNCTIONS_EMULATOR === 'true';
    const accepted =
      (emulator && code === EMULATOR_CODE) || (await isReviewCode(email, code));
    if (!accepted) await useCode(email, code);

    // Get or Create Firebase Auth User
    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
    } catch (e: any) {
      if (e.code === 'auth/user-not-found') {
        // Create new user
        userRecord = await admin.auth().createUser({
          email,
          emailVerified: true,
        });
      } else {
        throw new functions.https.HttpsError(
          'internal',
          'Firebase Auth lookup failed. Please try again.',
        );
      }
    }

    // Generate Custom Token
    try {
      // The code went to this address and was accepted, so the address is verified now.
      // The Firestore and Storage rules trust only verified addresses, and an account made
      // before those rules may not be verified yet.
      if (!userRecord.emailVerified) {
        userRecord = await admin.auth().updateUser(userRecord.uid, { emailVerified: true });
      }
      const auth = tokenSignerApp ? tokenSignerApp.auth() : admin.auth();
      const customToken = await auth.createCustomToken(userRecord.uid, {
        email,
      });
      return { success: true, customToken: customToken };
    } catch (e: any) {
      throw new functions.https.HttpsError(
        'internal',
        'Could not start the sign-in session. Please try again.',
      );
    }
  });
