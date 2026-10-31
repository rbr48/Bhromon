// Online carrom board rules. Needs the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/carrom_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';

describe('Online carrom board rules', () => {
  let env;
  const db = (email) => env.authenticatedContext(email.split('@')[0], { email, email_verified: true }).firestore();
  const guest = () => env.unauthenticatedContext().firestore();
  const game = (f, id) => doc(f, 'tours', TOUR, 'games', id);

  const players = (...emails) =>
    emails.map((email, i) => ({
      email,
      displayName: email.split('@')[0],
      seatIndex: i,
      isReady: true,
      isHost: i === 0,
      isBot: false,
    }));

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  afterAll(async () => {
    await env.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'tours', TOUR), { name: 'Trip', ownerEmail: 'owner@x.com' });
      for (const email of ['host@x.com', 'asha@x.com', 'babu@x.com']) {
        await setDoc(doc(f, 'memberships', `${TOUR}__${email}`), {
          tourId: TOUR,
          email,
          role: 'member',
          status: 'active',
        });
      }
      const base = { tourId: TOUR, updatedAt: '2026-10-27T10:00:00.000Z', createdAt: '2026-10-27T10:00:00.000Z' };
      await setDoc(game(f, 'waiting'), {
        ...base,
        gameType: 'carrom',
        status: 'waiting',
        hostEmail: 'host@x.com',
        players: players('host@x.com', 'asha@x.com'),
        maxPlayers: 2,
        currentTurn: 0,
        state: {},
        version: 1,
      });
      await setDoc(game(f, 'live'), {
        ...base,
        gameType: 'carrom',
        status: 'inProgress',
        hostEmail: 'host@x.com',
        players: players('host@x.com', 'asha@x.com'),
        maxPlayers: 2,
        currentTurn: 0,
        state: { step: 3, phase: 'aiming', currentPlayer: 0 },
        version: 4,
      });
    });
  });

  describe('a waiting board', () => {
    test('a member can join it', async () => {
      await assertSucceeds(
        updateDoc(game(db('babu@x.com'), 'waiting'), {
          players: players('host@x.com', 'asha@x.com', 'babu@x.com'),
          updatedAt: '2026-10-27T10:01:00.000Z',
        }),
      );
    });

    test('a member cannot start it, or write its state, by changing the fields directly', async () => {
      await assertFails(updateDoc(game(db('host@x.com'), 'waiting'), { status: 'inProgress' }));
      await assertFails(updateDoc(game(db('host@x.com'), 'waiting'), { state: { step: 9 } }));
    });

    test('the host can create a waiting board, and nobody can create one already in play', async () => {
      const base = { tourId: TOUR, gameType: 'carrom', hostEmail: 'host@x.com', players: [], maxPlayers: 2, currentTurn: 0 };
      await assertSucceeds(setDoc(game(db('host@x.com'), 'new1'), { ...base, status: 'waiting', state: {} }));
      await assertFails(setDoc(game(db('host@x.com'), 'new2'), { ...base, status: 'inProgress', state: {} }));
    });
  });

  describe('a board in play', () => {
    test('no member can change its state, so a shot cannot be forged', async () => {
      await assertFails(updateDoc(game(db('asha@x.com'), 'live'), { state: { step: 4, currentPlayer: 1 } }));
      await assertFails(updateDoc(game(db('host@x.com'), 'live'), { winnerSeat: 1 }));
    });

    test('a member who is not the host cannot delete it, and the host can', async () => {
      await assertFails(deleteDoc(game(db('asha@x.com'), 'live')));
      await assertSucceeds(deleteDoc(game(db('host@x.com'), 'live')));
    });

    test('a non-member can read nothing, and members can read the public board', async () => {
      await assertFails(getDoc(game(db('eve@x.com'), 'live')));
      await assertFails(getDoc(game(guest(), 'live')));
      await assertSucceeds(getDoc(game(db('babu@x.com'), 'live')));
    });
  });
});
