import {
  buildCallPushMessage,
  callerDisplayName,
  CALL_RING_SECONDS,
  CALLS_PER_WINDOW,
  isOverCallLimit,
  isStaleCall,
} from '../lib/callPush';

const input = { callId: 'c1', callerId: 'u-caller', callerName: 'Rahim', isVideo: true };

describe('buildCallPushMessage', () => {
  it('is data-only, so the app rings instead of the system showing a plain alert', () => {
    const message = buildCallPushMessage(input, 1_000_000);
    expect(message.notification).toBeUndefined();
    expect(message.data).toEqual({
      action: 'call',
      callId: 'c1',
      callerId: 'u-caller',
      callerName: 'Rahim',
      isVideo: 'true',
    });
  });

  it('keeps the ring high priority and lets it expire with the ring timeout', () => {
    const message = buildCallPushMessage({ ...input, isVideo: false }, 1_000_000);
    expect(message.android).toEqual({ priority: 'high', ttl: CALL_RING_SECONDS * 1000 });
    expect(message.data?.isVideo).toBe('false');
  });

  it('gives iOS a visible fallback and an expiry in seconds', () => {
    const message = buildCallPushMessage(input, 1_000_000);
    const apns = message.apns as any;
    expect(apns.headers['apns-priority']).toBe('10');
    expect(apns.headers['apns-expiration']).toBe(String(1000 + CALL_RING_SECONDS));
    expect(apns.payload.aps.alert.title).toBe('Incoming Video Call');
    expect(apns.payload.aps.alert.body).toBe('Rahim is calling you on Bhromon...');
    expect(apns.payload.aps.contentAvailable).toBe(true);
  });

  it('names a voice call as one', () => {
    const apns = buildCallPushMessage({ ...input, isVideo: false }, 0).apns as any;
    expect(apns.payload.aps.alert.title).toBe('Incoming Voice Call');
  });
});

describe('callerDisplayName', () => {
  it('trims the name and keeps it short', () => {
    expect(callerDisplayName('  Rahim  ')).toBe('Rahim');
    expect(callerDisplayName('x'.repeat(100))).toHaveLength(60);
  });

  it('falls back for a missing, blank or non-text name', () => {
    expect(callerDisplayName(undefined)).toBe('A traveler');
    expect(callerDisplayName('   ')).toBe('A traveler');
    expect(callerDisplayName(42)).toBe('A traveler');
  });
});

describe('call freshness and limits', () => {
  it('treats a call older than a minute as stale', () => {
    expect(isStaleCall(0, 60_000)).toBe(false);
    expect(isStaleCall(0, 60_001)).toBe(true);
  });

  it('allows the limit, and refuses the call after it', () => {
    expect(isOverCallLimit(CALLS_PER_WINDOW)).toBe(false);
    expect(isOverCallLimit(CALLS_PER_WINDOW + 1)).toBe(true);
  });
});
