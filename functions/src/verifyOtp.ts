import * as functions from 'firebase-functions/v1';
import { App, cert, getApp, initializeApp } from 'firebase-admin/app';
import { UserRecord, getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import * as fs from 'fs';
import * as path from 'path';
import { randomBytes } from 'crypto';
import { digestsMatch, otpDigest } from './lib/otp';
import { EMULATOR_OTP_CODE, consumeOtpCode } from './lib/otpStore';

const db = getFirestore();

// Initialize secondary Firebase App instance for cryptographic custom token signing
let tokenSignerApp: App | null = null;
const serviceAccountPath = path.join(__dirname, '..', 'service-account.json');
if (fs.existsSync(serviceAccountPath)) {
  try {
    tokenSignerApp = getApp('tokenSigner');
  } catch (e) {
    try {
      const serviceAccount = require(serviceAccountPath);
      tokenSignerApp = initializeApp({
        credential: cert(serviceAccount),
      }, 'tokenSigner');
    } catch (initErr) {
      console.error('Failed to initialize tokenSignerApp:', initErr);
    }
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
      (emulator && code === EMULATOR_OTP_CODE) || (await isReviewCode(email, code));
    if (!accepted) await consumeOtpCode(db, email, code);

    // Get or Create Firebase Auth User
    let userRecord: UserRecord;
    try {
      userRecord = await getAuth().getUserByEmail(email);
    } catch (e: any) {
      if (e.code === 'auth/user-not-found') {
        // Create new user
        userRecord = await getAuth().createUser({
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
        // A password account for this address may have been made by someone who does not
        // own it. Its password is replaced and its sessions end, so only a code opens it.
        const hasPassword = userRecord.providerData.some((p) => p.providerId === 'password');
        userRecord = await getAuth().updateUser(userRecord.uid, {
          emailVerified: true,
          ...(hasPassword ? { password: randomBytes(32).toString('hex') } : {}),
        });
        if (hasPassword) await getAuth().revokeRefreshTokens(userRecord.uid);
      }
      const auth = tokenSignerApp ? getAuth(tokenSignerApp) : getAuth();
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
