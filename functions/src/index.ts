import * as admin from 'firebase-admin';

admin.initializeApp();

// ── Core scoring & content lifecycle ──────────────────────────────────────────
export { computeExplorerScore } from './computeExplorerScore';
export { decayFreshness } from './decayFreshness';
export { moderateContent } from './moderateContent';
export { maintainPinGeohash, backfillPinGeohashes } from './maintainPinGeohash';

// ── Chat: notifications, rate-limiting, media thumbnails ─────────────────────
export { sendChatNotification } from './sendChatNotification';
export { chatRateLimiter } from './chatRateLimiter';
export { generateChatThumbnail } from './generateChatThumbnail';

// ── Push Notifications ────────────────────────────────────────────────────────
export { sendGeneralNotification } from './sendGeneralNotification';
export { sendBroadcastNotification } from './sendBroadcastNotification';
export { sendSosAlert } from './sendSosAlert';

// ── Admin & Compliance ────────────────────────────────────────────────────────
export { promoteToRegionExpert } from './promoteToRegionExpert';
export { gdprDeleteUser } from './gdprDeleteUser';
export { retainData } from './retainData';
export { backupFirestore } from './backupFirestore';

// ── Auth: OTP generation and verification ─────────────────────────────────────
export { sendOtpEmail } from './sendOtpEmail';
export { verifyOtp } from './verifyOtp';
