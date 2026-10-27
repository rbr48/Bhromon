// Online Teen Patti table rules. Needs the Firestore emulator:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/teen_patti_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';

describe('Online Teen Patti table rules', () => {
  let env;
  const db = (email) => env.authenticatedContext(email.split('@')[0], { email }).firestore();
  const guest = () => env.unauthenticatedContext().firestore();
  const game = (f, id) => doc(f, 'tours', TOUR, 'games', id);
  const seat = (f, id, n) => doc(f, 'tours', TOUR, 'games', id, 'private', `seat${n}`);

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
        gameType: 'teen_patti',
        status: 'waiting',
        hostEmail: 'host@x.com',
        players: players('host@x.com', 'asha@x.com'),
        maxPlayers: 4,
        currentTurn: 0,
        state: {},
        version: 1,
      });
      await setDoc(game(f, 'live'), {
        ...base,
        gameType: 'teen_patti',
        status: 'inProgress',
        hostEmail: 'host@x.com',
        players: players('host@x.com', 'asha@x.com', 'babu@x.com', 'bot_seat_3@bhromon.fun'),
        maxPlayers: 4,
        currentTurn: 1,
        state: { step: 4, phase: 'betting', pot: 40 },
        version: 5,
      });
      await setDoc(seat(f, 'live', 0), { owner: 'host@x.com', seat: 0, hand: ['AS', '9S', '4D'] });
      await setDoc(seat(f, 'live', 1), { owner: 'asha@x.com', seat: 1, hand: ['2H', '7D', '9C'] });
    });
  });

  describe('a waiting table', () => {
    test('a member can join it', async () => {
      await assertSucceeds(
        updateDoc(game(db('babu@x.com'), 'waiting'), {
          players: players('host@x.com', 'asha@x.com', 'babu@x.com'),
          updatedAt: '2026-10-27T10:01:00.000Z',
        }),
      );
    });

    test('a member cannot start it by changing its status', async () => {
      await assertFails(updateDoc(game(db('host@x.com'), 'waiting'), { status: 'inProgress' }));
    });

    test('a member cannot write the game state before it starts', async () => {
      await assertFails(updateDoc(game(db('host@x.com'), 'waiting'), { state: { step: 9 } }));
    });

    test('the host can create a waiting table, and nobody can create one already in play', async () => {
      const base = { tourId: TOUR, gameType: 'teen_patti', hostEmail: 'host@x.com', players: [], maxPlayers: 4, currentTurn: 0 };
      await assertSucceeds(setDoc(game(db('host@x.com'), 'new1'), { ...base, status: 'waiting', state: {} }));
      await assertFails(setDoc(game(db('host@x.com'), 'new2'), { ...base, status: 'inProgress', state: {} }));
      await assertFails(setDoc(game(db('host@x.com'), 'new3'), { ...base, status: 'waiting', state: { step: 1 } }));
    });
  });

  describe('a table in play', () => {
    test('no member can change its state', async () => {
      await assertFails(updateDoc(game(db('asha@x.com'), 'live'), { state: { step: 4, phase: 'betting', pot: 0 } }));
      await assertFails(updateDoc(game(db('host@x.com'), 'live'), { state: { step: 5 } }));
      await assertFails(updateDoc(game(db('host@x.com'), 'live'), { winnerSeat: 2 }));
    });

    test('a member who is not the host cannot delete it', async () => {
      await assertFails(deleteDoc(game(db('asha@x.com'), 'live')));
    });

    test('the host can delete it', async () => {
      await assertSucceeds(deleteDoc(game(db('host@x.com'), 'live')));
    });

    test('a waiting table may be deleted by any member', async () => {
      await assertSucceeds(deleteDoc(game(db('asha@x.com'), 'waiting')));
    });

    test('a non-member can read nothing from the table', async () => {
      await assertFails(getDoc(game(db('eve@x.com'), 'live')));
      await assertFails(getDoc(game(guest(), 'live')));
    });

    test('members can read the public table', async () => {
      await assertSucceeds(getDoc(game(db('babu@x.com'), 'live')));
    });
  });

  describe('private seat cards', () => {
    test('a seat owner can read their own cards', async () => {
      await assertSucceeds(getDoc(seat(db('host@x.com'), 'live', 0)));
      await assertSucceeds(getDoc(seat(db('asha@x.com'), 'live', 1)));
    });

    test("other members cannot read someone else's cards", async () => {
      await assertFails(getDoc(seat(db('asha@x.com'), 'live', 0)));
      await assertFails(getDoc(seat(db('babu@x.com'), 'live', 1)));
    });

    test('a non-member and a guest cannot read any seat', async () => {
      await assertFails(getDoc(seat(db('eve@x.com'), 'live', 0)));
      await assertFails(getDoc(seat(guest(), 'live', 0)));
    });

    test("nobody can write a seat's cards, not even its owner", async () => {
      await assertFails(updateDoc(seat(db('host@x.com'), 'live', 0), { hand: ['AS', 'AH', 'AD'] }));
      await assertFails(setDoc(seat(db('asha@x.com'), 'live', 1), { owner: 'asha@x.com', seat: 1, hand: ['JH'] }));
      await assertFails(deleteDoc(seat(db('host@x.com'), 'live', 0)));
    });
  });
});
