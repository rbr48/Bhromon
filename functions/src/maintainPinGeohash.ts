import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import { encodeGeohash } from './lib/geohash';

const db = admin.firestore();

/**
 * The geohash a pin document should carry, or null when it has no valid
 * coordinates.
 */
export function expectedGeohash(data: admin.firestore.DocumentData | undefined): string | null {
  const lat = data?.lat;
  const lng = data?.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  try {
    return encodeGeohash(lat, lng);
  } catch {
    return null;
  }
}

/**
 * Keeps location_pins/{pinId}.geoHash in step with lat/lng, so the app can
 * find pins near a point with geohash range queries instead of reading every
 * pin. Writes only when the stored value is wrong, so its own update doesn't
 * trigger another write.
 */
export const maintainPinGeohash = functions
  .region('asia-south1')
  .firestore.document('location_pins/{pinId}')
  .onWrite(async (change) => {
    if (!change.after.exists) return;
    const data = change.after.data();
    const geoHash = expectedGeohash(data);
    if (geoHash === null || data?.geoHash === geoHash) return;
    await change.after.ref.update({ geoHash });
  });

/** Pages per call; 400 pins each. */
const MAX_PAGES = 25;
const PAGE_SIZE = 400;

/**
 * Sets geoHash on existing pins (pins written before maintainPinGeohash).
 * Pioneers only. Pages by document id; call again with `startAfter` set to
 * the returned `next` until it comes back null.
 */
export async function runBackfill(startAfter: string | null) {
  let cursor = startAfter;
  let scanned = 0;
  let updated = 0;
  for (let page = 0; page < MAX_PAGES; page++) {
    let query = db.collection('location_pins')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();
    if (snap.empty) return { scanned, updated, next: null };

    const batch = db.batch();
    let writes = 0;
    for (const doc of snap.docs) {
      const geoHash = expectedGeohash(doc.data());
      if (geoHash !== null && doc.data().geoHash !== geoHash) {
        batch.update(doc.ref, { geoHash });
        writes++;
      }
    }
    if (writes > 0) await batch.commit();
    scanned += snap.size;
    updated += writes;
    cursor = snap.docs[snap.docs.length - 1].id;
    if (snap.size < PAGE_SIZE) return { scanned, updated, next: null };
  }
  return { scanned, updated, next: cursor };
}

export const backfillPinGeohashes = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
    }
    const caller = await db.collection('explorer_profiles').doc(context.auth.uid).get();
    if (caller.data()?.tier !== 'pioneer') {
      throw new functions.https.HttpsError('permission-denied', 'Only pioneers can run the backfill');
    }
    const startAfter = typeof data?.startAfter === 'string' ? data.startAfter : null;
    return runBackfill(startAfter);
  });
