import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as path from 'path';
import * as fs from 'fs';

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

export const verifyOtp = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { email, otp } = data;
    if (!email || !otp) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Email and OTP verification code are required',
      );
    }

    const normalizedEmail = email.trim().toLowerCase();

    // Fetch the OTP document
    const otpDocRef = db.collection('otps').doc(normalizedEmail);
    const otpDoc = await otpDocRef.get();

    if (!otpDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'No verification code found for this email. Please request a new one.',
      );
    }

    const otpData = otpDoc.data();
    const serverOtp = otpData?.otp;
    const expiresAt = otpData?.expiresAt?.toDate();
    const attempts = otpData?.attempts || 0;

    // Check expiry
    if (expiresAt && expiresAt.getTime() < Date.now()) {
      await otpDocRef.delete();
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Verification code has expired. Please request a new one.',
      );
    }

    // Check attempts limit (max 3)
    if (attempts >= 3) {
      await otpDocRef.delete();
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Too many invalid attempts. Please request a new verification code.',
      );
    }

    // Verify OTP
    // Test account for Google Play store review and local emulator testing:
    const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true';
    const isTester = (isEmulator || normalizedEmail === 'tester@bhromon.fun') && otp === '777777';
    if (!isTester && serverOtp !== otp) {
      await otpDocRef.update({
        attempts: attempts + 1,
      });
      throw new functions.https.HttpsError(
        'permission-denied',
        'Invalid verification code. Please try again.',
      );
    }

    // OTP is valid - delete it
    await otpDocRef.delete();

    // Get or Create Firebase Auth User
    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(normalizedEmail);
    } catch (e: any) {
      if (e.code === 'auth/user-not-found') {
        // Create new user
        userRecord = await admin.auth().createUser({
          email: normalizedEmail,
          emailVerified: true,
        });
      } else {
        throw new functions.https.HttpsError(
          'internal',
          `Firebase Auth lookup failed: ${e.message || e}`,
        );
      }
    }

    // Generate Custom Token
    try {
      const auth = tokenSignerApp ? tokenSignerApp.auth() : admin.auth();
      const customToken = await auth.createCustomToken(userRecord.uid, {
        email: normalizedEmail,
      });
      return { success: true, customToken: customToken };
    } catch (e: any) {
      throw new functions.https.HttpsError(
        'internal',
        `Failed to generate custom token: ${e.message || e}`,
      );
    }
  });
