import { getAuth } from 'firebase-admin/auth';
import {
  BulkWriter,
  DocumentReference,
  FieldPath,
  FieldValue,
  Firestore,
  Query,
  QueryDocumentSnapshot,
  Transaction,
  getFirestore,
} from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import * as functions from 'firebase-functions/v1';
import * as crypto from 'crypto';
import { leave29Table } from './card29/callables';
import { leaveCarromTable } from './carrom/callables';
import { leaveTeenPattiTable } from './teenPatti/callables';
import { purgeTourStorage } from './lib/tourStorage';
import { purgeCdnPaths } from './lib/cdnPurge';
import {
  AnonymizePlan,
  Decide,
  aboutPerson,
  anonymize,
  deleteWhen,
  familyTaskOf,
  formerMemberId,
  isInTour,
  leaveClientTable,
  leaveHotelRoom,
  luggageOf,
  normalizeEmail,
  pairWith,
  profileOf,
  Scrub,
  scrubsFor,
  seatHeldBy,
  sosOf,
  tableNames,
  updateArgs,
} from './lib/tourContentPlan';

/**
 * Permanent removal of tour content, on the server.
 *
 * - When a person leaves a tour, or the owner removes them, what they put
 *   into the tour is removed: their posts, stories, highlights, comments, chat
 *   messages, locations, luggage and seats, with their photos, videos and
 *   Storage files. They are also taken out of other people's likes, viewers,
 *   reactions, votes, mentions and tags. At a game table only their seat goes,
 *   and a seat in play passes to a bot. Their safety alerts stay as resolved
 *   records under a stand-in.
 * - The group's shared record (the ledger, notices, route stops, the packing
 *   list, and the study book list, reading plan, subjects, tips, suggestions, past papers, charts, assignments, findings, problems, problem sets and weekly
 *   challenges) keeps its amounts and dates. A challenge loses the person's join only.
 *   The person is replaced by a stand-in.
 * - When a tour is deleted, everything in it is deleted.
 *
 * Each purge is written as a job before it starts and removed once it has
 * finished. A purge that fails, for example while the media server is down, is
 * retried by retryTourPurgeJobs until it succeeds or gives up after two days.
 */

type Db = Firestore;
type DocRef = DocumentReference;
type DocSnap = QueryDocumentSnapshot;

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
// A family date belongs to the circle, so it stays; only its author is replaced.
const FAMILY_DATE: AnonymizePlan = { emails: ['createdByEmail'] };
const CHECKPOINT: AnonymizePlan = { emails: ['addedByEmail'] };
const CHECKLIST_ITEM: AnonymizePlan = { removeFromLists: ['checkedBy'] };
const CHANNEL: AnonymizePlan = { emails: ['createdByEmail', 'updatedByEmail'] };
const PINNED_MESSAGE: AnonymizePlan = { emails: ['pinnedByEmail'] };
const ITINERARY_META: AnonymizePlan = { emails: ['updatedByEmail'] };
/** A book on a study group's list: who added or proposed it, and who last set its status. */
const STUDY_BOOK: AnonymizePlan = { emails: ['createdByEmail', 'statusByEmail'] };
/** A reading session: who planned it. */
const STUDY_SESSION: AnonymizePlan = { emails: ['createdByEmail'] };
/** A study subject: who added or proposed it. */
const STUDY_SUBJECT: AnonymizePlan = { emails: ['createdByEmail'] };
/** A tip or a suggestion in a subject: who posted it. */
const STUDY_POST: AnonymizePlan = { emails: ['createdByEmail'] };
const STUDY_FINDING: AnonymizePlan = { emails: ['createdByEmail', 'withdrawnBy'] };
// A working another member wrote keeps its words. Only the admin who withdrew a review on it is named there.
const STUDY_WORK: AnonymizePlan = { emails: ['withdrawnBy'] };
const STUDY_ASSIGNMENT: AnonymizePlan = { emails: ['createdByEmail'] };
const STUDY_PROBLEM: AnonymizePlan = { emails: ['createdByEmail'] };
const STUDY_PROBLEM_SET: AnonymizePlan = { emails: ['createdByEmail'] };
/** A member's own due date for a problem set: who set it, for the admin who set it. */
const STUDY_MEMBER_DEADLINE: AnonymizePlan = { emails: ['setByEmail'] };
const STUDY_REFERENCE: AnonymizePlan = { emails: ['reviewedByEmail'] };
const STUDY_CHALLENGE: AnonymizePlan = { emails: ['setByEmail'] };
/** A discussion thread on a book: who started it. */
const STUDY_THREAD: AnonymizePlan = { emails: ['createdByEmail'] };
/** A reply in a thread: who wrote it. */
const STUDY_REPLY: AnonymizePlan = { emails: ['createdByEmail'] };
/** A study material: who filed it. */
const STUDY_MATERIAL: AnonymizePlan = { emails: ['createdByEmail'] };
const STUDY_QUIZ: AnonymizePlan = { emails: ['createdByEmail'] };
const STUDY_QUESTION: AnonymizePlan = { emails: ['proposedByEmail'] };
const STUDY_TERM: AnonymizePlan = { emails: ['createdByEmail'] };
const STUDY_SUMMARY: AnonymizePlan = { emails: ['editorEmail'] };

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
  private readonly writer: BulkWriter;
  private readonly writes: Promise<void>[] = [];

  constructor(db: Db) {
    this.writer = db.bulkWriter();
    this.writer.onWriteError(
      (error: any) => error.code !== NOT_FOUND && error.failedAttempts < 5,
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
        args[0] as string | FieldPath,
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
    const recursive = await db.runTransaction(async (tx: Transaction) => {
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
    snapshot.docs.map((doc: QueryDocumentSnapshot) => doc.ref),
    decide,
  );
}

/** Whether [email] holds a membership row in the tour, active or not. */
/**
 * Removes the person's report of a reported item (a finding, a problem or a working) and drops the item's
 * report count by one, in one batch. The item stays as it is: a hidden item waits for an admin. Runs again
 * safely, because it acts only when the report is there.
 */
async function removeReport(db: Db, item: DocRef, email: string): Promise<void> {
  const report = item.collection('reports').doc(email);
  if (!(await report.get()).exists) return;
  const batch = db.batch();
  batch.delete(report);
  batch.update(item, { reportCount: FieldValue.increment(-1) });
  await batch.commit();
}

async function holdsMembership(db: Db, tourId: string, email: string): Promise<boolean> {
  const row = await db.collection('memberships').doc(`${tourId}__${email}`).get();
  return row.exists;
}

/** Takes a person's seat off a table the server runs, as the app's own leave does. */
type ServerLeave = (
  tourId: string,
  gameId: string,
  email: string,
  options: { closeLobbyOnHostLeave: boolean },
) => Promise<void>;

/** The leave routine of each table the server runs. The apps run the rest. */
const SERVER_TABLES = new Map<string, ServerLeave>([
  ['card29', leave29Table],
  ['teen_patti', leaveTeenPattiTable],
  ['carrom', leaveCarromTable],
]);

/**
 * Takes the person's seat off each game table they host or sit at. The table
 * keeps its other people. A table the server runs is left by the routine the
 * app uses, so a seat in play passes to a bot. A lobby passes its host on
 * rather than closing, so the others keep their table.
 */
async function leaveGameTables(db: Db, tourId: string, email: string): Promise<void> {
  const tables = await db.collection('tours').doc(tourId).collection('games').get();
  for (const table of tables.docs) {
    if (!tableNames(table.data(), email)) continue;
    const leave = SERVER_TABLES.get(String(table.data().gameType));
    if (leave) {
      await leave(tourId, table.id, email, { closeLobbyOnHostLeave: false });
      await forgetSeats(db, table.ref, email);
    } else {
      await applyToDocs(db, [table.ref], leaveClientTable(email));
    }
  }
}

/**
 * Once the person has left a server-run table, their cards are gone from it. A
 * table that was removed takes its seats with it. A table not in play drops the
 * seats that were theirs. A table in play keeps its seats, which the leave has
 * already handed to a bot.
 */
async function forgetSeats(db: Db, table: DocRef, email: string): Promise<void> {
  const after = await table.get();
  if (!after.exists) {
    await db.recursiveDelete(table);
    return;
  }
  if (after.get('status') === 'inProgress') return;
  const seats = await table.collection('private').get();
  await applyToDocs(
    db,
    seats.docs.map((seat: QueryDocumentSnapshot) => seat.ref),
    deleteWhen((data) => normalizeEmail(data.owner) === email),
  );
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
    new FieldPath(...path, email);
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

  // Safety alerts they raised stay as resolved records under the stand-in, without
  // the location they sent. An alert they resolved for someone else keeps its resolution.
  await applyToQuery(db, tour.collection('sos'), sosOf(email, standIn));

  // The group's shared record keeps its amounts and dates. The person is
  // replaced by the stand-in, so the balances and the notices still read.
  await applyToQuery(db, tour.collection('expenses'), anonymize(LEDGER_EXPENSE, email, standIn));
  await applyToQuery(db, tour.collection('deposits'), anonymize(LEDGER_DEPOSIT, email, standIn));
  await applyToQuery(db, tour.collection('transfers'), anonymize(LEDGER_TRANSFER, email, standIn));
  await applyToQuery(db, tour.collection('notices'), anonymize(NOTICE, email, standIn));
  await applyToQuery(db, tour.collection('family_dates'), anonymize(FAMILY_DATE, email, standIn));
  // A shared shopping or to-do item stays for the circle under the stand-in, and an item given to the
  // person is open to anyone again. Their own day counts for those items go.
  await applyToQuery(db, tour.collection('family_tasks'), familyTaskOf(email, standIn));
  await applyToQuery(
    db,
    tour.collection('family_task_daily').where('email', '==', email),
    aboutPerson(email),
  );
  await applyToQuery(db, tour.collection('checkpoints'), anonymize(CHECKPOINT, email, standIn));
  await applyToQuery(db, tour.collection('checklist'), anonymize(CHECKLIST_ITEM, email, standIn));
  await applyToQuery(db, tour.collection('meta'), anonymize(ITINERARY_META, email, standIn));
  await applyToQuery(db, tour.collection('study_books'), anonymize(STUDY_BOOK, email, standIn));
  await applyToQuery(db, tour.collection('reading_sessions'), anonymize(STUDY_SESSION, email, standIn));
  // A session keeps its words under the stand-in. The person's answer and check-in come out, and the
  // step runs again safely: each delete happens only when the answer is there.
  const sessions = await tour.collection('reading_sessions').get();
  for (const session of sessions.docs) {
    const answer = session.ref.collection('rsvps').doc(email);
    if ((await answer.get()).exists) await answer.delete();
  }
  await applyToQuery(db, tour.collection('study_subjects'), anonymize(STUDY_SUBJECT, email, standIn));
  // Each subject's tips, suggestions, past papers and charts keep their text under the stand-in. The person's
  // helpful marks come out, and each post's count drops by the mark removed.
  const subjects = await tour.collection('study_subjects').get();
  for (const subject of subjects.docs) {
    for (const kind of ['tips', 'suggestions', 'papers', 'charts', 'differences']) {
      const posts = subject.ref.collection(kind);
      await applyToQuery(db, posts, anonymize(STUDY_POST, email, standIn));
      const docs = await posts.get();
      for (const post of docs.docs) {
        const mark = post.ref.collection('helpful').doc(email);
        const snap = await mark.get();
        if (!snap.exists) continue;
        const batch = db.batch();
        batch.delete(mark);
        batch.update(post.ref, { helpfulCount: FieldValue.increment(-1) });
        await batch.commit();
      }
    }

    // Assignments keep their words and due days under the stand-in. The person's finished marks are one document of
    // their own, which comes out.
    const assignments = subject.ref.collection('assignments');
    await applyToQuery(db, assignments, anonymize(STUDY_ASSIGNMENT, email, standIn));
    const finishedMarks = subject.ref.collection('assignment_marks').doc(email);
    if ((await finishedMarks.get()).exists) await finishedMarks.delete();

    // Shared findings keep their words under the stand-in. The person's checks and reports come out, and
    // each finding's count drops by the one removed, so the counts stay true.
    const findings = subject.ref.collection('findings');
    await applyToQuery(db, findings, anonymize(STUDY_FINDING, email, standIn));
    const found = await findings.get();
    for (const finding of found.docs) {
      await removeReport(db, finding.ref, email);
      const check = finding.ref.collection('checks').doc(email);
      const snap = await check.get();
      if (!snap.exists) continue;
      const countField = snap.get('verdict') === 'confirm' ? 'confirmCount' : 'challengeCount';
      const batch = db.batch();
      batch.delete(check);
      batch.update(finding.ref, { [countField]: FieldValue.increment(-1) });
      await batch.commit();
    }

    // Problems keep their statement under the stand-in, and a reference solution keeps its text with the admin who
    // wrote it under the stand-in. The person's own working is their attempt, so it goes with the reviews of it, as
    // their attempts do. Their reviews of other members' working go too, and each working's counts follow them.
    const problems = subject.ref.collection('problems');
    await applyToQuery(db, problems, anonymize(STUDY_PROBLEM, email, standIn));
    // A problem set keeps its name and due date under the stand-in for the admin who made it.
    await applyToQuery(db, subject.ref.collection('problem_sets'), anonymize(STUDY_PROBLEM_SET, email, standIn));
    // A member's own due date for a set goes with the member. A date the member set for someone else keeps its date,
    // under the stand-in for the admin who set it.
    const setDocs = await subject.ref.collection('problem_sets').get();
    for (const set of setDocs.docs) {
      const deadlines = set.ref.collection('member_deadlines');
      const own = deadlines.doc(email);
      if ((await own.get()).exists) await own.delete();
      await applyToQuery(db, deadlines, anonymize(STUDY_MEMBER_DEADLINE, email, standIn));
    }
    const problemDocs = await problems.get();
    for (const problem of problemDocs.docs) {
      await removeReport(db, problem.ref, email);
      await applyToQuery(db, problem.ref.collection('reference'), anonymize(STUDY_REFERENCE, email, standIn));
      const solutions = problem.ref.collection('solutions');
      const own = solutions.doc(email);
      if ((await own.get()).exists) {
        const ownReviews = await own.collection('reviews').get();
        for (const review of ownReviews.docs) await review.ref.delete();
        await own.delete();
      }
      const workDocs = await solutions.get();
      for (const work of workDocs.docs) {
        await removeReport(db, work.ref, email);
        const review = work.ref.collection('reviews').doc(email);
        const snap = await review.get();
        if (!snap.exists) continue;
        const countField = snap.get('verdict') === 'right' ? 'rightCount' : 'gapCount';
        const batch = db.batch();
        batch.delete(review);
        batch.update(work.ref, { [countField]: FieldValue.increment(-1) });
        await batch.commit();
      }
      // A review an admin withdrew from someone's working names the admin on the working. That name goes too.
      await applyToQuery(db, solutions, anonymize(STUDY_WORK, email, standIn));
    }

    // A week's challenge keeps its kind and target under the stand-in for the admin who set it. The person's join
    // comes out, so the challenge stops listing them, and the step runs again safely: each delete happens only when
    // the join is there.
    const challenges = subject.ref.collection('challenges');
    await applyToQuery(db, challenges, anonymize(STUDY_CHALLENGE, email, standIn));
    const weeks = await challenges.get();
    for (const week of weeks.docs) {
      const join = week.ref.collection('joins').doc(email);
      if ((await join.get()).exists) await join.delete();
    }
  }

  // A book's votes and a chapter's read marks are the person's own records, so they go.
  // Each delete runs only when the record is there, so the step can run again.
  const books = await tour.collection('study_books').get();
  for (const book of books.docs) {
    const vote = book.ref.collection('votes').doc(email);
    if ((await vote.get()).exists) await vote.delete();
    const chapters = await book.ref.collection('chapters').get();
    for (const chapter of chapters.docs) {
      const read = chapter.ref.collection('reads').doc(email);
      if ((await read.get()).exists) await read.delete();
      // Summary revisions keep their words under the stand-in, so the group's history stays whole. The person's
      // reports on them come out, and each count drops by one.
      await applyToQuery(db, chapter.ref.collection('summaries'), anonymize(STUDY_SUMMARY, email, standIn));
      const revisions = await chapter.ref.collection('summaries').get();
      for (const revision of revisions.docs) await removeReport(db, revision.ref, email);
    }
  }

  // Each book's threads and their replies keep their words under the stand-in. The person's helpful
  // marks and reports on replies come out, and each count drops by the mark or report removed.
  for (const book of books.docs) {
    const threads = book.ref.collection('threads');
    await applyToQuery(db, threads, anonymize(STUDY_THREAD, email, standIn));
    const threadDocs = await threads.get();
    for (const thread of threadDocs.docs) {
      const replies = thread.ref.collection('replies');
      await applyToQuery(db, replies, anonymize(STUDY_REPLY, email, standIn));
      const replyDocs = await replies.get();
      for (const reply of replyDocs.docs) {
        const mark = reply.ref.collection('helpful').doc(email);
        if ((await mark.get()).exists) {
          const batch = db.batch();
          batch.delete(mark);
          batch.update(reply.ref, { helpfulCount: FieldValue.increment(-1) });
          await batch.commit();
        }
        const report = reply.ref.collection('reports').doc(email);
        if ((await report.get()).exists) {
          const batch = db.batch();
          batch.delete(report);
          batch.update(reply.ref, { reportCount: FieldValue.increment(-1) });
          await batch.commit();
        }
      }
    }
  }

  // A quiz and its questions keep their words under the stand-in, and so does a glossary term. The person's
  // attempt on a quiz is their private record, so it goes. Each delete runs only when the record is there.
  for (const book of books.docs) {
    const quizzes = book.ref.collection('quizzes');
    await applyToQuery(db, quizzes, anonymize(STUDY_QUIZ, email, standIn));
    const quizDocs = await quizzes.get();
    for (const quiz of quizDocs.docs) {
      const questions = quiz.ref.collection('questions');
      await applyToQuery(db, questions, anonymize(STUDY_QUESTION, email, standIn));
      const attempt = quiz.ref.collection('attempts').doc(email);
      if ((await attempt.get()).exists) await attempt.delete();
    }
    const terms = book.ref.collection('glossary');
    await applyToQuery(db, terms, anonymize(STUDY_TERM, email, standIn));
  }

  // Materials keep their title and file under the stand-in. The person's reports come out, and each
  // count drops by the report removed. Their open markers come out too.
  const materials = tour.collection('study_materials');
  await applyToQuery(db, materials, anonymize(STUDY_MATERIAL, email, standIn));
  const materialDocs = await materials.get();
  for (const material of materialDocs.docs) {
    const report = material.ref.collection('reports').doc(email);
    if ((await report.get()).exists) {
      const batch = db.batch();
      batch.delete(report);
      batch.update(material.ref, { reportCount: FieldValue.increment(-1) });
      await batch.commit();
    }
    const open = material.ref.collection('opens').doc(email);
    if ((await open.get()).exists) await open.delete();
  }

  // What only the person used goes: luggage they own, seats and rooms they hold,
  // and their profile in the tour. At a game table only their seat goes.
  await applyToQuery(db, tour.collection('luggage'), luggageOf(email));
  await applyToQuery(db, tour.collection('bus_seats'), seatHeldBy(email));
  await applyToQuery(db, tour.collection('vehicle_seats'), seatHeldBy(email));
  await applyToQuery(db, tour.collection('hotel_rooms'), leaveHotelRoom(email));
  await leaveGameTables(db, tourId, email);
  await applyToQuery(db, tour.collection('profiles'), profileOf(email, memberUid));

  // Group chat: their messages, their reactions and votes, the mentions and tags
  // naming them, and their typing and voice presence in each channel.
  const channels = await tour.collection('channels').get();
  await applyToDocs(
    db,
    channels.docs.map((channel: QueryDocumentSnapshot) => channel.ref),
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
  const now = FieldValue.serverTimestamp();
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
        attempts: FieldValue.increment(1),
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
        { status: 'failed', updatedAt: FieldValue.serverTimestamp() },
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
    return (await getAuth().getUserByEmail(email)).uid;
  } catch (error) {
    if ((error as { code?: unknown }).code === 'auth/user-not-found') return null;
    throw error;
  }
}

/** The production wiring of every outside call a purge makes. */
export function productionDeps(): PurgeDeps {
  return {
    purgeMedia: async (tourId, uploaderEmail) => {
      const removed = await purgeMediaOnServer(tourId, uploaderEmail);
      // Cached copies of deleted media are cleared too, but a CDN failure must not stop the purge.
      try {
        await purgeCdnPaths(removed);
      } catch (error) {
        console.error('CDN purge after a media purge failed:', error);
      }
      return removed;
    },
    purgeStorage: (tourId, uploaderEmail) =>
      purgeTourStorage(getStorage().bucket(), tourId, uploaderEmail),
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
    const db = getFirestore();
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
      getFirestore(),
      { kind: 'tour', tourId: context.params.tourId },
      productionDeps(),
    ),
  );

/** Retries purges that failed partway, such as while the media server was down. */
export const retryTourPurgeJobs = functions
  .runWith(RUNTIME)
  .region(REGION)
  .pubsub.schedule('every 30 minutes')
  .onRun(() => retryPendingJobs(getFirestore(), productionDeps()));
