import * as functions from 'firebase-functions/v1';
import { Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { OTP_LOCK_MS, OTP_MAX_ATTEMPTS, digestsMatch, otpDigest, toMs } from './otp';

/** The code the emulator accepts, so local sign-in and sign-up work without email. */
export const EMULATOR_OTP_CODE = '777777';

export const MIN_PASSWORD_LENGTH = 6;
export const MAX_PASSWORD_LENGTH = 128;
export const MAX_DISPLAY_NAME_LENGTH = 60;

type UseOutcome = 'ok' | 'missing' | 'expired' | 'locked' | 'wrong' | 'wrong-locks';

/**
 * Spends one attempt at a 6-digit code in `otps/{email}`. A matching code is deleted;
 * a mismatch increments the attempt counter and locks out after [OTP_MAX_ATTEMPTS].
 */
export async function consumeOtpCode(
  db: Firestore,
  email: string,
  code: string,
): Promise<void> {
  const ref = db.collection('otps').doc(email);
  const nowMs = Date.now();
  const outcome = await db.runTransaction<UseOutcome>(async (tx: Transaction) => {
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
        lockedUntil: Timestamp.fromMillis(nowMs + OTP_LOCK_MS),
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

export interface ValidatedEmailOtpPasswordInput {
  email: string;
  otp: string;
  password: string;
}

export interface ValidatedSignUpInput extends ValidatedEmailOtpPasswordInput {
  displayName?: string;
}

/** Validates and normalizes common {email, otp, password} payloads. */
export function validateEmailOtpPassword(data: unknown): ValidatedEmailOtpPasswordInput {
  const raw = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const email = typeof raw.email === 'string' ? raw.email.trim().toLowerCase() : '';
  const otp = typeof raw.otp === 'string' ? raw.otp.trim() : '';
  const password = typeof raw.password === 'string' ? raw.password : '';

  if (!email || !email.includes('@')) {
    throw new functions.https.HttpsError('invalid-argument', 'Valid email address is required.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'A 6-digit verification code is required.',
    );
  }
  if (password.length < MIN_PASSWORD_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Password must be between ${MIN_PASSWORD_LENGTH} and ${MAX_PASSWORD_LENGTH} characters.`,
    );
  }

  return { email, otp, password };
}

/** Validates and normalizes Email + Password + 6-digit OTP registration payloads. */
export function validateSignUpInput(data: unknown): ValidatedSignUpInput {
  const base = validateEmailOtpPassword(data);
  const raw = (data && typeof data === 'object' ? data : {}) as Record<string, unknown>;
  const rawName = typeof raw.displayName === 'string' ? raw.displayName.trim() : '';
  const displayName = rawName ? rawName.slice(0, MAX_DISPLAY_NAME_LENGTH) : undefined;
  return { ...base, displayName };
}
