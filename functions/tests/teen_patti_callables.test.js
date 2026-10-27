// Online Teen Patti table, server side. Runs the callable functions against the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/teen_patti_callables"
const admin = require('firebase-admin');
const { teenPattiStart, teenPattiAct, teenPattiAdvance, teenPattiLeave } = require('../src/teenPatti/callables');

// Each test clears the emulator project first, which can take a few seconds on its own.
jest.setTimeout(60000);

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't_teen_patti';
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

/** The email of the person whose seat the table is waiting on. */
async function humanToAct() {
  const game = await readGame();
  return game.players.find((p) => p.seatIndex === game.state.currentTurn).email;
}

/** The chips and the pot add up to what the table started with, plus any rebuys. */
function expectBooksBalance(state) {
  const chips = state.seats.reduce((sum, s) => sum + s.chips, 0);
  expect(chips + state.pot).toBe(4 * 500 + state.totalInjected);
}

/** No seat's cards appear in the public state, except the hands shown at a showdown. */
async function expectHiddenCardsStayHidden(state) {
  const shown = JSON.stringify(state);
  const revealed = new Set(Object.keys(state.revealed ?? {}));
  for (let n = 0; n < 4; n++) {
    if (revealed.has(String(n))) continue;
    const seat = await readSeat(n);
    for (const card of seat.hand) expect(shown.includes(`"${card}"`)).toBe(false);
  }
}

/** Advances until the table waits on a person, or nothing more is due. */
async function advanceUntilHuman(max = 200) {
  for (let i = 0; i < max; i++) {
    const step = (await readGame()).state.step;
    const result = await teenPattiAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
    if (result.status === 'noop') return;
  }
  throw new Error('the table did not reach a human turn');
}

/** Pretends the waiting person's clock has run out, so the next advance plays for them. */
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
    gameType: 'teen_patti',
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
    await expect(teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA))).rejects.toMatchObject({
      code: 'permission-denied',
    });
  });

  it('refuses a stranger who is not a member', async () => {
    await expect(teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(OUTSIDER))).rejects.toMatchObject({
      code: 'permission-denied',
    });
  });

  it('fills the empty seats with bots, deals every seat, and keeps the cards off the public table', async () => {
    await teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    const game = await readGame();
    expect(game.status).toBe('inProgress');
    expect(game.players.map((p) => p.seatIndex)).toEqual([0, 1, 2, 3]);
    expect(game.players.filter((p) => p.isBot)).toHaveLength(2);

    expect(JSON.stringify(game.state)).not.toContain('"hand"');
    expect(game.state.phase).toBe('betting');
    expect(game.state.step).toBe(1);
    expect(game.state.pot).toBe(40);
    expect(game.state.currentTurn).toBe(1);
    expectBooksBalance(game.state);

    const dealt = [];
    for (let n = 0; n < 4; n++) {
      const seat = await readSeat(n);
      expect(seat.seat).toBe(n);
      expect(seat.hand).toHaveLength(3);
      dealt.push(...seat.hand);
    }
    expect(new Set(dealt).size).toBe(12);
    expect((await readSeat(0)).owner).toBe(HOST);
    expect((await readSeat(2)).owner).toBe('bot_seat_2@bhromon.fun');
  });

  it('refuses to start a table twice', async () => {
    await teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await expect(teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST))).rejects.toMatchObject({
      code: 'failed-precondition',
    });
  });
});

describe('acting at the table', () => {
  beforeEach(async () => {
    await teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
  });

  it('lets the seat whose turn it is bet, and refuses any other seat', async () => {
    const turn = await humanToAct();
    const other = turn === HOST ? ASHA : HOST;
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'bet' }, expectedStep: 1 }, ctx(other)),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const result = await teenPattiAct.run(
      { tourId: TOUR, gameId: GAME, action: { type: 'bet' }, expectedStep: 1 },
      ctx(turn),
    );
    expect(result.ok).toBe(true);
    const game = await readGame();
    expect(game.state.step).toBe(2);
    expect(game.state.pot).toBe(50);
    expectBooksBalance(game.state);
  });

  it('lets a seated person look at their cards off their turn, because looking does not use a turn', async () => {
    await teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'see' }, expectedStep: 1 }, ctx(HOST));
    const game = await readGame();
    expect(game.state.seats[0].isSeen).toBe(true);
    expect(game.state.currentTurn).toBe(1);
  });

  it('refuses a member who is not seated at the table', async () => {
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'pack' }, expectedStep: 1 }, ctx(BABU)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('refuses an action made on an old view of the table', async () => {
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'pack' }, expectedStep: 99 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'aborted' });
  });

  it('refuses a malformed action', async () => {
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'bet2' }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'sideshowReply' }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('refuses a rebuy while the hand is on, and a new hand before the last one is over', async () => {
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'rebuy' }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(
      teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'nextHand' }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  it('lets the bots move on advance, then waits on a person', async () => {
    const turn = await humanToAct();
    await teenPattiAct.run({ tourId: TOUR, gameId: GAME, action: { type: 'bet' }, expectedStep: 1 }, ctx(turn));
    await advanceUntilHuman();
    const game = await readGame();
    const waitingOn = game.players.find((p) => p.seatIndex === game.state.currentTurn);
    expect(waitingOn.isBot).toBe(false);
    expectBooksBalance(game.state);
  });

  it('an advance that is not due does nothing', async () => {
    const game = await readGame();
    const result = await teenPattiAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: game.state.step }, ctx(HOST));
    expect(result.status).toBe('noop');
    expect((await readGame()).state.step).toBe(game.state.step);
  });

  it('packs for a person whose time has run out', async () => {
    const before = await readGame();
    await expireHumanTurn();
    const result = await teenPattiAdvance.run(
      { tourId: TOUR, gameId: GAME, expectedStep: before.state.step },
      ctx(HOST),
    );
    expect(result.status).toBe('auto');
    const after = await readGame();
    expect(after.state.step).toBe(before.state.step + 1);
    expect(after.state.seats[before.state.currentTurn].isFolded).toBe(true);
  });

  it('reports a stale advance without changing anything', async () => {
    const result = await teenPattiAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: 0 }, ctx(HOST));
    expect(result.status).toBe('stale');
  });
});

describe('a hand played through the server', () => {
  it('plays three hands to the end, keeps the books, and never shows a hidden card', async () => {
    await teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    let nextHands = 0;

    for (let i = 0; i < 4000 && nextHands < 3; i++) {
      const game = await readGame();
      const { phase, step } = game.state;
      expectBooksBalance(game.state);
      await expectHiddenCardsStayHidden(game.state);

      if (phase === 'roundOver') {
        await teenPattiAct.run(
          { tourId: TOUR, gameId: GAME, action: { type: 'nextHand' }, expectedStep: step },
          ctx(HOST),
        );
        nextHands++;
        continue;
      }
      if (game.state.turnDeadline !== null) {
        if (i % 2 === 0) {
          // A person bets now and then; otherwise their time runs out.
          await teenPattiAct
            .run(
              { tourId: TOUR, gameId: GAME, action: { type: 'bet' }, expectedStep: step },
              ctx(await humanToAct()),
            )
            .catch(() => undefined);
        } else {
          await expireHumanTurn();
        }
      }
      await teenPattiAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
    }

    expect(nextHands).toBe(3);
    const game = await readGame();
    expect(game.state.handNumber).toBe(4);
    expectBooksBalance(game.state);
  }, 240000);
});

describe('leaving a table', () => {
  it('hands a seat in play to a bot, and the seat no longer belongs to the leaver', async () => {
    await teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await teenPattiLeave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));

    const game = await readGame();
    expect(game.players.find((p) => p.seatIndex === 1).isBot).toBe(true);
    expect(game.players.some((p) => p.email === ASHA)).toBe(false);
    expect((await readSeat(1)).owner).toBe('bot_seat_1@bhromon.fun');
    // Seat 1 was the one to act, so it packs and the turn passes on.
    expect(game.state.seats[1].isFolded).toBe(true);
    expect(game.state.currentTurn).toBe(2);
    expectBooksBalance(game.state);
  });

  it('removes the table once no person is left in it', async () => {
    await teenPattiStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await teenPattiLeave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));
    await teenPattiLeave.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    expect((await gameRef().get()).exists).toBe(false);
    expect((await seatRef(0).get()).exists).toBe(false);
  });

  it('removes a waiting seat, and removes the table when the host leaves it', async () => {
    await teenPattiLeave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));
    const game = await readGame();
    expect(game.players.map((p) => p.email)).toEqual([HOST]);

    await teenPattiLeave.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    expect((await gameRef().get()).exists).toBe(false);
  });
});
