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
import * as functions from 'firebase-functions/v1';
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

const GAME_TYPE = 'card29';

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
      const seat = seatOfEmail(table.players, email);
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
 * Takes a person's seat off a 29 table. Before the deal the seat is given up.
 * Once play has started, the seat passes to a bot so the table keeps going.
 * A table with no people left at all is removed.
 *
 * When [closeLobbyOnHostLeave] is set, a lobby closes when its host leaves, as
 * the app does. Otherwise the host passes on to someone still at the table.
 */
export async function leave29Table(
  tourId: string,
  gameId: string,
  email: string,
  options: { closeLobbyOnHostLeave: boolean },
): Promise<void> {
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
      const people = remaining.filter((p) => !p.isBot);
      if (people.length === 0 || (options.closeLobbyOnHostLeave && table.hostEmail === email)) {
        tx.delete(ref);
        return;
      }
      if (table.hostEmail !== email) {
        tx.update(ref, { players: remaining, updatedAt: nowIso(nowMs) });
        return;
      }
      const newHost = people[0].email;
      tx.update(ref, {
        players: remaining.map((p) => ({ ...p, isHost: p.email === newHost })),
        hostEmail: newHost,
        updatedAt: nowIso(nowMs),
      });
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
}

export const card29Leave = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const { tourId, gameId } = requireIds(data);
    const email = callerEmail(context);
    await assertMember(tourId, email);
    await leave29Table(tourId, gameId, email, { closeLobbyOnHostLeave: true });
    return { ok: true };
  });
