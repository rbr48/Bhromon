import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import {
  isInTour,
  normalizeEmail,
  Scrub,
  scrubsFor,
  updateArgs,
} from './lib/tourContentPlan';

/**
 * Permanent removal of tour content, on the server.
 *
 * - When a person leaves a tour, or the owner removes them, their own posts,
 *   stories, highlights, comments and chat messages in that tour are deleted,
 *   with their photos and videos on the media server. They are also taken out
 *   of other people's likes, viewers, reactions and votes.
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

/** Removes the media a tour, or one person's uploads in it, put on the server. */
export type MediaPurge = (
  tourId: string,
  uploaderEmail: string | null,
) => Promise<void>;

export type PurgeJob =
  | { kind: 'member'; tourId: string; email: string }
  | { kind: 'tour'; tourId: string };

const JOBS = 'tour_purge_jobs';
const NOT_FOUND = 5;
/** Retries every 30 minutes for two days, then the job is marked failed. */
const MAX_ATTEMPTS = 96;
const MEDIA_PURGE_URL =
  process.env.MEDIA_PURGE_URL ?? 'https://bhromon.fun/api/media/purge';
const REGION = 'asia-south1';
const RUNTIME = {
  timeoutSeconds: 540,
  memory: '512MB' as const,
  secrets: ['MEDIA_PURGE_KEY'],
};

const everywhere = (_path: string): boolean => true;

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

/** Whether [email] holds a membership row in the tour, active or not. */
async function holdsMembership(db: Db, tourId: string, email: string): Promise<boolean> {
  const row = await db.collection('memberships').doc(`${tourId}__${email}`).get();
  return row.exists;
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
  purgeMedia: MediaPurge,
): Promise<void> {
  if (!email || (await holdsMembership(db, tourId, email))) return;
  const tour = db.collection('tours').doc(tourId);
  const inTour = (path: string): boolean => isInTour(path, tourId);
  // A map keyed by email, read as one field path so the dots are not nesting.
  const keyIs = (...path: string[]) =>
    new admin.firestore.FieldPath(...path, email);

  // Their own posts, with the comments under them.
  await deleteMatching(
    db,
    [tour.collection('posts').where('authorEmail', '==', email)],
    everywhere,
    true,
  );

  // Other people's posts: take them out of the likes and viewers.
  await scrubMatching(
    db,
    email,
    [
      tour.collection('posts').where('likes', 'array-contains', email),
      tour.collection('posts').where('viewers', 'array-contains', email),
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

  // Their live presence.
  await deleteRefs(db, [tour.collection('presence').doc(email)]);

  // Group chat: their messages, their reactions and votes, and their typing
  // and voice presence in each channel.
  const channels = await tour.collection('channels').get();
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
      ],
      everywhere,
    );
    await deleteRefs(db, [
      channel.ref.collection('typing').doc(email),
      channel.ref.collection('voice_participants').doc(email),
    ]);
  }

  // Their photos and videos on the media server.
  await purgeMedia(tourId, email);
}

/** Removes a whole tour: everything under it, its memberships and invites, and its media. */
export async function purgeTour(
  db: Db,
  tourId: string,
  purgeMedia: MediaPurge,
): Promise<void> {
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
  await purgeMedia(tourId, null);
}

function jobRef(db: Db, job: PurgeJob): DocRef {
  // The email is hashed into the id, so no address is kept in a document name.
  const key =
    job.kind === 'member'
      ? `member_${crypto.createHash('sha256').update(job.email).digest('hex')}`
      : 'tour';
  return db.collection(JOBS).doc(`${job.tourId}__${key}`);
}

function jobFields(job: PurgeJob): Record<string, string> {
  // The job keeps the email while it is pending, so a retry can finish it. It
  // is deleted as soon as the purge succeeds.
  return job.kind === 'member'
    ? { kind: 'member', tourId: job.tourId, email: job.email }
    : { kind: 'tour', tourId: job.tourId };
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 300) : 'unknown error';
}

/** Runs one purge. On failure the job stays pending for retryPendingJobs. */
export async function runPurgeJob(
  db: Db,
  job: PurgeJob,
  purgeMedia: MediaPurge,
): Promise<void> {
  const ref = jobRef(db, job);
  const now = admin.firestore.FieldValue.serverTimestamp();
  await ref.set({ ...jobFields(job), status: 'pending', updatedAt: now }, { merge: true });
  try {
    if (job.kind === 'member') {
      await purgeMemberContent(db, job.tourId, job.email, purgeMedia);
    } else {
      await purgeTour(db, job.tourId, purgeMedia);
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
export async function retryPendingJobs(
  db: Db,
  purgeMedia: MediaPurge,
  limit = 50,
): Promise<void> {
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
      await runPurgeJob(db, { kind: 'member', tourId, email: data.email }, purgeMedia);
    } else if (data.kind === 'tour' && tourId) {
      await runPurgeJob(db, { kind: 'tour', tourId }, purgeMedia);
    }
  }
}

/** The real media call. The media server removes what the purge names. */
export async function purgeMediaOnServer(
  tourId: string,
  uploaderEmail: string | null,
): Promise<void> {
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
    if (!tourId || !email) return;
    const db = admin.firestore();
    // A tour that is already gone is purged as a whole by onTourDeleted.
    const tour = await db.collection('tours').doc(tourId).get();
    if (!tour.exists) return;
    await runPurgeJob(db, { kind: 'member', tourId, email }, purgeMediaOnServer);
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
      purgeMediaOnServer,
    ),
  );

/** Retries purges that failed partway, such as while the media server was down. */
export const retryTourPurgeJobs = functions
  .runWith(RUNTIME)
  .region(REGION)
  .pubsub.schedule('every 30 minutes')
  .onRun(() => retryPendingJobs(admin.firestore(), purgeMediaOnServer));
