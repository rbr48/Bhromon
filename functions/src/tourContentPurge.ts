import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as crypto from 'crypto';
import { purgeTourStorage } from './lib/tourStorage';
import {
  AnonymizePlan,
  Decide,
  aboutPerson,
  anonymize,
  formerMemberId,
  gameInvolves,
  isInTour,
  leaveHotelRoom,
  luggageOf,
  normalizeEmail,
  pairWith,
  profileOf,
  Scrub,
  scrubsFor,
  seatHeldBy,
  sosOf,
  updateArgs,
} from './lib/tourContentPlan';

/**
 * Permanent removal of tour content, on the server.
 *
 * - When a person leaves a tour, or the owner removes them, what they put
 *   into the tour is removed: their posts, stories, highlights, comments, chat
 *   messages, safety alerts, locations, luggage, seats and game tables, with
 *   their photos, videos and Storage files. They are also taken out of other
 *   people's likes, viewers, reactions, votes, mentions and tags.
 * - The group's shared record (the ledger, notices, route stops and the packing
 *   list) keeps its amounts and dates. The person is replaced by a stand-in.
 * - When a tour is deleted, everything in it is deleted.
 *
 * Each purge is written as a job before it starts and removed once it has
 * finished. A purge that fails, for example while the media server is down, is
 * retried by retryTourPurgeJobs until it succeeds or gives up after two days.
 */

type Db = admin.firestore.Firestore;
type Query = admin.firestore.Query;
type DocRef = admin.firestore.DocumentReference;
type DocSnap = admin.firestore.QueryDocumentSnapshot;

/**
 * Removes a person's photos and videos on the media server (or all of the
 * tour's, when the uploader is null). Returns the paths it removed, relative
 * to the tour's folder, so the receipts that pointed to them can be cleared.
 */
export type MediaPurge = (
  tourId: string,
  uploaderEmail: string | null,
) => Promise<string[]>;

/** Removes a person's files from the tour's Storage folder, or all of them when the uploader is null. */
export type StoragePurge = (
  tourId: string,
  uploaderEmail: string | null,
) => Promise<void>;

/** The outside services a purge reaches. Tests replace them with fakes. */
export interface PurgeDeps {
  purgeMedia: MediaPurge;
  purgeStorage: StoragePurge;
  resolveUid: (email: string) => Promise<string | null>;
}

export type PurgeJob =
  | { kind: 'member'; tourId: string; email: string; uid?: string | null }
  | { kind: 'tour'; tourId: string };

const JOBS = 'tour_purge_jobs';
const NOT_FOUND = 5;
/** Retries every 30 minutes for two days, then the job is marked failed. */
const MAX_ATTEMPTS = 96;
const REGION = 'asia-south1';
const RUNTIME = {
  timeoutSeconds: 540,
  memory: '512MB' as const,
  secrets: ['MEDIA_PURGE_KEY'],
};

const everywhere = (_path: string): boolean => true;

/**
 * How the group's shared record is anonymized: the person's identity is
 * replaced, and the amounts, counts and dates are kept.
 */
const LEDGER_EXPENSE: AnonymizePlan = {
  emails: ['addedByEmail', 'paidById'],
  names: { paidById: 'paidByName' },
  lists: ['participantIds'],
  maps: ['splitShares'],
};
const LEDGER_DEPOSIT: AnonymizePlan = {
  emails: ['addedByEmail', 'memberId'],
  names: { memberId: 'memberName' },
};
const LEDGER_TRANSFER: AnonymizePlan = {
  emails: ['addedByEmail', 'fromId', 'toId'],
  names: { fromId: 'fromName', toId: 'toName' },
};
const NOTICE: AnonymizePlan = {
  emails: ['authorEmail'],
  names: { authorEmail: 'author' },
  removeFromLists: ['ackBy'],
};
const CHECKPOINT: AnonymizePlan = { emails: ['addedByEmail'] };
const CHECKLIST_ITEM: AnonymizePlan = { removeFromLists: ['checkedBy'] };
const CHANNEL: AnonymizePlan = { emails: ['createdByEmail', 'updatedByEmail'] };
const PINNED_MESSAGE: AnonymizePlan = { emails: ['pinnedByEmail'] };
const ITINERARY_META: AnonymizePlan = { emails: ['updatedByEmail'] };

function isNotFound(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    (error as { code?: unknown }).code === NOT_FOUND
  );
}

/**
 * Batched writes. A document that is already gone is the outcome wanted, so it
 * is not a failure. Any other failure is raised by done().
 */
class Writes {
  private readonly writer: admin.firestore.BulkWriter;
  private readonly writes: Promise<void>[] = [];

  constructor(db: Db) {
    this.writer = db.bulkWriter();
    this.writer.onWriteError(
      (error) => error.code !== NOT_FOUND && error.failedAttempts < 5,
    );
  }

  delete(ref: DocRef): void {
    this.track(this.writer.delete(ref));
  }

  update(ref: DocRef, scrubs: Scrub[]): void {
    if (scrubs.length === 0) return;
    const args = updateArgs(scrubs);
    this.track(
      this.writer.update(
        ref,
        args[0] as string | admin.firestore.FieldPath,
        args[1],
        ...args.slice(2),
      ),
    );
  }

  private track(write: Promise<unknown>): void {
    this.writes.push(
      write.then(
        () => undefined,
        (error: unknown) => {
          if (!isNotFound(error)) throw error;
        },
      ),
    );
  }

  async done(): Promise<void> {
    await this.writer.close();
    await Promise.all(this.writes);
  }
}

/** The documents the queries find, once each, that are in scope. */
async function collect(
  queries: Query[],
  inScope: (path: string) => boolean,
): Promise<DocSnap[]> {
  const byPath = new Map<string, DocSnap>();
  for (const query of queries) {
    const snapshot = await query.get();
    for (const doc of snapshot.docs) {
      if (inScope(doc.ref.path)) byPath.set(doc.ref.path, doc);
    }
  }
  return [...byPath.values()];
}

async function deleteMatching(
  db: Db,
  queries: Query[],
  inScope: (path: string) => boolean,
  recursive: boolean,
): Promise<void> {
  const found = await collect(queries, inScope);
  if (recursive) {
    // Recursive delete also removes subcollections, such as a post's comments.
    for (const doc of found) await db.recursiveDelete(doc.ref);
    return;
  }
  const writes = new Writes(db);
  for (const doc of found) writes.delete(doc.ref);
  await writes.done();
}

async function scrubMatching(
  db: Db,
  email: string,
  queries: Query[],
  inScope: (path: string) => boolean,
): Promise<void> {
  const found = await collect(queries, inScope);
  const writes = new Writes(db);
  for (const doc of found) writes.update(doc.ref, scrubsFor(doc.data(), email));
  await writes.done();
}

async function deleteRefs(db: Db, refs: DocRef[]): Promise<void> {
  const writes = new Writes(db);
  for (const ref of refs) writes.delete(ref);
  await writes.done();
}

/**
 * Applies [decide] to each document, in a transaction, so a change made in the
 * meantime is read first. A recursive delete runs once its transaction is done.
 */
async function applyToDocs(
  db: Db,
  refs: DocRef[],
  decide: Decide,
): Promise<void> {
  for (const ref of refs) {
    const recursive = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const decision = decide(snap.data() ?? {}, snap.id);
      if (decision === null) return false;
      if (decision.kind === 'update') {
        tx.update(ref, decision.fields);
        return false;
      }
      if (decision.recursive) return true;
      tx.delete(ref);
      return false;
    });
    if (recursive) await db.recursiveDelete(ref);
  }
}

async function applyToQuery(db: Db, query: Query, decide: Decide): Promise<void> {
  const snapshot = await query.get();
  await applyToDocs(
    db,
    snapshot.docs.map((doc) => doc.ref),
    decide,
  );
}

/** Whether [email] holds a membership row in the tour, active or not. */
async function holdsMembership(db: Db, tourId: string, email: string): Promise<boolean> {
  const row = await db.collection('memberships').doc(`${tourId}__${email}`).get();
  return row.exists;
}

/**
 * Clears the receipt of each expense whose file was removed. The receipt URL
 * ends with the tour and the file's path inside the tour.
 */
async function clearReceipts(db: Db, tourId: string, removed: string[]): Promise<void> {
  if (removed.length === 0) return;
  const endings = removed.map((path) => `/${tourId}/${path}`);
  await applyToQuery(db, db.collection('tours').doc(tourId).collection('expenses'), (data) => {
    const url = typeof data.receiptUrl === 'string' ? data.receiptUrl : '';
    return endings.some((ending) => url.endsWith(ending))
      ? { kind: 'update', fields: { receiptUrl: null } }
      : null;
  });
}

/**
 * Removes everything [email] put into the tour [tourId], and their media.
 *
 * Nothing runs for a person who holds a membership again by the time this
 * runs: they rejoined, so what they post now is theirs, not a leftover.
 */
export async function purgeMemberContent(
  db: Db,
  tourId: string,
  email: string,
  deps: PurgeDeps,
  uid: string | null = null,
): Promise<void> {
  if (!email || (await holdsMembership(db, tourId, email))) return;
  const memberUid = uid ?? (await deps.resolveUid(email));
  const tour = db.collection('tours').doc(tourId);
  const inTour = (path: string): boolean => isInTour(path, tourId);
  // A map keyed by email, read as one field path so the dots are not nesting.
  const keyIs = (...path: string[]) =>
    new admin.firestore.FieldPath(...path, email);
  const standIn = formerMemberId(tourId, email);

  // Their own posts, with the comments under them.
  await deleteMatching(
    db,
    [tour.collection('posts').where('authorEmail', '==', email)],
    everywhere,
    true,
  );

  // Other people's posts: take them out of the likes, viewers and tags.
  await scrubMatching(
    db,
    email,
    [
      tour.collection('posts').where('likes', 'array-contains', email),
      tour.collection('posts').where('viewers', 'array-contains', email),
      tour.collection('posts').where('tags', 'array-contains', email),
    ],
    everywhere,
  );

  // Their comments in the tour, and their likes on other comments.
  const comments = db.collectionGroup('comments');
  await deleteMatching(
    db,
    [comments.where('authorEmail', '==', email)],
    inTour,
    false,
  );
  await scrubMatching(
    db,
    email,
    [comments.where('likes', 'array-contains', email)],
    inTour,
  );

  // Their stories, and their likes, views, reactions and poll votes elsewhere.
  const stories = tour.collection('stories');
  await deleteMatching(
    db,
    [stories.where('authorEmail', '==', email)],
    everywhere,
    true,
  );
  await scrubMatching(
    db,
    email,
    [
      stories.where('viewers', 'array-contains', email),
      stories.where(keyIs('reactions'), '!=', null),
      stories.where(keyIs('poll', 'votes'), '!=', null),
    ],
    everywhere,
  );

  // Highlights they made.
  await deleteMatching(
    db,
    [tour.collection('highlights').where('createdByEmail', '==', email)],
    everywhere,
    true,
  );

  // Their live presence, and their location, battery telemetry and legacy row.
  await deleteRefs(db, [tour.collection('presence').doc(email)]);
  for (const name of ['locations', 'telemetry', 'members']) {
    await applyToQuery(db, tour.collection(name), aboutPerson(email));
  }

  // Safety alerts they raised. An alert they resolved for someone else keeps the stand-in.
  await applyToQuery(db, tour.collection('sos'), sosOf(email, standIn));

  // The group's shared record keeps its amounts and dates. The person is
  // replaced by the stand-in, so the balances and the notices still read.
  await applyToQuery(db, tour.collection('expenses'), anonymize(LEDGER_EXPENSE, email, standIn));
  await applyToQuery(db, tour.collection('deposits'), anonymize(LEDGER_DEPOSIT, email, standIn));
  await applyToQuery(db, tour.collection('transfers'), anonymize(LEDGER_TRANSFER, email, standIn));
  await applyToQuery(db, tour.collection('notices'), anonymize(NOTICE, email, standIn));
  await applyToQuery(db, tour.collection('checkpoints'), anonymize(CHECKPOINT, email, standIn));
  await applyToQuery(db, tour.collection('checklist'), anonymize(CHECKLIST_ITEM, email, standIn));
  await applyToQuery(db, tour.collection('meta'), anonymize(ITINERARY_META, email, standIn));

  // What only the person used goes: luggage they own, seats and rooms they hold,
  // game tables they host or sit at, and their profile in the tour.
  await applyToQuery(db, tour.collection('luggage'), luggageOf(email));
  await applyToQuery(db, tour.collection('bus_seats'), seatHeldBy(email));
  await applyToQuery(db, tour.collection('vehicle_seats'), seatHeldBy(email));
  await applyToQuery(db, tour.collection('hotel_rooms'), leaveHotelRoom(email));
  await applyToQuery(db, tour.collection('games'), gameInvolves(email));
  await applyToQuery(db, tour.collection('profiles'), profileOf(email, memberUid));

  // Group chat: their messages, their reactions and votes, the mentions and tags
  // naming them, and their typing and voice presence in each channel.
  const channels = await tour.collection('channels').get();
  await applyToDocs(
    db,
    channels.docs.map((channel) => channel.ref),
    anonymize(CHANNEL, email, standIn),
  );
  for (const channel of channels.docs) {
    const messages = channel.ref.collection('messages');
    await deleteMatching(
      db,
      [messages.where('senderEmail', '==', email)],
      everywhere,
      false,
    );
    await scrubMatching(
      db,
      email,
      [
        messages.where(keyIs('reactions'), '!=', null),
        messages.where(keyIs('votes'), '!=', null),
        messages.where('mentions', 'array-contains', email),
      ],
      everywhere,
    );
    await applyToQuery(
      db,
      messages.where('pinnedByEmail', '==', email),
      anonymize(PINNED_MESSAGE, email, standIn),
    );
    await deleteRefs(db, [
      channel.ref.collection('typing').doc(email),
      channel.ref.collection('voice_participants').doc(email),
    ]);
    // Voice signalling between the person and another member.
    await applyToQuery(db, channel.ref.collection('voice_signals'), pairWith(email));
  }

  // Their files in the tour's Storage folder (uploads from before the media server).
  await deps.purgeStorage(tourId, email);

  // Their photos and videos on the media server, and the receipts that pointed to them.
  const removed = await deps.purgeMedia(tourId, email);
  await clearReceipts(db, tourId, removed);
}

/**
 * Removes a whole tour: everything under it, its memberships and invites, its
 * Storage files and its media.
 */
export async function purgeTour(db: Db, tourId: string, deps: PurgeDeps): Promise<void> {
  await db.recursiveDelete(db.collection('tours').doc(tourId));
  await deleteMatching(
    db,
    [db.collection('memberships').where('tourId', '==', tourId)],
    everywhere,
    false,
  );
  await deleteMatching(
    db,
    [db.collection('invites').where('tourId', '==', tourId)],
    everywhere,
    false,
  );
  await deps.purgeStorage(tourId, null);
  await deps.purgeMedia(tourId, null);
}

function jobRef(db: Db, job: PurgeJob): DocRef {
  // The email is hashed into the id, so no address is kept in a document name.
  const key =
    job.kind === 'member'
      ? `member_${crypto.createHash('sha256').update(job.email).digest('hex')}`
      : 'tour';
  return db.collection(JOBS).doc(`${job.tourId}__${key}`);
}

function jobFields(job: PurgeJob): Record<string, string | null> {
  // The job keeps the email while it is pending, so a retry can finish it. It
  // is deleted as soon as the purge succeeds.
  return job.kind === 'member'
    ? { kind: 'member', tourId: job.tourId, email: job.email, uid: job.uid ?? null }
    : { kind: 'tour', tourId: job.tourId };
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 300) : 'unknown error';
}

/** Runs one purge. On failure the job stays pending for retryPendingJobs. */
export async function runPurgeJob(db: Db, job: PurgeJob, deps: PurgeDeps): Promise<void> {
  const ref = jobRef(db, job);
  const now = admin.firestore.FieldValue.serverTimestamp();
  await ref.set({ ...jobFields(job), status: 'pending', updatedAt: now }, { merge: true });
  try {
    if (job.kind === 'member') {
      await purgeMemberContent(db, job.tourId, job.email, deps, job.uid ?? null);
    } else {
      await purgeTour(db, job.tourId, deps);
    }
    await ref.delete();
  } catch (error) {
    await ref.set(
      {
        status: 'pending',
        attempts: admin.firestore.FieldValue.increment(1),
        lastError: errorText(error),
        updatedAt: now,
      },
      { merge: true },
    );
    functions.logger.error('Tour content purge failed; it will be retried.', {
      tourId: job.tourId,
      kind: job.kind,
    });
  }
}

/** Retries purges that have not finished. A job past its last attempt is marked failed. */
export async function retryPendingJobs(db: Db, deps: PurgeDeps, limit = 50): Promise<void> {
  const pending = await db
    .collection(JOBS)
    .where('status', '==', 'pending')
    .limit(limit)
    .get();
  for (const doc of pending.docs) {
    const data = doc.data();
    const attempts = typeof data.attempts === 'number' ? data.attempts : 0;
    if (attempts >= MAX_ATTEMPTS) {
      await doc.ref.set(
        { status: 'failed', updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
      continue;
    }
    const tourId = typeof data.tourId === 'string' ? data.tourId : '';
    if (data.kind === 'member' && typeof data.email === 'string' && tourId) {
      const uid = typeof data.uid === 'string' && data.uid !== '' ? data.uid : null;
      await runPurgeJob(db, { kind: 'member', tourId, email: data.email, uid }, deps);
    } else if (data.kind === 'tour' && tourId) {
      await runPurgeJob(db, { kind: 'tour', tourId }, deps);
    }
  }
}

/** The media server's purge route. The back end calls it with the purge key. */
const MEDIA_PURGE_URL =
  process.env.MEDIA_PURGE_URL ?? 'https://bhromon.fun/api/media/purge';

/**
 * The media server call. It removes the person's files and returns the paths
 * it removed, relative to the tour's folder. A failed call throws, so the job
 * stays pending and is retried.
 */
export async function purgeMediaOnServer(
  tourId: string,
  uploaderEmail: string | null,
): Promise<string[]> {
  const key = process.env.MEDIA_PURGE_KEY;
  if (!key) throw new Error('MEDIA_PURGE_KEY is not configured');
  const response = await fetch(MEDIA_PURGE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Purge-Key': key },
    body: JSON.stringify({ tourId, uploaderEmail }),
  });
  if (!response.ok) {
    throw new Error(`Media purge answered HTTP ${response.status}`);
  }
  const body = (await response.json()) as { paths?: unknown };
  return Array.isArray(body.paths)
    ? body.paths.filter((path): path is string => typeof path === 'string')
    : [];
}

/** The account id behind an email, or null when there is no account. */
export async function resolveUidByEmail(email: string): Promise<string | null> {
  try {
    return (await admin.auth().getUserByEmail(email)).uid;
  } catch (error) {
    if ((error as { code?: unknown }).code === 'auth/user-not-found') return null;
    throw error;
  }
}

/** The production wiring of every outside call a purge makes. */
export function productionDeps(): PurgeDeps {
  return {
    purgeMedia: purgeMediaOnServer,
    purgeStorage: (tourId, uploaderEmail) =>
      purgeTourStorage(admin.storage().bucket(), tourId, uploaderEmail),
    resolveUid: resolveUidByEmail,
  };
}

/** A person's membership row was deleted: they left the tour, or were removed. */
export const onTourMembershipRemoved = functions
  .runWith(RUNTIME)
  .region(REGION)
  .firestore.document('memberships/{membershipId}')
  .onDelete(async (snap) => {
    const data = snap.data() ?? {};
    const tourId = typeof data.tourId === 'string' ? data.tourId : '';
    const email = normalizeEmail(data.email);
    const uid = typeof data.uid === 'string' && data.uid !== '' ? data.uid : null;
    if (!tourId || !email) return;
    const db = admin.firestore();
    // A tour that is already gone is purged as a whole by onTourDeleted.
    const tour = await db.collection('tours').doc(tourId).get();
    if (!tour.exists) return;
    await runPurgeJob(db, { kind: 'member', tourId, email, uid }, productionDeps());
  });

/** A tour document was deleted: everything in it goes. */
export const onTourDeleted = functions
  .runWith(RUNTIME)
  .region(REGION)
  .firestore.document('tours/{tourId}')
  .onDelete((_snap, context) =>
    runPurgeJob(
      admin.firestore(),
      { kind: 'tour', tourId: context.params.tourId },
      productionDeps(),
    ),
  );

/** Retries purges that failed partway, such as while the media server was down. */
export const retryTourPurgeJobs = functions
  .runWith(RUNTIME)
  .region(REGION)
  .pubsub.schedule('every 30 minutes')
  .onRun(() => retryPendingJobs(admin.firestore(), productionDeps()));
