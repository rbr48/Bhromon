import * as admin from 'firebase-admin';

/** An email as the app stores it: trimmed and lower case. */
export function normalizeEmail(value: unknown): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

/** Whether a document path lies inside the tour [tourId]. */
export function isInTour(docPath: string, tourId: string): boolean {
  return docPath.startsWith(`tours/${tourId}/`);
}

/** One change that takes a person out of a shared field of a document. */
export type Scrub =
  | { kind: 'arrayRemove'; field: string; value: string }
  | { kind: 'deleteKey'; path: string[] };

/**
 * The shared fields that can name a person: the likes and viewers lists, the
 * reaction and vote maps keyed by email, and a story poll's votes. Each is
 * checked with the same email comparison the app uses.
 */
const LIST_FIELDS = ['likes', 'viewers'];
const MAP_PATHS: string[][] = [['reactions'], ['votes'], ['poll', 'votes']];

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readPath(data: Record<string, unknown>, path: string[]): unknown {
  return path.reduce<unknown>(
    (node, key) => (isPlainObject(node) ? node[key] : undefined),
    data,
  );
}

/**
 * The changes that take [email] out of a document. Empty when the person does
 * not appear in any shared field, so the caller leaves that document alone.
 * Stored values are used as they are, so a list entry or map key is removed
 * exactly, even when it is not in the normalised form.
 */
export function scrubsFor(
  data: Record<string, unknown>,
  email: string,
): Scrub[] {
  const scrubs: Scrub[] = [];

  for (const field of LIST_FIELDS) {
    const list = data[field];
    if (!Array.isArray(list)) continue;
    const stored = new Set(
      list.filter(
        (entry): entry is string =>
          typeof entry === 'string' && normalizeEmail(entry) === email,
      ),
    );
    for (const value of stored) {
      scrubs.push({ kind: 'arrayRemove', field, value });
    }
  }

  for (const path of MAP_PATHS) {
    const map = readPath(data, path);
    if (!isPlainObject(map)) continue;
    for (const key of Object.keys(map)) {
      if (normalizeEmail(key) === email) {
        scrubs.push({ kind: 'deleteKey', path: [...path, key] });
      }
    }
  }

  return scrubs;
}

/**
 * The field arguments of one Firestore update that applies [scrubs]: a
 * (field, value) pair for each change. Map keys go in as field paths, so an
 * email's dots are never read as nesting.
 */
export function updateArgs(scrubs: Scrub[]): unknown[] {
  const args: unknown[] = [];
  for (const scrub of scrubs) {
    if (scrub.kind === 'arrayRemove') {
      args.push(
        scrub.field,
        admin.firestore.FieldValue.arrayRemove(scrub.value),
      );
    } else {
      args.push(
        new admin.firestore.FieldPath(...scrub.path),
        admin.firestore.FieldValue.delete(),
      );
    }
  }
  return args;
}
