/**
 * Plumbing for the server-run tables (29 and Teen Patti): the Firestore
 * references, the checks on who is calling, and the seat bookkeeping. Each game
 * keeps its own rules and its own seat documents.
 */

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';

export const SEATS = 4;
const BOT_NAMES = ['Tour Guide Bot', 'Highway Ace Bot', 'Dhaka Champ Bot'];

export interface PlayerRow {
  email: string;
  displayName: string;
  photoUrl?: string;
  seatIndex: number;
  isReady: boolean;
  isHost: boolean;
  isBot: boolean;
}

export type DocData = FirebaseFirestore.DocumentData;
export type Transaction = FirebaseFirestore.Transaction;
export type DocRef = FirebaseFirestore.DocumentReference;

export const HttpsError = functions.https.HttpsError;

export const db = (): FirebaseFirestore.Firestore => admin.firestore();

export function botEmail(seat: number): string {
  return `bot_seat_${seat}@bhromon.fun`;
}

export function botName(index: number): string {
  return BOT_NAMES[index % BOT_NAMES.length];
}

export function nowIso(ms: number): string {
  return new Date(ms).toISOString();
}

export function gameRef(tourId: string, gameId: string): DocRef {
  return db().collection('tours').doc(tourId).collection('games').doc(gameId);
}

/** Each seat's private cards live in their own document. */
export function seatRef(table: DocRef, seat: number): DocRef {
  return table.collection('private').doc(`seat${seat}`);
}

export function callerEmail(context: functions.https.CallableContext): string {
  const email = String(context.auth?.token?.email ?? '').trim().toLowerCase();
  if (!context.auth || email === '') {
    throw new HttpsError('unauthenticated', 'Sign in to play at the table.');
  }
  return email;
}

export function requireIds(data: unknown): { tourId: string; gameId: string } {
  const body = (data ?? {}) as Record<string, unknown>;
  const tourId = typeof body.tourId === 'string' ? body.tourId : '';
  const gameId = typeof body.gameId === 'string' ? body.gameId : '';
  if (tourId === '' || gameId === '') {
    throw new HttpsError('invalid-argument', 'tourId and gameId are required.');
  }
  return { tourId, gameId };
}

export function expectedStepOf(data: unknown): number | null {
  const step = (data as Record<string, unknown> | null)?.expectedStep;
  return typeof step === 'number' ? step : null;
}

/** Members and the tour owner may use the table, as the security rules allow. */
export async function assertMember(tourId: string, email: string): Promise<void> {
  const tour = await db().collection('tours').doc(tourId).get();
  if (tour.exists && String(tour.get('ownerEmail') ?? '').toLowerCase() === email) return;
  const membership = await db().collection('memberships').doc(`${tourId}__${email}`).get();
  if (membership.exists && membership.get('status') === 'active') return;
  throw new HttpsError('permission-denied', 'You are not an active member of this tour.');
}

/** The seat a person sits in, or undefined. Bots never match. */
export function seatOfEmail(players: readonly PlayerRow[], email: string): number | undefined {
  return players.find((p) => !p.isBot && p.email === email)?.seatIndex;
}

export function stepOf(state: Record<string, unknown>): number {
  return typeof state.step === 'number' ? state.step : 0;
}

export function ownerOf(players: readonly PlayerRow[], seat: number): string {
  return players.find((p) => p.seatIndex === seat)?.email ?? botEmail(seat);
}

/** Every seat of a table, with a bot in every seat nobody has taken. */
export function completeSeats(players: PlayerRow[], seatCount: number = SEATS): PlayerRow[] {
  const taken = new Set<number>();
  for (const p of players) {
    if (!Number.isInteger(p.seatIndex) || p.seatIndex < 0 || p.seatIndex >= seatCount || taken.has(p.seatIndex)) {
      throw new HttpsError('failed-precondition', 'This table has a seat that cannot be used.');
    }
    taken.add(p.seatIndex);
  }
  const full = [...players];
  let bots = 0;
  for (let seat = 0; seat < seatCount; seat++) {
    if (taken.has(seat)) continue;
    full.push({
      email: botEmail(seat),
      displayName: botName(bots),
      seatIndex: seat,
      isReady: true,
      isHost: false,
      isBot: true,
    });
    bots++;
  }
  return full.sort((a, b) => a.seatIndex - b.seatIndex);
}
