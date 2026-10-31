import * as crypto from 'crypto';

/** Digits in a sign-in code. */
export const OTP_DIGITS = 6;
/** How long a code can be used. */
export const OTP_TTL_MS = 5 * 60 * 1000;
/** How long a code may wait before the next one is sent to the same email. */
export const OTP_RESEND_MS = 60 * 1000;
/** Wrong codes allowed for one issued code before the email is locked out. */
export const OTP_MAX_ATTEMPTS = 5;
/** How long a locked-out email waits. */
export const OTP_LOCK_MS = 15 * 60 * 1000;
/** Codes one email may be sent in an hour. */
export const OTP_CODES_PER_EMAIL_PER_HOUR = 5;
/** Codes the whole service may send in an hour. A cost brake, not a fairness rule. */
export const OTP_CODES_PER_HOUR_OVERALL = 1000;

const HOUR_MS = 60 * 60 * 1000;

/** A fresh code from a cryptographically secure source. */
export function generateOtpCode(): string {
  return crypto.randomInt(0, 10 ** OTP_DIGITS).toString().padStart(OTP_DIGITS, '0');
}

/**
 * What is stored in place of a code: a digest bound to the email, so a copy of the
 * database does not hold usable codes.
 */
export function otpDigest(email: string, code: string): string {
  return crypto.createHash('sha256').update(`${email}\u0000${code}`).digest('hex');
}

/** Constant-time comparison of two digests. */
export function digestsMatch(a: string, b: string): boolean {
  const left = Buffer.from(a, 'utf8');
  const right = Buffer.from(b, 'utf8');
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

/** A Firestore timestamp as milliseconds, or undefined when the field is missing. */
export function toMs(value: unknown): number | undefined {
  if (value && typeof (value as { toMillis?: unknown }).toMillis === 'function') {
    return (value as { toMillis: () => number }).toMillis();
  }
  return undefined;
}

/** A counting window: when it began and how many were counted in it. */
export interface CountWindow {
  windowStartMs?: number;
  count?: number;
}

/**
 * Takes one slot from an hourly window. Refused when the window is full. A window
 * that began more than an hour ago starts again.
 */
export function takeWindowSlot(
  window: CountWindow,
  nowMs: number,
  limit: number,
): { ok: true; next: Required<CountWindow> } | { ok: false } {
  const open = window.windowStartMs !== undefined && nowMs - window.windowStartMs < HOUR_MS;
  const count = open ? window.count ?? 0 : 0;
  if (count >= limit) return { ok: false };
  return { ok: true, next: { windowStartMs: open ? window.windowStartMs! : nowMs, count: count + 1 } };
}

/** The state of one email's sign-in record that decides whether a new code may go out. */
export interface IssueState extends CountWindow {
  /** When the code now stored expires. */
  expiresAtMs?: number;
  /** When a lockout ends, if the email is locked out. */
  lockedUntilMs?: number;
}

export type IssueDecision =
  | { ok: true; window: Required<CountWindow> }
  | { ok: false; reason: 'locked' | 'resend' | 'hourly' };

/**
 * Whether a new code may be sent to this email now. A locked-out email gets nothing
 * until its lock ends. A code can be replaced only after a minute, and an email gets
 * a few codes an hour, so guessing cannot start over with each new code.
 */
export function decideIssue(state: IssueState, nowMs: number): IssueDecision {
  if (state.lockedUntilMs !== undefined && state.lockedUntilMs > nowMs) {
    return { ok: false, reason: 'locked' };
  }
  if (state.expiresAtMs !== undefined && state.expiresAtMs - nowMs > OTP_TTL_MS - OTP_RESEND_MS) {
    return { ok: false, reason: 'resend' };
  }
  const slot = takeWindowSlot(state, nowMs, OTP_CODES_PER_EMAIL_PER_HOUR);
  if (!slot.ok) return { ok: false, reason: 'hourly' };
  return { ok: true, window: slot.next };
}
