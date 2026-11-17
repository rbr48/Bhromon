import * as functions from 'firebase-functions/v1';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import {
  EMULATOR_OTP_CODE,
  consumeOtpCode,
  validateSignUpInput,
} from './lib/otpStore';

export interface RegisterWithEmailOtpDeps {
  consumeOtp: (email: string, code: string) => Promise<void>;
  getUserByEmail: (email: string) => Promise<{ uid: string }>;
  createUser: (properties: {
    email: string;
    password: string;
    emailVerified: boolean;
    displayName?: string;
  }) => Promise<{ uid: string }>;
  emulator?: boolean;
}

/**
 * Verifies a 6-digit email OTP first, then creates a verified Firebase Auth
 * Email/Password account so no address can be squatted prior to email verification.
 */
export async function executeRegisterWithEmailOtp(
  deps: RegisterWithEmailOtpDeps,
  data: unknown,
): Promise<{ success: true; uid: string }> {
  const { email, otp, password, displayName } = validateSignUpInput(data);

  const acceptedByEmulator = deps.emulator === true && otp === EMULATOR_OTP_CODE;
  if (!acceptedByEmulator) {
    await deps.consumeOtp(email, otp);
  }

  let existingUser = false;
  try {
    await deps.getUserByEmail(email);
    existingUser = true;
  } catch (err: unknown) {
    const code = (err as { code?: string })?.code;
    if (code !== 'auth/user-not-found') {
      throw new functions.https.HttpsError(
        'internal',
        'Account lookup failed. Please try again.',
      );
    }
  }

  if (existingUser) {
    throw new functions.https.HttpsError(
      'already-exists',
      'An account with this email already exists. Please sign in instead.',
    );
  }

  try {
    const created = await deps.createUser({
      email,
      password,
      emailVerified: true,
      ...(displayName ? { displayName } : {}),
    });
    return { success: true, uid: created.uid };
  } catch (err: unknown) {
    const code = (err as { code?: string })?.code;
    if (code === 'auth/email-already-exists') {
      throw new functions.https.HttpsError(
        'already-exists',
        'An account with this email already exists. Please sign in instead.',
      );
    }
    if (code === 'auth/invalid-password' || code === 'auth/weak-password') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Password must be at least 6 characters.',
      );
    }
    throw new functions.https.HttpsError(
      'internal',
      'Could not create the account. Please try again.',
    );
  }
}

function productionDeps(): RegisterWithEmailOtpDeps {
  const db = getFirestore();
  const auth = getAuth();
  return {
    consumeOtp: (email, code) => consumeOtpCode(db, email, code),
    getUserByEmail: (email) => auth.getUserByEmail(email),
    createUser: (props) => auth.createUser(props),
    emulator: process.env.FUNCTIONS_EMULATOR === 'true',
  };
}

export const registerWithEmailOtp = functions
  .region('asia-south1')
  .https.onCall(async (data) => executeRegisterWithEmailOtp(productionDeps(), data));
