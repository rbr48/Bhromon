import * as admin from 'firebase-admin';

/** Firestore commits at most 500 writes per batch. */
export const MAX_BATCH_WRITES = 500;

/** FCM multicast / sendEach accept at most 500 messages per call. */
export const MAX_FCM_BATCH = 500;

/** Splits [items] into arrays of at most [size]. */
export function chunk<T>(items: readonly T[], size: number): T[][] {
  if (size <= 0) throw new Error('chunk size must be positive');
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

/**
 * Reads documents in parallel `getAll` calls of at most [size] refs each,
 * instead of one sequential `get()` per document.
 */
export async function getAllInChunks(
  db: admin.firestore.Firestore,
  refs: admin.firestore.DocumentReference[],
  size = 100,
): Promise<admin.firestore.DocumentSnapshot[]> {
  if (refs.length === 0) return [];
  const parts = await Promise.all(chunk(refs, size).map((part) => db.getAll(...part)));
  return parts.flat();
}

/**
 * Runs [query] repeatedly and passes each page to [apply] (which must make
 * the page's documents stop matching, e.g. delete or update them) until the
 * query comes back empty or [maxPages] pages were processed.
 *
 * Returns the number of documents handled. Each page is a separate batch,
 * so no single commit exceeds Firestore's write limit.
 */
export async function drainQuery(
  query: admin.firestore.Query,
  apply: (docs: admin.firestore.QueryDocumentSnapshot[]) => Promise<void>,
  { pageSize = 400, maxPages = 50 }: { pageSize?: number; maxPages?: number } = {},
): Promise<{ handled: number; exhausted: boolean }> {
  let handled = 0;
  for (let page = 0; page < maxPages; page++) {
    const snap = await query.limit(pageSize).get();
    if (snap.empty) return { handled, exhausted: true };
    await apply(snap.docs);
    handled += snap.size;
    if (snap.size < pageSize) return { handled, exhausted: true };
  }
  return { handled, exhausted: false };
}
