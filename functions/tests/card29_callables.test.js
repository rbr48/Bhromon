// Online 29 table, server side. Runs the callable functions against the Firestore
// emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/card29_callables"
const admin = require('firebase-admin');
const { card29Start, card29Act, card29Advance, card29Leave } = require('../src/card29/callables');

// Each test clears the emulator project first, which can take a few seconds on its own.
jest.setTimeout(60000);

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't_card29';
const GAME = 'table1';
const HOST = 'host@x.com';
const ASHA = 'asha@x.com';
const BABU = 'babu@x.com';
const OUTSIDER = 'eve@x.com';

if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

const ctx = (email) => ({ auth: { uid: email.split('@')[0], token: { email } } });
const gameRef = () => db.collection('tours').doc(TOUR).collection('games').doc(GAME);
const seatRef = (n) => gameRef().collection('private').doc(`seat${n}`);

async function readGame() {
  return (await gameRef().get()).data();
}

async function readSeat(n) {
  return (await seatRef(n).get()).data();
}

/**
 * Every card of the deck is in exactly one place: a hand, a second half, or the
 * played pile. A card left in a hand after it was played shows up here as a
 * duplicate, which is how a stale seat document once let the deal score 33.
 */
async function expectAllCardsAccountedFor(game) {
  const held = [];
  for (let n = 0; n < 4; n++) {
    const seat = await readSeat(n);
    held.push(...seat.hand, ...seat.pending);
  }
  expect(new Set(held).size).toBe(held.length);
  expect(held.length + game.state.playedCards.length).toBe(32);
}

/** The email of the human sitting in the seat the table is waiting on. */
async function humanToAct() {
  const game = await readGame();
  return game.players.find((p) => p.seatIndex === game.state.currentTurn).email;
}

/** Advances until the table waits on a human, or nothing more is due. */
async function advanceUntilHuman(max = 200) {
  for (let i = 0; i < max; i++) {
    const step = (await readGame()).state.step;
    const result = await card29Advance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
    if (result.status === 'noop') return;
  }
  throw new Error('the table did not reach a human turn');
}

/** Pretends the waiting human's clock has run out, so the next advance plays for them. */
async function expireHumanTurn() {
  await gameRef().update({ 'state.turnDeadline': 1 });
}

beforeEach(async () => {
  await db.recursiveDelete(db.collection('tours').doc(TOUR));
  await db.collection('tours').doc(TOUR).set({ name: 'Trip', ownerEmail: 'owner@x.com' });
  for (const email of [HOST, ASHA, BABU]) {
    await db.collection('memberships').doc(`${TOUR}__${email}`).set({ tourId: TOUR, email, role: 'member', status: 'active' });
  }
  await gameRef().set({
    tourId: TOUR,
    gameType: 'card29',
    status: 'waiting',
    hostEmail: HOST,
    players: [
      { email: HOST, displayName: 'Host', seatIndex: 0, isReady: true, isHost: true, isBot: false },
      { email: ASHA, displayName: 'Asha', seatIndex: 1, isReady: true, isHost: false, isBot: false },
    ],
    maxPlayers: 4,
    currentTurn: 0,
    state: {},
    createdAt: '2026-10-27T10:00:00.000Z',
    updatedAt: '2026-10-27T10:00:00.000Z',
    version: 1,
  });
});

afterAll(async () => {
  await db.recursiveDelete(db.collection('tours').doc(TOUR));
});

describe('starting a table', () => {
  it('refuses a member who is not the host', async () => {
    await expect(card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA))).rejects.toMatchObject({
      code: 'permission-denied',
    });
  });

  it('refuses a stranger who is not a member', async () => {
    await expect(card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(OUTSIDER))).rejects.toMatchObject({
      code: 'permission-denied',
    });
  });

  it('fills the empty seats with bots, deals, and keeps the hidden cards off the public table', async () => {
    await card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    const game = await readGame();
    expect(game.status).toBe('inProgress');
    expect(game.players.map((p) => p.seatIndex)).toEqual([0, 1, 2, 3]);
    expect(game.players.filter((p) => p.isBot)).toHaveLength(2);

    const publicText = JSON.stringify(game.state);
    expect(publicText).not.toContain('"hand"');
    expect(publicText).not.toContain('"pending"');
    expect(game.state.trumpSuit).toBeNull();
    expect(game.state.step).toBe(1);

    for (let n = 0; n < 4; n++) {
      const seat = await readSeat(n);
      expect(seat.seat).toBe(n);
      expect(seat.hand).toHaveLength(4);
      expect(seat.pending).toHaveLength(4);
    }
    expect((await readSeat(0)).owner).toBe(HOST);
    expect((await readSeat(2)).owner).toBe('bot_seat_2@bhromon.fun');
  });

  it('refuses to start a table twice', async () => {
    await card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await expect(card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST))).rejects.toMatchObject({
      code: 'failed-precondition',
    });
  });
});

describe('acting at the table', () => {
  beforeEach(async () => {
    await card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
  });

  it('lets the seat whose turn it is bid, and refuses any other seat', async () => {
    const turn = await humanToAct();
    const other = turn === HOST ? ASHA : HOST;
    await expect(
      card29Act.run({ tourId: TOUR, gameId: GAME, action: { type: 'pass' }, expectedStep: 1 }, ctx(other)),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const result = await card29Act.run(
      { tourId: TOUR, gameId: GAME, action: { type: 'bid', bid: 16 }, expectedStep: 1 },
      ctx(turn),
    );
    expect(result.ok).toBe(true);
    const game = await readGame();
    expect(game.state.step).toBe(2);
    expect(game.state.highestBid).toBe(16);
  });

  it('refuses a member who is not seated at the table', async () => {
    await expect(
      card29Act.run({ tourId: TOUR, gameId: GAME, action: { type: 'pass' }, expectedStep: 1 }, ctx(BABU)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('refuses an action made on an old view of the table', async () => {
    await expect(
      card29Act.run({ tourId: TOUR, gameId: GAME, action: { type: 'pass' }, expectedStep: 99 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'aborted' });
  });

  it('refuses a malformed action', async () => {
    await expect(
      card29Act.run({ tourId: TOUR, gameId: GAME, action: { type: 'play', card: 'ZZ' }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('lets the bots move on advance, then waits on a human', async () => {
    const turn = await humanToAct();
    await card29Act.run(
      { tourId: TOUR, gameId: GAME, action: { type: 'bid', bid: 16 }, expectedStep: 1 },
      ctx(turn),
    );
    await advanceUntilHuman();
    const game = await readGame();
    const waitingOn = game.players.find((p) => p.seatIndex === game.state.currentTurn);
    expect(waitingOn.isBot).toBe(false);
  });

  it('an advance that is not due does nothing', async () => {
    const game = await readGame();
    const result = await card29Advance.run(
      { tourId: TOUR, gameId: GAME, expectedStep: game.state.step },
      ctx(HOST),
    );
    expect(result.status).toBe('noop');
    expect((await readGame()).state.step).toBe(game.state.step);
  });

  it('plays for a human whose time has run out', async () => {
    const before = await readGame();
    await expireHumanTurn();
    const result = await card29Advance.run(
      { tourId: TOUR, gameId: GAME, expectedStep: before.state.step },
      ctx(HOST),
    );
    expect(result.status).toBe('auto');
    expect((await readGame()).state.step).toBe(before.state.step + 1);
  });

  it('reports a stale advance without changing anything', async () => {
    const result = await card29Advance.run({ tourId: TOUR, gameId: GAME, expectedStep: 0 }, ctx(HOST));
    expect(result.status).toBe('stale');
  });
});

describe('leaving a table', () => {
  it('hands a seat in play to a bot, and keeps the leaver out of its cards', async () => {
    await card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await card29Leave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));

    const game = await readGame();
    expect(game.players.find((p) => p.seatIndex === 1).isBot).toBe(true);
    expect(game.players.some((p) => p.email === ASHA)).toBe(false);
    expect((await readSeat(1)).owner).toBe('bot_seat_1@bhromon.fun');
  });

  it('removes the table once no person is left in it', async () => {
    await card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await card29Leave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));
    await card29Leave.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    expect((await gameRef().get()).exists).toBe(false);
    expect((await seatRef(0).get()).exists).toBe(false);
  });

  it('removes a waiting seat, and removes the table when the host leaves it', async () => {
    await card29Leave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));
    const game = await readGame();
    expect(game.players.map((p) => p.email)).toEqual([HOST]);

    await card29Leave.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    expect((await gameRef().get()).exists).toBe(false);
  });
});

describe('a deal played through the server', () => {
  it('plays out with the table playing for people when their time runs out, and the totals hold', async () => {
    await card29Start.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    let deals = 0;

    for (let i = 0; i < 2000; i++) {
      const game = await readGame();
      const { phase, step } = game.state;
      await expectAllCardsAccountedFor(game);
      if (phase === 'matchOver') break;
      if (phase === 'roundOver') {
        // Every deal scores exactly 29 points, and one side takes one pip.
        expect(game.state.teamPoints[0] + game.state.teamPoints[1]).toBe(29);
        expect(game.state.matchPips[0] + game.state.matchPips[1]).toBe(deals + 1);
        deals++;
        if (deals === 2) break;
        await card29Act.run({ tourId: TOUR, gameId: GAME, action: { type: 'nextDeal' }, expectedStep: step }, ctx(HOST));
        continue;
      }
      if (game.state.turnDeadline !== null) await expireHumanTurn();
      await card29Advance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
    }

    expect(deals).toBe(2);
    const game = await readGame();
    if (!game.state.trumpRevealed) expect(game.state.trumpSuit).toBeNull();
  }, 240000);
});
