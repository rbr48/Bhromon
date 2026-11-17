import * as functions from 'firebase-functions/v1';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import {
  EMULATOR_OTP_CODE,
  consumeOtpCode,
  validateEmailOtpPassword,
} from './lib/otpStore';

export interface ResetPasswordWithOtpDeps {
  consumeOtp: (email: string, code: string) => Promise<void>;
  getUserByEmail: (email: string) => Promise<{ uid: string; disabled?: boolean }>;
  updateUser: (
    uid: string,
    properties: { password: string; emailVerified: boolean },
  ) => Promise<{ uid: string }>;
  emulator?: boolean;
}

/**
 * Verifies a 6-digit email OTP first (preventing pre-OTP account enumeration),
 * then updates the Firebase Auth user's password and marks the email verified.
 */
export async function executeResetPasswordWithOtp(
  deps: ResetPasswordWithOtpDeps,
  data: unknown,
): Promise<{ success: true; uid: string }> {
  const { email, otp, password } = validateEmailOtpPassword(data);

  const acceptedByEmulator = deps.emulator === true && otp === EMULATOR_OTP_CODE;
  if (!acceptedByEmulator) {
    await deps.consumeOtp(email, otp);
  }

  let user: { uid: string; disabled?: boolean };
  try {
    user = await deps.getUserByEmail(email);
  } catch (err: unknown) {
    const code = (err as { code?: string })?.code;
    if (code === 'auth/user-not-found') {
      throw new functions.https.HttpsError(
        'not-found',
        'No account found for this email. Please create an account instead.',
      );
    }
    throw new functions.https.HttpsError(
      'internal',
      'Account lookup failed. Please try again.',
    );
  }

  if (user.disabled === true) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'This account has been disabled.',
    );
  }

  try {
    await deps.updateUser(user.uid, {
      password,
      emailVerified: true,
    });
    return { success: true, uid: user.uid };
  } catch (err: unknown) {
    const code = (err as { code?: string })?.code;
    if (code === 'auth/invalid-password' || code === 'auth/weak-password') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Password must be at least 6 characters.',
      );
    }
    throw new functions.https.HttpsError(
      'internal',
      'Could not reset the password. Please try again.',
    );
  }
}

function productionDeps(): ResetPasswordWithOtpDeps {
  const db = getFirestore();
  const auth = getAuth();
  return {
    consumeOtp: (email, code) => consumeOtpCode(db, email, code),
    getUserByEmail: (email) => auth.getUserByEmail(email),
    updateUser: (uid, props) => auth.updateUser(uid, props),
    emulator: process.env.FUNCTIONS_EMULATOR === 'true',
  };
}

export const resetPasswordWithOtp = functions
  .region('asia-south1')
  .https.onCall(async (data) => executeResetPasswordWithOtp(productionDeps(), data));
