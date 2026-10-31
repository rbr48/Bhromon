import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as https from 'https';
import {
  OTP_CODES_PER_HOUR_OVERALL,
  OTP_TTL_MS,
  decideIssue,
  generateOtpCode,
  otpDigest,
  takeWindowSlot,
  toMs,
} from './lib/otp';

const db = admin.firestore();

type IssueOutcome = 'ok' | 'locked' | 'resend' | 'hourly' | 'overall';

interface AuthConfig {
  provider: string;
  resendApiKey: string;
  fromEmail: string;
}

async function readAuthConfig(): Promise<AuthConfig> {
  const data = (await db.collection('config').doc('auth').get()).data() ?? {};
  return {
    provider: typeof data.provider === 'string' ? data.provider : 'none',
    resendApiKey: typeof data.resendApiKey === 'string' ? data.resendApiKey : '',
    fromEmail:
      typeof data.fromEmail === 'string' ? data.fromEmail : 'Bhromon Auth <noreply@bhromon.fun>',
  };
}

export const sendOtpEmail = functions
  .region('asia-south1')
  .https.onCall(async (data) => {
    const email = typeof data?.email === 'string' ? data.email.trim().toLowerCase() : '';
    if (!email || !email.includes('@')) {
      throw new functions.https.HttpsError('invalid-argument', 'Valid email address is required');
    }

    // Without a mail provider, a code could only be read from the logs. Production refuses
    // instead. The emulator has no mail, so it stores the code and carries on.
    const config = await readAuthConfig();
    const emulator = process.env.FUNCTIONS_EMULATOR === 'true';
    const configured = config.provider === 'resend' && config.resendApiKey !== '';
    if (!configured && !emulator) {
      throw new functions.https.HttpsError('failed-precondition', 'Email sign-in is not set up yet.');
    }

    const code = generateOtpCode();
    const nowMs = Date.now();
    const outcome = await db.runTransaction<IssueOutcome>(async (tx) => {
      const otpRef = db.collection('otps').doc(email);
      const overallRef = db.collection('otp_limits').doc('overall');
      const [otpSnap, overallSnap] = await Promise.all([tx.get(otpRef), tx.get(overallRef)]);

      const existing = otpSnap.data() ?? {};
      const decision = decideIssue(
        {
          expiresAtMs: toMs(existing.expiresAt),
          lockedUntilMs: toMs(existing.lockedUntil),
          windowStartMs: toMs(existing.windowStart),
          count: typeof existing.codesInWindow === 'number' ? existing.codesInWindow : 0,
        },
        nowMs,
      );
      if (!decision.ok) return decision.reason;

      const overall = overallSnap.data() ?? {};
      const slot = takeWindowSlot(
        { windowStartMs: toMs(overall.windowStart), count: overall.count },
        nowMs,
        OTP_CODES_PER_HOUR_OVERALL,
      );
      if (!slot.ok) return 'overall';

      tx.set(otpRef, {
        digest: otpDigest(email, code),
        expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + OTP_TTL_MS),
        attempts: 0,
        windowStart: admin.firestore.Timestamp.fromMillis(decision.window.windowStartMs),
        codesInWindow: decision.window.count,
      });
      tx.set(overallRef, {
        windowStart: admin.firestore.Timestamp.fromMillis(slot.next.windowStartMs),
        count: slot.next.count,
      });
      return 'ok';
    });

    if (outcome === 'locked') {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Too many wrong codes. Wait 15 minutes, then ask for a new code.',
      );
    }
    if (outcome === 'resend') {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Please wait 60 seconds before requesting a new verification code.',
      );
    }
    if (outcome === 'hourly') {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Too many codes were sent to this address this hour. Try again later.',
      );
    }
    if (outcome === 'overall') {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Sign-in codes are busy right now. Try again in a few minutes.',
      );
    }

    if (configured) {
      try {
        await sendViaResend(config.resendApiKey, config.fromEmail, email, code);
      } catch (error) {
        // The provider's answer is logged without the code.
        console.error('Error sending the sign-in code via Resend:', (error as Error).message);
        throw new functions.https.HttpsError(
          'internal',
          'Could not send the verification code. Please try again.',
        );
      }
    } else {
      console.log('[Bhromon Auth] Emulator: no email sent. Use the emulator sign-in code.');
    }

    return { success: true, message: 'Verification code sent.' };
  });

function sendViaResend(apiKey: string, from: string, to: string, otp: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      from: from,
      to: [to],
      subject: 'Bhromon Login Verification Code',
      html: `
        <div style="font-family: sans-serif; padding: 24px; max-width: 480px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 12px; background-color: #ffffff;">
          <h2 style="color: #1b4332; margin-top: 0;">Bhromon Verification</h2>
          <p style="color: #4a4a4a; font-size: 14px; line-height: 1.5;">
            Use the following 6-digit verification code to log in to your account. This code is valid for 5 minutes.
          </p>
          <div style="font-size: 32px; font-weight: bold; color: #1b4332; text-align: center; letter-spacing: 4px; padding: 16px; margin: 24px 0; background-color: #f4f9f4; border-radius: 8px;">
            ${otp}
          </div>
          <p style="color: #999999; font-size: 11px; text-align: center;">
            If you did not request this code, please ignore this email.
          </p>
        </div>
      `
    });

    const options = {
      hostname: 'api.resend.com',
      port: 443,
      path: '/emails',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(data),
      }
    };

    const req = https.request(options, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => {
        responseBody += chunk;
      });
      res.on('end', () => {
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else {
          reject(new Error(`Resend responded with status ${res.statusCode}: ${responseBody}`));
        }
      });
    });

    req.on('error', (e) => {
      reject(e);
    });

    req.write(data);
    req.end();
  });
}
