/**
 * The server side of the online Teen Patti table. As on the 29 table, every
 * change runs in a Firestore transaction that reads the table first, so two
 * people acting at once cannot overwrite each other, and the rules are checked
 * here, not on the phone.
 *
 * Public table state lives in tours/{tourId}/games/{gameId}.state. Each seat's
 * three cards live in tours/{tourId}/games/{gameId}/private/seat{n}, readable
 * only by that seat's owner. The seat documents change only when a hand is dealt.
 */

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { SeatDoc, TeenPattiAction, TeenPattiGame, TeenPattiRuleError, publicState, restoreGame, seatDoc } from './game';
import { shuffledDeck } from './cards';
import { STARTING_CHIPS } from './rules';
import {
  DocData,
  DocRef,
  HttpsError,
  PlayerRow,
  SEATS,
  Transaction,
  assertMember,
  botEmail,
  botName,
  callerEmail,
  completeSeats,
  db,
  expectedStepOf,
  gameRef,
  nowIso,
  ownerOf,
  requireIds,
  seatOfEmail,
  seatRef,
  stepOf,
} from '../gameTable/shared';

const GAME_TYPE = 'teen_patti';

function parseAction(raw: unknown): TeenPattiAction {
  const invalid = (): never => {
    throw new HttpsError('invalid-argument', 'That action is not understood.');
  };
  if (typeof raw !== 'object' || raw === null) return invalid();
  const a = raw as Record<string, unknown>;
  switch (a.type) {
    case 'see':
    case 'bet':
    case 'raise':
    case 'pack':
    case 'show':
    case 'sideshow':
    case 'rebuy':
    case 'nextHand':
      return { type: a.type } as TeenPattiAction;
    case 'sideshowReply':
      if (typeof a.accept !== 'boolean') return invalid();
      return { type: 'sideshowReply', accept: a.accept };
    default:
      return invalid();
  }
}

function botFlags(players: readonly PlayerRow[]): boolean[] {
  return Array.from({ length: SEATS }, (_, seat) => players.find((p) => p.seatIndex === seat)?.isBot === true);
}

interface RunningTable {
  players: PlayerRow[];
  state: Record<string, unknown>;
  seats: SeatDoc[];
  isBot: boolean[];
}

/** Reads every seat's private document. All reads come before any write in a transaction. */
async function readSeatDocs(tx: Transaction, ref: DocRef): Promise<SeatDoc[]> {
  const seats: SeatDoc[] = [];
  for (let seat = 0; seat < SEATS; seat++) {
    const s = await tx.get(seatRef(ref, seat));
    if (!s.exists) throw new HttpsError('failed-precondition', 'This table has not been dealt yet.');
    seats.push(s.data() as SeatDoc);
  }
  return seats;
}

/** Reads a table that is in play, in a transaction. */
async function readRunning(tx: Transaction, ref: DocRef): Promise<RunningTable> {
  const snap = await tx.get(ref);
  if (!snap.exists) throw new HttpsError('not-found', 'This table no longer exists.');
  const data = snap.data() as DocData;
  if (data.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a Teen Patti table.');
  if (data.status !== 'inProgress') throw new HttpsError('failed-precondition', 'This table is not in play.');

  const seats = await readSeatDocs(tx, ref);
  const players = (data.players ?? []) as PlayerRow[];
  return {
    players,
    state: (data.state ?? {}) as Record<string, unknown>,
    seats,
    isBot: botFlags(players),
  };
}

/** Writes the new public state. The seat documents are not touched. */
function writeState(tx: Transaction, ref: DocRef, game: TeenPattiGame, nowMs: number, step: number): void {
  tx.update(ref, {
    state: publicState(game, step, nowMs),
    currentTurn: game.currentTurn,
    updatedAt: nowIso(nowMs),
    version: admin.firestore.FieldValue.increment(1),
  });
}

/** Writes every seat's cards for a newly dealt hand. */
function writeDeal(tx: Transaction, ref: DocRef, game: TeenPattiGame, players: readonly PlayerRow[]): void {
  for (let seat = 0; seat < SEATS; seat++) {
    tx.set(seatRef(ref, seat), seatDoc(game, seat, ownerOf(players, seat)));
  }
}

/** Starts a waiting table: fills empty seats with bots, and deals the first hand. */
export const teenPattiStart = functions
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
      if (table.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a Teen Patti table.');
      if (table.status !== 'waiting') throw new HttpsError('failed-precondition', 'This table has already started.');
      if (String(table.hostEmail ?? '').toLowerCase() !== email) {
        throw new HttpsError('permission-denied', 'Only the host can start the table.');
      }

      const players = completeSeats((table.players ?? []) as PlayerRow[]);
      const game = new TeenPattiGame(botFlags(players));
      for (const seat of game.seats) seat.chips = STARTING_CHIPS;
      if (!game.startHand(shuffledDeck())) throw new HttpsError('failed-precondition', 'The table cannot be dealt.');
      const nowMs = Date.now();

      tx.update(ref, {
        players,
        status: 'inProgress',
        currentTurn: game.currentTurn,
        state: publicState(game, 1, nowMs),
        updatedAt: nowIso(nowMs),
        version: admin.firestore.FieldValue.increment(1),
      });
      writeDeal(tx, ref, game, players);
    });

    return { ok: true };
  });

/**
 * A seated player's action. The action must be allowed now. When [expectedStep]
 * is given, a table that has moved on is refused, so a stale screen cannot act
 * on old information.
 */
export const teenPattiAct = functions
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
      const seat = seatOfEmail(table.players, email);
      if (seat === undefined) throw new HttpsError('permission-denied', 'Only seated players can act here.');

      const game = restoreGame(table.state, table.seats, table.isBot);
      const handBefore = game.handNumber;
      try {
        game.applyHuman(seat, action, shuffledDeck);
      } catch (e) {
        if (e instanceof TeenPattiRuleError) throw new HttpsError('failed-precondition', e.message);
        throw e;
      }
      writeState(tx, ref, game, Date.now(), current + 1);
      if (game.handNumber !== handBefore) writeDeal(tx, ref, game, table.players);
      return current + 1;
    });

    return { ok: true, step };
  });

/**
 * One step of the table, when a bot must act or a person's time has run out.
 * Any member may call it. Calls that arrive when nothing is due return "noop",
 * so duplicate calls are harmless.
 */
export const teenPattiAdvance = functions
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
      writeState(tx, ref, game, nowMs, current + 1);
      return { status: kind, step: current + 1 };
    });
  });

/**
 * Leaves a table. Before the deal, the seat is simply given up. Once a hand is
 * under way, the seat packs and passes to a bot, so the table keeps going. A
 * table with no people left at all is removed.
 */
export const teenPattiLeave = functions
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
      if (table.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a Teen Patti table.');
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
        displayName: botName(seat),
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

      // Reads come before writes: the hand as it stands, then the table is updated.
      const seats = await readSeatDocs(tx, ref);
      const state = (table.state ?? {}) as Record<string, unknown>;
      const game = restoreGame(state, seats, botFlags(swapped));
      game.seatLeft(seat);

      const newHost = table.hostEmail === email ? humans[0].email : String(table.hostEmail ?? '');
      tx.update(ref, {
        players: swapped.map((p) => ({ ...p, isHost: !p.isBot && p.email === newHost })),
        hostEmail: newHost,
        state: publicState(game, stepOf(state) + 1, nowMs),
        currentTurn: game.currentTurn,
        updatedAt: nowIso(nowMs),
        version: admin.firestore.FieldValue.increment(1),
      });
      // Hand the leaver's cards to the bot, so the leaver can no longer read them.
      tx.update(seatRef(ref, seat), { owner: replacement.email });
    });

    return { ok: true };
  });
