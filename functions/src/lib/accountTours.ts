import * as admin from 'firebase-admin';
import { normalizeEmail } from './tourContentPlan';

/** A member row of a tour, as closing an account reads it. */
export interface MemberRow {
  email: string;
  status: string;
  role: string;
  joinedAtMs: number;
  uid: string | null;
}

/**
 * Who takes a tour over when its owner closes their account: the earliest-joined
 * active admin, or failing that the earliest-joined active member. Null when no
 * one else is in the tour.
 */
export function nextOwnerFor(
  members: MemberRow[],
  leavingEmail: string,
): { email: string; uid: string | null } | null {
  const candidates = members
    .filter((m) => m.status === 'active' && m.email !== leavingEmail)
    .sort(
      (a, b) =>
        adminRank(a) - adminRank(b) || a.joinedAtMs - b.joinedAtMs || a.email.localeCompare(b.email),
    );
  const first = candidates[0];
  return first ? { email: first.email, uid: first.uid } : null;
}

function adminRank(member: MemberRow): number {
  return member.role === 'admin' || member.role === 'owner' ? 0 : 1;
}

/**
 * Takes a closing account out of every tour it belongs to. Deleting a membership
 * row runs the purge of what that person put into the tour, photos included. A
 * tour they own passes to its next owner; a tour with nobody else in it is
 * deleted, and onTourDeleted purges everything in it.
 */
export async function leaveAllTours(db: admin.firestore.Firestore, rawEmail: string): Promise<void> {
  const email = normalizeEmail(rawEmail);
  if (email === '') return;

  const [rows, owned] = await Promise.all([
    db.collection('memberships').where('email', '==', email).get(),
    db.collection('tours').where('ownerEmail', '==', email).get(),
  ]);
  const tourIds = new Set<string>([
    ...rows.docs.map((doc) => String(doc.get('tourId') ?? '')),
    ...owned.docs.map((doc) => doc.id),
  ]);
  tourIds.delete('');

  for (const tourId of tourIds) {
    await leaveTour(db, tourId, email);
  }
}

async function leaveTour(db: admin.firestore.Firestore, tourId: string, email: string): Promise<void> {
  const tourRef = db.collection('tours').doc(tourId);
  const ownRowRef = db.collection('memberships').doc(`${tourId}__${email}`);
  const tour = await tourRef.get();

  if (!tour.exists || normalizeEmail(tour.get('ownerEmail')) !== email) {
    await ownRowRef.delete();
    return;
  }

  const memberRows = await db.collection('memberships').where('tourId', '==', tourId).get();
  const members: MemberRow[] = memberRows.docs.map((doc) => ({
    email: normalizeEmail(doc.get('email')),
    status: String(doc.get('status') ?? ''),
    role: String(doc.get('role') ?? ''),
    joinedAtMs: toMillis(doc.get('joinedAt')),
    uid: typeof doc.get('uid') === 'string' && doc.get('uid') !== '' ? String(doc.get('uid')) : null,
  }));
  const next = nextOwnerFor(members, email);
  if (next === null) {
    await tourRef.delete();
    return;
  }

  const batch = db.batch();
  batch.update(tourRef, { ownerEmail: next.email, ownerUid: next.uid ?? '' });
  batch.update(db.collection('memberships').doc(`${tourId}__${next.email}`), { role: 'owner' });
  await batch.commit();
  await ownRowRef.delete();
}

function toMillis(value: unknown): number {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return Number.MAX_SAFE_INTEGER;
}
