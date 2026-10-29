import * as admin from 'firebase-admin';

/** How long a call rings before it is dead. The app's ring timeout matches this. */
export const CALL_RING_SECONDS = 45;

/** A call document that is older than this when the function sees it is not rung. */
const STALE_CALL_MS = 60_000;

/** A caller may start this many calls per window. Further calls are ended without a push. */
export const CALLS_PER_WINDOW = 10;
export const CALL_WINDOW_MS = 10 * 60_000;

const FALLBACK_CALLER_NAME = 'A traveler';

export interface CallPushInput {
  callId: string;
  callerId: string;
  callerName: string;
  isVideo: boolean;
}

/**
 * The message that rings the callee.
 *
 * Android gets a data-only message, so the app's background handler receives it
 * and shows the incoming call itself. A `notification` block would show a plain
 * alert, and the call would never ring. iOS gets a visible alert as a fallback,
 * because CallKit on iOS needs a VoIP push that this server does not send.
 */
export function buildCallPushMessage(
  input: CallPushInput,
  nowMs: number,
): Omit<admin.messaging.MulticastMessage, 'tokens'> {
  const kind = input.isVideo ? 'Video' : 'Voice';
  return {
    data: {
      action: 'call',
      callId: input.callId,
      callerId: input.callerId,
      callerName: input.callerName,
      isVideo: String(input.isVideo),
    },
    android: {
      priority: 'high',
      ttl: CALL_RING_SECONDS * 1000,
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-expiration': String(Math.floor(nowMs / 1000) + CALL_RING_SECONDS),
      },
      payload: {
        aps: {
          alert: {
            title: `Incoming ${kind} Call`,
            body: `${input.callerName} is calling you on Bhromon...`,
          },
          sound: 'default',
          contentAvailable: true,
        },
      },
    },
  };
}

/** The caller's name from the server's profile record. Anything the client sent is ignored. */
export function callerDisplayName(displayName: unknown): string {
  if (typeof displayName !== 'string') return FALLBACK_CALLER_NAME;
  const name = displayName.trim().slice(0, 60);
  return name === '' ? FALLBACK_CALLER_NAME : name;
}

export function isStaleCall(createdAtMs: number, nowMs: number): boolean {
  return nowMs - createdAtMs > STALE_CALL_MS;
}

export function isOverCallLimit(recentCount: number): boolean {
  return recentCount > CALLS_PER_WINDOW;
}

/** How many calls this caller started since `sinceMs`, counting at most one more than the limit. */
export async function recentCallCount(
  db: admin.firestore.Firestore,
  callerId: string,
  sinceMs: number,
): Promise<number> {
  const snap = await db
    .collection('calls')
    .where('callerId', '==', callerId)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromMillis(sinceMs))
    .limit(CALLS_PER_WINDOW + 1)
    .get();
  return snap.size;
}
