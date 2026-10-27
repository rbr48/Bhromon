/**
 * The server side of the online 29 table. Every change runs in a Firestore
 * transaction that reads the table first, so two players acting at once cannot
 * overwrite each other, and the rules are checked here, not on the phone.
 *
 * Public table state lives in tours/{tourId}/games/{gameId}.state. Each seat's
 * hand lives in tours/{tourId}/games/{gameId}/private/seat{n}, readable only by
 * the seat's owner.
 */

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import {
  Card29Game,
  Card29RuleError,
  HumanAction,
  SeatDoc,
  publicState,
  restoreGame,
  seatDoc,
  shuffledDeck,
} from './game';
import { isCard, isSuit } from './cards';

const GAME_TYPE = 'card29';
const SEATS = 4;
const BOT_NAMES = ['Tour Guide Bot', 'Highway Ace Bot', 'Dhaka Champ Bot'];

interface PlayerRow {
  email: string;
  displayName: string;
  photoUrl?: string;
  seatIndex: number;
  isReady: boolean;
  isHost: boolean;
  isBot: boolean;
}

type DocData = FirebaseFirestore.DocumentData;
type Transaction = FirebaseFirestore.Transaction;
type DocRef = FirebaseFirestore.DocumentReference;

const db = (): FirebaseFirestore.Firestore => admin.firestore();

const HttpsError = functions.https.HttpsError;

function botEmail(seat: number): string {
  return `bot_seat_${seat}@bhromon.fun`;
}

function nowIso(ms: number): string {
  return new Date(ms).toISOString();
}

function gameRef(tourId: string, gameId: string): DocRef {
  return db().collection('tours').doc(tourId).collection('games').doc(gameId);
}

function seatRef(table: DocRef, seat: number): DocRef {
  return table.collection('private').doc(`seat${seat}`);
}

function callerEmail(context: functions.https.CallableContext): string {
  const email = String(context.auth?.token?.email ?? '').trim().toLowerCase();
  if (!context.auth || email === '') {
    throw new HttpsError('unauthenticated', 'Sign in to play at the table.');
  }
  return email;
}

function requireIds(data: unknown): { tourId: string; gameId: string } {
  const body = (data ?? {}) as Record<string, unknown>;
  const tourId = typeof body.tourId === 'string' ? body.tourId : '';
  const gameId = typeof body.gameId === 'string' ? body.gameId : '';
  if (tourId === '' || gameId === '') {
    throw new HttpsError('invalid-argument', 'tourId and gameId are required.');
  }
  return { tourId, gameId };
}

function expectedStepOf(data: unknown): number | null {
  const step = (data as Record<string, unknown> | null)?.expectedStep;
  return typeof step === 'number' ? step : null;
}

/** Members and the tour owner may use the table, as the security rules allow. */
async function assertMember(tourId: string, email: string): Promise<void> {
  const tour = await db().collection('tours').doc(tourId).get();
  if (tour.exists && String(tour.get('ownerEmail') ?? '').toLowerCase() === email) return;
  const membership = await db().collection('memberships').doc(`${tourId}__${email}`).get();
  if (membership.exists && membership.get('status') === 'active') return;
  throw new HttpsError('permission-denied', 'You are not an active member of this tour.');
}

function parseAction(raw: unknown): HumanAction {
  const invalid = (): never => {
    throw new HttpsError('invalid-argument', 'That action is not understood.');
  };
  if (typeof raw !== 'object' || raw === null) return invalid();
  const a = raw as Record<string, unknown>;
  switch (a.type) {
    case 'bid':
      if (typeof a.bid !== 'number' || !Number.isInteger(a.bid)) return invalid();
      return { type: 'bid', bid: a.bid };
    case 'selectTrump':
      if (!isSuit(a.suit)) return invalid();
      return { type: 'selectTrump', suit: a.suit };
    case 'play':
      if (!isCard(a.card)) return invalid();
      return { type: 'play', card: a.card };
    case 'pass':
    case 'ask':
    case 'reveal':
    case 'claimRoyalty':
    case 'nextDeal':
    case 'newMatch':
      return { type: a.type } as HumanAction;
    default:
      return invalid();
  }
}

function stepOf(state: Record<string, unknown>): number {
  return typeof state.step === 'number' ? state.step : 0;
}

/** Seats 0 to 3, with a bot in every seat nobody has taken. */
function completeSeats(players: PlayerRow[]): PlayerRow[] {
  const taken = new Set<number>();
  for (const p of players) {
    if (!Number.isInteger(p.seatIndex) || p.seatIndex < 0 || p.seatIndex >= SEATS || taken.has(p.seatIndex)) {
      throw new HttpsError('failed-precondition', 'This table has a seat that cannot be used.');
    }
    taken.add(p.seatIndex);
  }
  const full = [...players];
  let bots = 0;
  for (let seat = 0; seat < SEATS; seat++) {
    if (taken.has(seat)) continue;
    full.push({
      email: botEmail(seat),
      displayName: BOT_NAMES[bots % BOT_NAMES.length],
      seatIndex: seat,
      isReady: true,
      isHost: false,
      isBot: true,
    });
    bots++;
  }
  return full.sort((a, b) => a.seatIndex - b.seatIndex);
}

function ownerOf(players: readonly PlayerRow[], seat: number): string {
  return players.find((p) => p.seatIndex === seat)?.email ?? botEmail(seat);
}

interface RunningTable {
  players: PlayerRow[];
  state: Record<string, unknown>;
  seats: SeatDoc[];
  isBot: boolean[];
}

/** Reads a table that is in play, in a transaction. */
async function readRunning(tx: Transaction, ref: DocRef): Promise<RunningTable> {
  const snap = await tx.get(ref);
  if (!snap.exists) throw new HttpsError('not-found', 'This table no longer exists.');
  const data = snap.data() as DocData;
  if (data.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a 29 table.');
  if (data.status !== 'inProgress') throw new HttpsError('failed-precondition', 'This table is not in play.');

  // Reads go one after another inside the transaction.
  const seats: SeatDoc[] = [];
  for (let seat = 0; seat < SEATS; seat++) {
    const s = await tx.get(seatRef(ref, seat));
    if (!s.exists) throw new HttpsError('failed-precondition', 'This table has not been dealt yet.');
    seats.push(s.data() as SeatDoc);
  }
  const players = (data.players ?? []) as PlayerRow[];
  return {
    players,
    state: (data.state ?? {}) as Record<string, unknown>,
    seats,
    isBot: Array.from({ length: SEATS }, (_, seat) => players.find((p) => p.seatIndex === seat)?.isBot === true),
  };
}

/** Writes the new public state, and only the seat documents whose contents changed. */
function writeTable(
  tx: Transaction,
  ref: DocRef,
  table: RunningTable,
  game: Card29Game,
  nowMs: number,
  step: number,
): void {
  tx.update(ref, {
    state: publicState(game, step, nowMs),
    currentTurn: game.currentTurn,
    updatedAt: nowIso(nowMs),
    version: admin.firestore.FieldValue.increment(1),
  });
  for (let seat = 0; seat < SEATS; seat++) {
    const after = seatDoc(game, seat, ownerOf(table.players, seat));
    if (JSON.stringify(after) !== JSON.stringify(table.seats[seat])) {
      tx.set(seatRef(ref, seat), after);
    }
  }
}

/** Starts a waiting table: fills empty seats with bots, deals, and writes every seat. */
export const card29Start = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { tourId, gameId } = requireIds(data);
    const email = callerEmail(context);
    await assertMember(tourId, email);
    const ref = gameRef(tourId, gameId);

    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', 'This table no longer exists.');
      const table = snap.data() as DocData;
      if (table.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a 29 table.');
      if (table.status !== 'waiting') throw new HttpsError('failed-precondition', 'This table has already started.');
      if (String(table.hostEmail ?? '').toLowerCase() !== email) {
        throw new HttpsError('permission-denied', 'Only the host can start the table.');
      }

      const players = completeSeats((table.players ?? []) as PlayerRow[]);
      const isBot = Array.from({ length: SEATS }, (_, seat) => players[seat]?.isBot === true);
      const game = new Card29Game(isBot);
      game.startRound(shuffledDeck());
      const nowMs = Date.now();

      tx.update(ref, {
        players,
        status: 'inProgress',
        currentTurn: game.currentTurn,
        state: publicState(game, 1, nowMs),
        updatedAt: nowIso(nowMs),
        version: admin.firestore.FieldValue.increment(1),
      });
      for (let seat = 0; seat < SEATS; seat++) {
        tx.set(seatRef(ref, seat), seatDoc(game, seat, ownerOf(players, seat)));
      }
    });

    return { ok: true };
  });

/**
 * A seated player's action. The action must be allowed now, and it must come
 * from the seat whose turn it is. When [expectedStep] is given, a table that
 * has moved on is refused, so a stale screen cannot act on old information.
 */
export const card29Act = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { tourId, gameId } = requireIds(data);
    const action = parseAction((data as Record<string, unknown>)?.action);
    const expectedStep = expectedStepOf(data);
    const email = callerEmail(context);
    await assertMember(tourId, email);
    const ref = gameRef(tourId, gameId);

    const step = await db().runTransaction(async (tx) => {
      const table = await readRunning(tx, ref);
      const current = stepOf(table.state);
      if (expectedStep !== null && expectedStep !== current) {
        throw new HttpsError('aborted', 'The table has changed. Refresh and try again.');
      }
      const seat = table.players.find((p) => !p.isBot && p.email === email)?.seatIndex;
      if (seat === undefined) throw new HttpsError('permission-denied', 'Only seated players can act here.');

      const game = restoreGame(table.state, table.seats, table.isBot);
      try {
        game.applyHuman(seat, action, shuffledDeck);
      } catch (e) {
        if (e instanceof Card29RuleError) throw new HttpsError('failed-precondition', e.message);
        throw e;
      }
      writeTable(tx, ref, table, game, Date.now(), current + 1);
      return current + 1;
    });

    return { ok: true, step };
  });

/**
 * One step of the table, when it is someone's turn to be played for: a bot, a
 * finished trick, or a human whose time has run out. Any member may call it.
 * Calls that arrive when nothing is due return "noop", so duplicate calls are
 * harmless.
 */
export const card29Advance = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { tourId, gameId } = requireIds(data);
    const expectedStep = expectedStepOf(data);
    const email = callerEmail(context);
    await assertMember(tourId, email);
    const ref = gameRef(tourId, gameId);

    return db().runTransaction(async (tx) => {
      const table = await readRunning(tx, ref);
      const current = stepOf(table.state);
      if (expectedStep !== null && expectedStep !== current) {
        return { status: 'stale', step: current };
      }
      const deadline = typeof table.state.turnDeadline === 'number' ? table.state.turnDeadline : null;
      const nowMs = Date.now();
      const game = restoreGame(table.state, table.seats, table.isBot);
      const kind = game.advance(deadline !== null && nowMs >= deadline);
      if (kind === null) return { status: 'noop', step: current };
      writeTable(tx, ref, table, game, nowMs, current + 1);
      return { status: kind, step: current + 1 };
    });
  });

/**
 * Leaves a table. Before the deal, the seat is simply given up. Once play has
 * started, the seat passes to a bot so the table keeps going. A table with no
 * people left at all is removed.
 */
export const card29Leave = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { tourId, gameId } = requireIds(data);
    const email = callerEmail(context);
    await assertMember(tourId, email);
    const ref = gameRef(tourId, gameId);

    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const table = snap.data() as DocData;
      if (table.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a 29 table.');
      const players = (table.players ?? []) as PlayerRow[];
      const me = players.find((p) => !p.isBot && p.email === email);
      if (!me) return;
      const nowMs = Date.now();

      if (table.status !== 'inProgress') {
        const remaining = players.filter((p) => p.email !== email);
        if (remaining.length === 0 || table.hostEmail === email) {
          tx.delete(ref);
          return;
        }
        tx.update(ref, { players: remaining, updatedAt: nowIso(nowMs) });
        return;
      }

      const seat = me.seatIndex;
      const replacement: PlayerRow = {
        email: botEmail(seat),
        displayName: BOT_NAMES[seat % BOT_NAMES.length],
        seatIndex: seat,
        isReady: true,
        isHost: false,
        isBot: true,
      };
      const swapped = players.map((p) => (p === me ? replacement : p));
      const humans = swapped.filter((p) => !p.isBot);
      if (humans.length === 0) {
        tx.delete(ref);
        for (let s = 0; s < SEATS; s++) tx.delete(seatRef(ref, s));
        return;
      }

      // Hand the leaver's private cards to the bot, so the leaver cannot read them.
      const seatSnap = await tx.get(seatRef(ref, seat));
      if (seatSnap.exists) tx.update(seatRef(ref, seat), { owner: replacement.email });

      const newHost = table.hostEmail === email ? humans[0].email : String(table.hostEmail ?? '');
      tx.update(ref, {
        players: swapped.map((p) => ({ ...p, isHost: !p.isBot && p.email === newHost })),
        hostEmail: newHost,
        updatedAt: nowIso(nowMs),
        version: admin.firestore.FieldValue.increment(1),
      });
    });

    return { ok: true };
  });
