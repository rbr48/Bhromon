import {
  OTP_CODES_PER_EMAIL_PER_HOUR,
  OTP_RESEND_MS,
  OTP_TTL_MS,
  decideIssue,
  digestsMatch,
  generateOtpCode,
  otpDigest,
  takeWindowSlot,
} from '../lib/otp';

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const NOW = 1_800_000_000_000;

describe('sign-in codes', () => {
  it('are six digits from a secure source, and keep leading zeros', () => {
    const codes = Array.from({ length: 300 }, () => generateOtpCode());
    for (const code of codes) expect(code).toMatch(/^\d{6}$/);
    expect(new Set(codes).size).toBeGreaterThan(200);
  });

  it('are stored as a digest bound to the email, never as the code', () => {
    const digest = otpDigest('a@x.com', '123456');
    expect(digest).toMatch(/^[0-9a-f]{64}$/);
    expect(digest).not.toContain('123456');
    expect(otpDigest('a@x.com', '123456')).toBe(digest);
    expect(otpDigest('b@x.com', '123456')).not.toBe(digest);
    expect(otpDigest('a@x.com', '123457')).not.toBe(digest);
  });

  it('compare digests in constant time, and refuse digests of different lengths', () => {
    const digest = otpDigest('a@x.com', '123456');
    expect(digestsMatch(digest, otpDigest('a@x.com', '123456'))).toBe(true);
    expect(digestsMatch(digest, otpDigest('a@x.com', '000000'))).toBe(false);
    expect(digestsMatch(digest, 'short')).toBe(false);
  });
});

describe('counting windows', () => {
  it('take a slot until the limit, then refuse until the hour is over', () => {
    let window: { windowStartMs?: number; count?: number } = {};
    for (let i = 0; i < 3; i++) {
      const slot = takeWindowSlot(window, NOW + i, 3);
      expect(slot.ok).toBe(true);
      if (slot.ok) window = slot.next;
    }
    expect(takeWindowSlot(window, NOW + 10, 3)).toEqual({ ok: false });
    expect(takeWindowSlot(window, NOW + HOUR, 3).ok).toBe(true);
  });
});

describe('deciding whether a new code may be sent', () => {
  it('sends the first code', () => {
    const decision = decideIssue({}, NOW);
    expect(decision.ok).toBe(true);
  });

  it('waits a minute between codes for the same email', () => {
    const current = { expiresAtMs: NOW + OTP_TTL_MS };
    expect(decideIssue(current, NOW)).toEqual({ ok: false, reason: 'resend' });
    expect(decideIssue({ expiresAtMs: NOW + OTP_TTL_MS - OTP_RESEND_MS - 1 }, NOW).ok).toBe(true);
  });

  it('refuses while the email is locked out, however old the lock is about to get', () => {
    expect(decideIssue({ lockedUntilMs: NOW + MINUTE }, NOW)).toEqual({ ok: false, reason: 'locked' });
    expect(decideIssue({ lockedUntilMs: NOW - MINUTE }, NOW).ok).toBe(true);
  });

  it('caps the codes an email gets in an hour, so guessing cannot restart with each code', () => {
    const full = { windowStartMs: NOW - MINUTE, count: OTP_CODES_PER_EMAIL_PER_HOUR };
    expect(decideIssue(full, NOW)).toEqual({ ok: false, reason: 'hourly' });
    expect(decideIssue(full, NOW + HOUR).ok).toBe(true);
  });

  it('counts the codes it sends in the window it returns', () => {
    const decision = decideIssue({ windowStartMs: NOW - MINUTE, count: 2 }, NOW);
    expect(decision).toEqual({ ok: true, window: { windowStartMs: NOW - MINUTE, count: 3 } });
  });
});
