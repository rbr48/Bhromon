/**
 * One-off: sets geoHash on every existing location pin.
 *
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npm run backfill:geohashes
 *
 * Safe to re-run: pins already carrying the right geohash aren't written.
 * New and edited pins are kept current by the maintainPinGeohash trigger.
 */
import { getApps, initializeApp } from 'firebase-admin/app';

async function main() {
  if (getApps().length === 0) initializeApp();
  // Loaded after initializeApp: the module reads Firestore at import time.
  const { runBackfill } = await import('../maintainPinGeohash');
  let next: string | null = null;
  let scanned = 0;
  let updated = 0;
  do {
    const result: { scanned: number; updated: number; next: string | null } =
      await runBackfill(next);
    scanned += result.scanned;
    updated += result.updated;
    next = result.next;
    console.log(`scanned ${scanned}, updated ${updated}${next ? ' ...' : ''}`);
  } while (next);
  console.log('Backfill complete.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
