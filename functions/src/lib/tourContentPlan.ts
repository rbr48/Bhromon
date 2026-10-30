import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

/** An email as the app stores it: trimmed and lower case. */
export function normalizeEmail(value: unknown): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

/** Whether a document path lies inside the tour [tourId]. */
export function isInTour(docPath: string, tourId: string): boolean {
  return docPath.startsWith(`tours/${tourId}/`);
}

/** A document's data as Firestore returns it. */
export type Data = Record<string, unknown>;

function isPlainObject(value: unknown): value is Data {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** One change that takes a person out of a shared field of a document. */
export type Scrub =
  | { kind: 'arrayRemove'; field: string; value: string }
  | { kind: 'deleteKey'; path: string[] };

/**
 * The shared fields that can name a person: the likes, viewers, mentions and
 * tags lists, the reaction and vote maps keyed by email, and a story poll's
 * votes. Each is checked with the same email comparison the app uses.
 */
const LIST_FIELDS = ['likes', 'viewers', 'mentions', 'tags'];
const MAP_PATHS: string[][] = [['reactions'], ['votes'], ['poll', 'votes']];

function readPath(data: Data, path: string[]): unknown {
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
export function scrubsFor(data: Data, email: string): Scrub[] {
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

// ---------------------------------------------------------------------------
// Records that stay. The ledger, notices and route stops are the group's
// shared record, so they keep their amounts and dates. The person is replaced
// by a stand-in and their name by a neutral label, so the balances still add up.
// ---------------------------------------------------------------------------

/** The name shown for a person who has left, in records that stay. */
export const FORMER_MEMBER_NAME = 'সাবেক সদস্য';

/**
 * A stand-in for a person who has left, used in records that stay. It is the
 * same each time for the same person in the same tour, so their balance stays
 * one balance, and it is not their address.
 */
export function formerMemberId(tourId: string, email: string): string {
  const digest = crypto
    .createHash('sha256')
    .update(`${tourId}|${normalizeEmail(email)}`)
    .digest('hex');
  return `former-${digest.slice(0, 16)}`;
}

/** The fields one update writes, as Firestore's update takes them. */
export type Fields = admin.firestore.DocumentData;

/** What a document needs: removing it, or changing some of its fields. */
export type Decision =
  | { kind: 'delete'; recursive?: boolean }
  | { kind: 'update'; fields: Fields };

/**
 * Decides what one document needs from its data and id. Null leaves it alone.
 * Most rules read the data alone, so the id is optional for them.
 */
export type Decide = (data: Data, id?: string) => Decision | null;

/** Which fields of a record name the person, and how each one is replaced. */
export interface AnonymizePlan {
  /** Fields that hold the person's email. They take the stand-in. */
  emails?: string[];
  /** For an email field, the name field that takes the former-member label. */
  names?: Record<string, string>;
  /** Lists of emails: the person's entry takes the stand-in. */
  lists?: string[];
  /** Lists of emails: the person's entry is taken out. */
  removeFromLists?: string[];
  /** Maps keyed by email: the person's key takes the stand-in, value kept. */
  maps?: string[];
}

function listHas(value: unknown, email: string): value is unknown[] {
  return (
    Array.isArray(value) &&
    value.some((entry) => normalizeEmail(entry) === email)
  );
}

/**
 * Replaces the person in a record with [standIn], and their display names with
 * the former-member label. Amounts, counts and dates are left as they are.
 */
export function anonymize(
  plan: AnonymizePlan,
  email: string,
  standIn: string,
): Decide {
  return (data) => {
    const fields: Fields = {};

    for (const field of plan.emails ?? []) {
      if (normalizeEmail(data[field]) !== email) continue;
      fields[field] = standIn;
      const name = plan.names?.[field];
      if (name) fields[name] = FORMER_MEMBER_NAME;
    }

    for (const field of plan.lists ?? []) {
      const list = data[field];
      if (!listHas(list, email)) continue;
      const replaced = list.map((entry) =>
        normalizeEmail(entry) === email ? standIn : entry,
      );
      fields[field] = [...new Set(replaced)];
    }

    for (const field of plan.removeFromLists ?? []) {
      const list = data[field];
      if (!listHas(list, email)) continue;
      fields[field] = list.filter((entry) => normalizeEmail(entry) !== email);
    }

    for (const field of plan.maps ?? []) {
      const map = data[field];
      if (
        !isPlainObject(map) ||
        !Object.keys(map).some((key) => normalizeEmail(key) === email)
      ) {
        continue;
      }
      const next: Data = {};
      for (const [key, value] of Object.entries(map)) {
        next[normalizeEmail(key) === email ? standIn : key] = value;
      }
      fields[field] = next;
    }

    return Object.keys(fields).length > 0 ? { kind: 'update', fields } : null;
  };
}

// ---------------------------------------------------------------------------
// Records that go. What the person put into the tour for themselves is
// removed, and so is what only they can use.
// ---------------------------------------------------------------------------

/** Removes the document when [test] holds for it. */
export function deleteWhen(
  test: (data: Data, id: string) => boolean,
  recursive = false,
): Decide {
  return (data, id = '') => (test(data, id) ? { kind: 'delete', recursive } : null);
}

/** A document keyed by the person's email, or naming them as its email field. */
export function aboutPerson(email: string): Decide {
  return deleteWhen(
    (data, id) =>
      normalizeEmail(id) === email || normalizeEmail(data.email) === email,
  );
}

/** A member's profile in the tour: by their account id, or by their email. */
export function profileOf(email: string, uid: string | null): Decide {
  return deleteWhen(
    (data, id) =>
      (uid !== null && (data.uid === uid || id === uid)) ||
      normalizeEmail(data.email) === email ||
      normalizeEmail(id) === email,
  );
}

/** A safety alert the person raised goes. One they resolved keeps the stand-in. */
export function sosOf(email: string, standIn: string): Decide {
  const resolved = anonymize({ emails: ['resolvedByEmail'] }, email, standIn);
  return (data, id) =>
    normalizeEmail(data.senderEmail) === email
      ? { kind: 'delete' }
      : resolved(data, id);
}

/** A seat the person holds in a bus or vehicle is freed by removing the seat. */
export function seatHeldBy(email: string): Decide {
  return deleteWhen((data) => normalizeEmail(data.assignedMemberEmail) === email);
}

/** Luggage the person owns goes. Where they were the custodian, the custody is cleared. */
export function luggageOf(email: string): Decide {
  return (data) => {
    if (normalizeEmail(data.ownerEmail) === email) return { kind: 'delete' };
    if (normalizeEmail(data.custodianEmail) === email) {
      return {
        kind: 'update',
        fields: { custodianEmail: null, custodianName: null },
      };
    }
    return null;
  };
}

/**
 * Takes the person out of a hotel room's guest lists. The emails and the names
 * are index-aligned, so the same position is removed from both.
 */
export function leaveHotelRoom(email: string): Decide {
  return (data) => {
    const emails = data.assignedMemberEmails;
    if (!listHas(emails, email)) return null;
    const names = Array.isArray(data.assignedMemberNames)
      ? (data.assignedMemberNames as unknown[])
      : [];
    const keptEmails: unknown[] = [];
    const keptNames: unknown[] = [];
    emails.forEach((entry, index) => {
      if (normalizeEmail(entry) === email) return;
      keptEmails.push(entry);
      if (index < names.length) keptNames.push(names[index]);
    });
    return {
      kind: 'update',
      fields: {
        assignedMemberEmails: keptEmails,
        assignedMemberNames: keptNames,
      },
    };
  };
}

/** A game table the person hosts or sits at cannot go on without them, so it goes with its seats. */
export function gameInvolves(email: string): Decide {
  return deleteWhen(
    (data) =>
      normalizeEmail(data.hostEmail) === email ||
      (Array.isArray(data.players) &&
        data.players.some(
          (player) => isPlainObject(player) && normalizeEmail(player.email) === email,
        )),
    true,
  );
}

/** A voice signalling pair names the two members it joins, so a pair with the person goes. */
export function pairWith(email: string): Decide {
  return deleteWhen(
    (_data, id) => id.split('__').some((part) => normalizeEmail(part) === email),
    true,
  );
}
