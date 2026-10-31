/**
 * Bhromon Online Games Microservice.
 *
 * Runs the 12 server-side Card 29, Teen Patti, and Carrom callables on the Hostinger VPS,
 * bypassing Firebase Cloud Functions and enabling 100% free operation on the
 * Firebase Spark plan.
 */

import * as fs from 'fs';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { DecodedIdToken, getAuth } from 'firebase-admin/auth';
import express, { Request, Response } from 'express';
import cors from 'cors';
import { card29Start, card29Act, card29Advance, card29Leave } from './card29/callables';
import { teenPattiStart, teenPattiAct, teenPattiAdvance, teenPattiLeave } from './teenPatti/callables';
import { carromStart, carromShoot, carromAdvance, carromLeave } from './carrom/callables';

// Initialize Firebase Admin SDK if not already initialized
if (!getApps().length) {
  const credPath = process.env.FIREBASE_CREDENTIALS || '/run/secrets/firebase-admin.json';
  if (fs.existsSync(credPath)) {
    initializeApp({
      credential: cert(credPath),
    });
  } else {
    initializeApp();
  }
}

export const app = express();
// Only the app's own web addresses may call the games from a browser. The app's native
// clients send no Origin header and are not affected.
const ALLOWED_ORIGINS = (
  process.env.CORS_ORIGINS ??
  'https://app.bhromon.fun,https://bhromon-ff801.web.app,https://bhromon-ff801.firebaseapp.com'
)
  .split(',')
  .map((origin) => origin.trim())
  .filter((origin) => origin !== '');
app.use(cors({ origin: ALLOWED_ORIGINS }));
app.use(express.json());

const callables: Record<string, any> = {
  card29Start,
  card29Act,
  card29Advance,
  card29Leave,
  teenPattiStart,
  teenPattiAct,
  teenPattiAdvance,
  teenPattiLeave,
  carromStart,
  carromShoot,
  carromAdvance,
  carromLeave,
};

const errorStatusMap: Record<string, number> = {
  'invalid-argument': 400,
  'failed-precondition': 400,
  'out-of-range': 400,
  'unauthenticated': 401,
  'permission-denied': 403,
  'not-found': 404,
  'already-exists': 409,
  'resource-exhausted': 429,
  'cancelled': 499,
  'data-loss': 500,
  'unknown': 500,
  'internal': 500,
  'unavailable': 503,
  'deadline-exceeded': 504,
};

app.get('/health', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'bhromon-games-server',
    callables: Object.keys(callables),
  });
});

app.post('/:name', async (req: Request, res: Response) => {
  const paramName = req.params.name;
  const name = Array.isArray(paramName) ? paramName[0] : paramName;
  const fn = callables[name];
  if (!fn || typeof fn.run !== 'function') {
    res.status(404).json({ error: { message: `Callable ${name} not found.`, status: 'NOT_FOUND' } });
    return;
  }

  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: { message: 'Sign in to play at the table.', status: 'UNAUTHENTICATED' } });
    return;
  }

  const idToken = authHeader.slice(7).trim();
  let decoded: DecodedIdToken;
  try {
    decoded = await getAuth().verifyIdToken(idToken);
  } catch (err: any) {
    res.status(401).json({ error: { message: 'Invalid or expired authentication token.', status: 'UNAUTHENTICATED' } });
    return;
  }

  let email = (decoded.email || '').trim().toLowerCase();
  if (!email && decoded.uid) {
    try {
      const userRecord = await getAuth().getUser(decoded.uid);
      email = (userRecord.email || '').trim().toLowerCase();
    } catch (e) {
      console.warn('Could not fetch user record for uid:', decoded.uid, e);
    }
  }

  const context = {
    auth: {
      uid: decoded.uid,
      token: {
        ...decoded,
        email: email || decoded.email,
      },
    },
  };

  const payload = req.body?.data !== undefined ? req.body.data : req.body;

  try {
    const result = await fn.run(payload, context);
    res.json({ result: result ?? null });
  } catch (err: any) {
    const rawCode = err.code ?? err.status ?? 'internal';
    const code = typeof rawCode === 'string' ? rawCode : String(rawCode);
    const message = err.message || 'An internal error occurred.';
    const httpStatus = errorStatusMap[code] || (typeof rawCode === 'number' && rawCode >= 400 && rawCode < 600 ? rawCode : 500);
    console.error(`Callable ${name} failed:`, err);
    res.status(httpStatus).json({
      error: {
        message,
        status: code.toUpperCase(),
      },
    });
  }
});

const port = process.env.PORT || 8000;
if (require.main === module) {
  app.listen(port, () => {
    console.log(`Bhromon Games Server listening on port ${port}`);
  });
}
