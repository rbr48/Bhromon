import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as https from 'https';

const db = admin.firestore();

export const sendOtpEmail = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { email } = data;
    if (!email || typeof email !== 'string' || !email.includes('@')) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Valid email address is required',
      );
    }

    const normalizedEmail = email.trim().toLowerCase();
    
    // Rate limit: check if an OTP was recently generated (within the last 60 seconds)
    const existingOtpDoc = await db.collection('otps').doc(normalizedEmail).get();
    if (existingOtpDoc.exists) {
      const existingOtpData = existingOtpDoc.data();
      const existingExpiresAt = existingOtpData?.expiresAt?.toDate();
      if (existingExpiresAt) {
        const timeRemainingMs = existingExpiresAt.getTime() - Date.now();
        const fourMinutesMs = 4 * 60 * 1000;
        if (timeRemainingMs > fourMinutesMs) {
          throw new functions.https.HttpsError(
            'resource-exhausted',
            'Please wait 60 seconds before requesting a new verification code.',
          );
        }
      }
    }

    // Generate a 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes

    // Save to Firestore /otps/{email}
    await db.collection('otps').doc(normalizedEmail).set({
      otp: otp,
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      attempts: 0,
    });

    console.log(`[Bhromon Auth] Generated OTP ${otp} for ${normalizedEmail}`);



    // Read config
    let provider = 'none';
    let resendApiKey = '';
    let fromEmail = 'Bhromon Auth <noreply@bhromon.fun>';

    try {
      const configDoc = await db.collection('config').doc('auth').get();
      if (configDoc.exists) {
        const configData = configDoc.data();
        provider = configData?.provider || 'none';
        resendApiKey = configData?.resendApiKey || '';
        fromEmail = configData?.fromEmail || fromEmail;
      }
    } catch (e) {
      console.warn('Could not read auth config, defaulting to sandbox mode:', e);
    }

    if (provider === 'resend' && resendApiKey) {
      try {
        await sendViaResend(resendApiKey, fromEmail, normalizedEmail, otp);
        console.log(`Successfully sent Resend email to ${normalizedEmail}`);
      } catch (err: any) {
        console.error('Error sending via Resend API:', err);
        throw new functions.https.HttpsError(
          'internal',
          `Failed to deliver email: ${err.message || err}`,
        );
      }
    } else {
      console.log(`[SANDBOX MODE] OTP is ${otp}. No email sent since provider is 'none' or unconfigured.`);
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
