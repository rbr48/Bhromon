// Online carrom board, server side. Runs the callable functions against the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/carrom_callables"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { carromStart, carromShoot, carromAdvance, carromLeave } = require('../src/carrom/callables');

// Each test clears the emulator project first, and bot shots take a moment to choose.
jest.setTimeout(120000);

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't_carrom';
const GAME = 'board1';
const HOST = 'host@x.com';
const ASHA = 'asha@x.com';
const BABU = 'babu@x.com';
const OUTSIDER = 'eve@x.com';

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID });
}
const db = getFirestore();

const ctx = (email) => ({ auth: { uid: email.split('@')[0], token: { email } } });
const gameRef = () => db.collection('tours').doc(TOUR).collection('games').doc(GAME);

async function readGame() {
  return (await gameRef().get()).data();
}

/** Every piece is on the board or in exactly one pocket, and the queen is counted once. */
function expectAccounted(state) {
  const flagged = state.pieces.filter((p) => p.type !== 'striker' && p.pocketed).length;
  const listed = state.pocketed['0'].length + state.pocketed['1'].length;
  const queenDown = state.pieces.find((p) => p.type === 'queen').pocketed ? 1 : 0;
  expect(flagged).toBe(listed + queenDown);
  expect(state.pieces).toHaveLength(20);
  expect(new Set(state.pieces.map((p) => p.id)).size).toBe(20);
}

/** Plays through whatever is due: a bot's shot, or a person whose time has run out. */
async function playUntilHuman(max = 50) {
  for (let i = 0; i < max; i++) {
    const game = await readGame();
    const { step, phase } = game.state;
    if (phase !== 'aiming') return;
    const seat = game.state.currentPlayer;
    const isBot = game.players.find((p) => p.seatIndex === seat).isBot;
    if (!isBot) return;
    await carromAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
  }
}

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
    gameType: 'carrom',
    status: 'waiting',
    hostEmail: HOST,
    players: [{ email: HOST, displayName: 'Host', seatIndex: 0, isReady: true, isHost: true, isBot: false }],
    maxPlayers: 2,
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

describe('starting a board', () => {
  it('refuses a member who is not the host, and a stranger', async () => {
    await gameRef().update({ players: [
      { email: HOST, displayName: 'Host', seatIndex: 0, isReady: true, isHost: true, isBot: false },
      { email: ASHA, displayName: 'Asha', seatIndex: 1, isReady: true, isHost: false, isBot: false },
    ] });
    await expect(carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA))).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(OUTSIDER))).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('fills the empty seat with a bot, lays out the board, and says whose shot it is', async () => {
    await carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    const game = await readGame();
    expect(game.status).toBe('inProgress');
    expect(game.players.map((p) => p.seatIndex)).toEqual([0, 1]);
    expect(game.players[1].isBot).toBe(true);
    expect(game.state.phase).toBe('aiming');
    expect(game.state.step).toBe(1);
    expect(game.state.currentPlayer).toBe(0);
    expect(game.state.pieces).toHaveLength(20);
    expect(typeof game.state.turnDeadline).toBe('number');
    expectAccounted(game.state);
  });

  it('refuses to start a board twice', async () => {
    await carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await expect(carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST))).rejects.toMatchObject({ code: 'failed-precondition' });
  });
});

describe('shooting', () => {
  beforeEach(async () => {
    await carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
  });

  it('refuses a shot from someone who is not seated, and a shot out of turn', async () => {
    await expect(
      carromShoot.run({ tourId: TOUR, gameId: GAME, shot: { x: 0.5, angle: -Math.PI / 2, power: 0.5 }, expectedStep: 1 }, ctx(BABU)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    await gameRef().update({ 'state.currentPlayer': 1 });
    await expect(
      carromShoot.run({ tourId: TOUR, gameId: GAME, shot: { x: 0.5, angle: -Math.PI / 2, power: 0.5 }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  it('refuses a malformed shot, and a shot made on an old view of the board', async () => {
    await expect(
      carromShoot.run({ tourId: TOUR, gameId: GAME, shot: { x: 0.5, angle: -1, power: 2 }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      carromShoot.run({ tourId: TOUR, gameId: GAME, shot: { angle: -1, power: 0.5 }, expectedStep: 1 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      carromShoot.run({ tourId: TOUR, gameId: GAME, shot: { x: 0.5, angle: -1, power: 0.5 }, expectedStep: 99 }, ctx(HOST)),
    ).rejects.toMatchObject({ code: 'aborted' });
  });

  it('plays the shot on the server, scores it, and stores the board', async () => {
    const result = await carromShoot.run(
      { tourId: TOUR, gameId: GAME, shot: { x: 0.5, angle: -Math.PI / 2, power: 0.6 }, expectedStep: 1 },
      ctx(HOST),
    );
    expect(result.ok).toBe(true);
    const game = await readGame();
    expect(game.state.step).toBe(2);
    expect(game.state.lastShot).toMatchObject({ shooter: 0, x: 0.5, angle: -Math.PI / 2, power: 0.6 });
    // The striker's starting velocity, so the phones replay the shot exactly.
    expect(game.state.lastShot.vx).toBe(Math.cos(-Math.PI / 2) * 2.1799999999999997);
    expect(game.state.lastShot.vy).toBe(Math.sin(-Math.PI / 2) * 2.1799999999999997);
    expect(game.state.phase === 'aiming' || game.state.phase === 'gameOver').toBe(true);
    expectAccounted(game.state);
  });

  it('a bot takes its turn on advance, and a person whose time has run out has a shot played for them', async () => {
    await carromShoot.run(
      { tourId: TOUR, gameId: GAME, shot: { x: 0.5, angle: -Math.PI / 2, power: 0.6 }, expectedStep: 1 },
      ctx(HOST),
    );
    const afterShot = await readGame();
    if (afterShot.state.phase === 'aiming' && afterShot.state.currentPlayer === 1) {
      const bot = await carromAdvance.run(
        { tourId: TOUR, gameId: GAME, expectedStep: afterShot.state.step },
        ctx(HOST),
      );
      expect(bot.status).toBe('bot');
    }
    await playUntilHuman();
    const game = await readGame();
    if (game.state.phase !== 'aiming') return;
    expect(game.state.currentPlayer).toBe(0);
    const quiet = await carromAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: game.state.step }, ctx(HOST));
    expect(quiet.status).toBe('noop');
    await expireHumanTurn();
    const timed = await carromAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: game.state.step }, ctx(HOST));
    expect(timed.status).toBe('auto');
    expectAccounted((await readGame()).state);
  });
});

describe('a board played through the server', () => {
  it('plays shots to the end of the board, keeping every coin accounted for', async () => {
    await carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    for (let i = 0; i < 40; i++) {
      const game = await readGame();
      const { phase, step } = game.state;
      expectAccounted(game.state);
      if (phase === 'gameOver') break;
      const seat = game.state.currentPlayer;
      const isBot = game.players.find((p) => p.seatIndex === seat).isBot;
      if (isBot) {
        await carromAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
      } else {
        // The person's shot runs out of time, and the table plays the bot's choice for them.
        await expireHumanTurn();
        await carromAdvance.run({ tourId: TOUR, gameId: GAME, expectedStep: step }, ctx(HOST));
      }
    }
    const game = await readGame();
    expectAccounted(game.state);
    if (game.state.phase === 'gameOver') {
      expect(game.status).toBe('finished');
      expect(game.winnerSeat).toBe(game.state.winner);
    }
  }, 240000);
});

describe('leaving a board', () => {
  it('hands the seat to a bot, and removes the board once no person is left', async () => {
    await gameRef().update({ players: [
      { email: HOST, displayName: 'Host', seatIndex: 0, isReady: true, isHost: true, isBot: false },
      { email: ASHA, displayName: 'Asha', seatIndex: 1, isReady: true, isHost: false, isBot: false },
    ] });
    await carromStart.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    await carromLeave.run({ tourId: TOUR, gameId: GAME }, ctx(ASHA));
    const game = await readGame();
    expect(game.players.find((p) => p.seatIndex === 1).isBot).toBe(true);
    expect(game.players.some((p) => p.email === ASHA)).toBe(false);

    await carromLeave.run({ tourId: TOUR, gameId: GAME }, ctx(HOST));
    expect((await gameRef().get()).exists).toBe(false);
  });
});
