import { initializeApp } from 'firebase-admin/app';

initializeApp();

// ── Core scoring & content lifecycle ──────────────────────────────────────────
export { computeExplorerScore } from './computeExplorerScore';

// ── Chat: rate-limiting & media thumbnails (Notifications handled by VPS) ─────
export { chatRateLimiter } from './chatRateLimiter';
export { generateChatThumbnail } from './generateChatThumbnail';

// ── Push Notifications Note: ──────────────────────────────────────────────────
// All push notifications (Direct Chat, SOS alerts, Calls, Channels, Moments,
// Comments, Notices, Reminders, and Ledger) have been migrated to the Hostinger
// VPS Notification Engine (media-server:8210 / notifications.py).
// This eliminates duplicate ghost dispatches and keeps Bhromon 100% free on the
// Firebase Spark plan without incurring Cloud Functions compute billing.

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
