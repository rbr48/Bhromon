import { initializeApp } from 'firebase-admin/app';

initializeApp();

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
export { sendChannelNotification } from './sendChannelNotification';
export { sendTourPostNotification } from './sendTourPostNotification';
export { sendTourCommentNotification } from './sendTourCommentNotification';
export { sendTourReactionNotification } from './sendTourReactionNotification';
export { sendTourNoticeNotification } from './sendTourNoticeNotification';
export { sendTourNoticeReminders } from './sendTourNoticeReminders';
export { sendTourLedgerNotification } from './sendTourLedgerNotification';
export { sendCallPushNotification } from './sendCallPushNotification';

// ── Online 29 table (server-run game) ─────────────────────────────────────────
export { card29Start, card29Act, card29Advance, card29Leave } from './card29/callables';

// ── Online Teen Patti table (server-run game) ─────────────────────────────────
export { teenPattiStart, teenPattiAct, teenPattiAdvance, teenPattiLeave } from './teenPatti/callables';

// ── Online carrom board (server-run game) ─────────────────────────────────────
export { carromStart, carromShoot, carromAdvance, carromLeave } from './carrom/callables';

// ── Admin & Compliance ────────────────────────────────────────────────────────
export { promoteToRegionExpert } from './promoteToRegionExpert';
export { gdprDeleteUser } from './gdprDeleteUser';
export {
  onTourMembershipRemoved,
  onTourDeleted,
  retryTourPurgeJobs,
} from './tourContentPurge';
export { retainData } from './retainData';
export { backupFirestore } from './backupFirestore';

// ── Auth: OTP generation and verification ─────────────────────────────────────
export { sendOtpEmail } from './sendOtpEmail';
export { verifyOtp } from './verifyOtp';
