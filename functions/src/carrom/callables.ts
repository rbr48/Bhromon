/**
 * The server side of the online carrom board. The server runs every shot: it
 * checks the striker and the turn, simulates the shot, scores it, and stores
 * the board. The phones send the shot and draw the stored board. Each change
 * runs in a transaction that reads the table first.
 *
 * The board is public, so there are no private seat documents. Bots play their
 * own shots here, and a person who runs out of time has their shot played by
 * the bot's choice.
 */

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { CarromTable, publicState, restoreTable } from './game';
import { BOT_AIM_NOISE, chooseShot } from './bot';
import { secureRandom } from '../gameTable/random';
import {
  DocData,
  DocRef,
  HttpsError,
  PlayerRow,
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
  requireIds,
  seatOfEmail,
  stepOf,
} from '../gameTable/shared';

const GAME_TYPE = 'carrom';
const SEATS = 2;

/** How long a person has to shoot before the bot's choice is played for them. */
const HUMAN_TURN_MS = 60_000;

function namesOf(players: readonly PlayerRow[]): [string, string] {
  const name = (seat: number): string => players.find((p) => p.seatIndex === seat)?.displayName ?? botName(seat);
  return [name(0), name(1)];
}

function botFlags(players: readonly PlayerRow[]): boolean[] {
  return Array.from({ length: SEATS }, (_, seat) => players.find((p) => p.seatIndex === seat)?.isBot === true);
}

function turnDeadlineFor(board: CarromTable, players: readonly PlayerRow[], nowMs: number): number | null {
  if (board.phase !== 'aiming') return null;
  return botFlags(players)[board.currentPlayer] ? null : nowMs + HUMAN_TURN_MS;
}

interface ShotInput {
  x: number;
  angle: number;
  power: number;
}

function parseShot(raw: unknown): ShotInput {
  const invalid = (): never => {
    throw new HttpsError('invalid-argument', 'That shot is not understood.');
  };
  if (typeof raw !== 'object' || raw === null) return invalid();
  const s = raw as Record<string, unknown>;
  const { x, angle, power } = s;
  if (typeof x !== 'number' || typeof angle !== 'number' || typeof power !== 'number') return invalid();
  if (!Number.isFinite(x) || !Number.isFinite(angle) || !Number.isFinite(power)) return invalid();
  if (power < 0 || power > 1) return invalid();
  return { x, angle, power };
}

/** Reads a board that is in play, in a transaction. */
async function readRunning(tx: Transaction, ref: DocRef): Promise<DocData & { players: PlayerRow[]; state: Record<string, unknown> }> {
  const snap = await tx.get(ref);
  if (!snap.exists) throw new HttpsError('not-found', 'This table no longer exists.');
  const data = snap.data() as DocData;
  if (data.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a carrom table.');
  if (data.status !== 'inProgress') throw new HttpsError('failed-precondition', 'This table is not in play.');
  return {
    ...data,
    players: (data.players ?? []) as PlayerRow[],
    state: (data.state ?? {}) as Record<string, unknown>,
  };
}

/** Stores the board after a shot or a bot's turn. */
function writeBoard(
  tx: Transaction,
  ref: DocRef,
  board: CarromTable,
  players: readonly PlayerRow[],
  nowMs: number,
  step: number,
): void {
  const update: FirebaseFirestore.UpdateData<DocData> = {
    state: publicState(board, step, turnDeadlineFor(board, players, nowMs)),
    currentTurn: board.currentPlayer,
    updatedAt: nowIso(nowMs),
    version: admin.firestore.FieldValue.increment(1),
  };
  if (board.phase === 'gameOver') {
    update.status = 'finished';
    update.winnerSeat = board.winner;
  }
  tx.update(ref, update);
}

/** Starts a waiting board: fills the empty seat with a bot, and lays out the coins. */
export const carromStart = functions
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
      if (table.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a carrom table.');
      if (table.status !== 'waiting') throw new HttpsError('failed-precondition', 'This table has already started.');
      if (String(table.hostEmail ?? '').toLowerCase() !== email) {
        throw new HttpsError('permission-denied', 'Only the host can start the table.');
      }

      const players = completeSeats((table.players ?? []) as PlayerRow[], SEATS);
      const board = CarromTable.fresh(namesOf(players));
      const nowMs = Date.now();

      tx.update(ref, {
        players,
        status: 'inProgress',
        currentTurn: board.currentPlayer,
        state: publicState(board, 1, turnDeadlineFor(board, players, nowMs)),
        updatedAt: nowIso(nowMs),
        version: admin.firestore.FieldValue.increment(1),
      });
    });

    return { ok: true };
  });

/**
 * A seated player's shot. It must be their turn, and the striker must be free
 * on the baseline. When [expectedStep] is given, a board that has moved on is
 * refused, so a stale screen cannot shoot on old information.
 */
export const carromShoot = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { tourId, gameId } = requireIds(data);
    const shot = parseShot((data as Record<string, unknown>)?.shot);
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
      if (seat === undefined) throw new HttpsError('permission-denied', 'Only seated players can shoot here.');

      const board = restoreTable(table.state, namesOf(table.players));
      if (board.phase !== 'aiming') throw new HttpsError('failed-precondition', 'This board is finished.');
      if (board.currentPlayer !== seat) throw new HttpsError('failed-precondition', 'It is not your shot.');
      if (!board.resolveShot(seat, shot.x, shot.angle, shot.power)) {
        throw new HttpsError('failed-precondition', 'The striker cannot be played from there.');
      }
      writeBoard(tx, ref, board, table.players, Date.now(), current + 1);
      return current + 1;
    });

    return { ok: true, step };
  });

/**
 * One step of the board, when a bot must shoot or a person's time has run out.
 * Any member may call it. Calls that arrive when nothing is due return "noop",
 * so duplicate calls are harmless.
 */
export const carromAdvance = functions
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
      const board = restoreTable(table.state, namesOf(table.players));
      if (board.phase !== 'aiming') return { status: 'noop', step: current };

      const seat = board.currentPlayer;
      const bot = botFlags(table.players)[seat];
      const deadline = typeof table.state.turnDeadline === 'number' ? table.state.turnDeadline : null;
      const nowMs = Date.now();
      const timedOut = deadline !== null && nowMs >= deadline;
      if (!bot && !timedOut) return { status: 'noop', step: current };

      const shot = chooseShot(board, seat, BOT_AIM_NOISE, secureRandom);
      if (!board.resolveShot(seat, shot.x, shot.angle, shot.power)) {
        throw new HttpsError('internal', 'The bot found no playable shot.');
      }
      writeBoard(tx, ref, board, table.players, nowMs, current + 1);
      return { status: bot ? 'bot' : 'auto', step: current + 1 };
    });
  });

/**
 * Leaves a board. Before the start, the seat is simply given up. Once play has
 * started, the seat passes to a bot, and the board carries on. A board with no
 * people left at all is removed.
 */
export const carromLeave = functions
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
      if (table.gameType !== GAME_TYPE) throw new HttpsError('failed-precondition', 'This is not a carrom table.');
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
        return;
      }

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
