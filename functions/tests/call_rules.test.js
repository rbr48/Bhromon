// Call and voice-room rules. Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/call_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';
const CHANNEL = 'voice_lounge';
const ALICE = { uid: 'alice-uid', email: 'alice@x.com' };
const BOB = { uid: 'bob-uid', email: 'bob@x.com' };
const CAROL = { uid: 'carol-uid', email: 'carol@x.com' };
const EVE = { uid: 'eve-uid', email: 'eve@x.com' };
const CALL = 'call-1';
const OFFER = { type: 'offer', sdp: 'v=0 offer' };
const ANSWER = { type: 'answer', sdp: 'v=0 answer' };
const CANDIDATE = { candidate: 'candidate:1 1 udp 2122 10.0.0.1 5000 typ host', sdpMid: '0', sdpMLineIndex: 0 };
const PAIR = `${ALICE.email}__${BOB.email}`;

const seatPath = (email) => ['tours', TOUR, 'channels', CHANNEL, 'voice_participants', email];
const signalPath = (pair) => ['tours', TOUR, 'channels', CHANNEL, 'voice_signals', pair];

describe('call and voice rules', () => {
  let env;
  const as = (who) => env.authenticatedContext(who.uid, { email: who.email }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();

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
      for (const who of [ALICE, BOB, CAROL]) {
        await setDoc(doc(f, 'memberships', `${TOUR}__${who.email}`), {
          tourId: TOUR,
          email: who.email,
          role: 'member',
          status: 'active',
        });
      }
      await setDoc(doc(f, 'calls', CALL), {
        callerId: ALICE.uid,
        calleeId: BOB.uid,
        isVideo: true,
        status: 'calling',
        offer: OFFER,
        createdAt: new Date(),
      });
    });
  });

  const seedCall = async (fields) => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'calls', CALL), {
        callerId: ALICE.uid,
        calleeId: BOB.uid,
        isVideo: true,
        status: 'calling',
        offer: OFFER,
        createdAt: new Date(),
        ...fields,
      });
    });
  };

  const callRef = (who) => doc(as(who), 'calls', CALL);

  describe('creating a call', () => {
    const newCall = (overrides = {}) => ({
      callerId: ALICE.uid,
      calleeId: BOB.uid,
      isVideo: false,
      status: 'calling',
      offer: OFFER,
      createdAt: serverTimestamp(),
      ...overrides,
    });

    test('the caller can ring the callee', async () => {
      await assertSucceeds(setDoc(doc(as(ALICE), 'calls', 'new-1'), newCall()));
    });

    test('nobody can start a call in someone else\'s name', async () => {
      await assertFails(setDoc(doc(as(EVE), 'calls', 'new-2'), newCall()));
    });

    test('nobody can call themselves', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-3'), newCall({ calleeId: ALICE.uid })));
    });

    test('a call must start ringing, not already answered', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-4'), newCall({ status: 'answered' })));
    });

    test('the creation time must be the server time', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-5'), newCall({ createdAt: new Date(0) })));
    });

    test('unknown fields are refused', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-6'), newCall({ role: 'admin' })));
    });

    test('the offer must be an SDP offer within the size limit', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-7'), newCall({ offer: ANSWER })));
      await assertFails(
        setDoc(doc(as(ALICE), 'calls', 'new-8'), newCall({ offer: { type: 'offer', sdp: 'x'.repeat(65537) } })),
      );
    });

    test('the callee must be named, and the flags must be typed', async () => {
      const { calleeId, ...withoutCallee } = newCall();
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-9'), withoutCallee));
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-10'), newCall({ calleeId: 'x'.repeat(129) })));
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'new-11'), newCall({ isVideo: 'yes' })));
    });
  });

  describe('reading a call', () => {
    test('only the two parties can read it', async () => {
      await assertSucceeds(getDoc(callRef(ALICE)));
      await assertSucceeds(getDoc(callRef(BOB)));
      await assertFails(getDoc(callRef(EVE)));
      await assertFails(getDoc(doc(anon(), 'calls', CALL)));
    });
  });

  describe('moving a call along', () => {
    test('the callee answers with an SDP answer', async () => {
      await assertSucceeds(updateDoc(callRef(BOB), { status: 'answered', answer: ANSWER }));
    });

    test('only the callee can answer', async () => {
      await assertFails(updateDoc(callRef(ALICE), { status: 'answered', answer: ANSWER }));
    });

    test('an answer must carry an SDP answer', async () => {
      await assertFails(updateDoc(callRef(BOB), { status: 'answered' }));
      await assertFails(updateDoc(callRef(BOB), { status: 'answered', answer: OFFER }));
    });

    test('identity fields cannot change after the call starts', async () => {
      await assertFails(updateDoc(callRef(BOB), { status: 'answered', answer: ANSWER, calleeId: EVE.uid }));
      await assertFails(updateDoc(callRef(BOB), { status: 'answered', answer: ANSWER, callerId: BOB.uid }));
      await assertFails(updateDoc(callRef(BOB), { status: 'answered', answer: ANSWER, offer: ANSWER }));
    });

    test('the callee can decline a ringing call, and the caller cannot', async () => {
      await assertFails(updateDoc(callRef(ALICE), { status: 'declined' }));
      await assertSucceeds(updateDoc(callRef(BOB), { status: 'declined' }));
    });

    test('the caller can give up on a call nobody answered, and the callee cannot', async () => {
      await assertFails(updateDoc(callRef(BOB), { status: 'missed' }));
      await assertSucceeds(updateDoc(callRef(ALICE), { status: 'missed' }));
    });

    test('either party can hang up a call in progress, and others cannot', async () => {
      await seedCall({ status: 'answered', answer: ANSWER });
      await assertFails(updateDoc(callRef(EVE), { status: 'ended' }));
      await assertSucceeds(updateDoc(callRef(BOB), { status: 'ended' }));
    });

    test('a finished call cannot be reopened or ended twice', async () => {
      await assertSucceeds(updateDoc(callRef(ALICE), { status: 'ended' }));
      await assertFails(updateDoc(callRef(ALICE), { status: 'ended' }));
      await assertFails(updateDoc(callRef(BOB), { status: 'calling' }));
    });

    test('a declined call cannot be ended afterwards', async () => {
      await assertSucceeds(updateDoc(callRef(BOB), { status: 'declined' }));
      await assertFails(updateDoc(callRef(ALICE), { status: 'ended' }));
    });

    test('unknown statuses are refused', async () => {
      await assertFails(updateDoc(callRef(BOB), { status: 'ringing' }));
    });

    test('hang-up and decline record the end time and duration', async () => {
      await assertSucceeds(updateDoc(callRef(BOB), { status: 'declined', endedAt: serverTimestamp() }));
      await seedCall({ status: 'answered', answer: ANSWER });
      await assertSucceeds(
        updateDoc(callRef(ALICE), { status: 'ended', endedAt: serverTimestamp(), durationSeconds: 12 }),
      );
    });

    test('the end time must be the server time and the duration a whole number', async () => {
      await assertFails(updateDoc(callRef(ALICE), { status: 'ended', endedAt: new Date(0) }));
      await assertFails(updateDoc(callRef(ALICE), { status: 'ended', durationSeconds: '12' }));
    });

    test('calls are never deleted by a client', async () => {
      await assertFails(deleteDoc(callRef(ALICE)));
      await assertFails(deleteDoc(callRef(BOB)));
    });
  });

  describe('ICE candidates', () => {
    const offerCandidate = (who, id = 'c1') =>
      setDoc(doc(as(who), 'calls', CALL, 'offerCandidates', id), CANDIDATE);
    const answerCandidate = (who, id = 'a1') =>
      setDoc(doc(as(who), 'calls', CALL, 'answerCandidates', id), CANDIDATE);

    test('the caller writes offer candidates and the callee writes answer candidates', async () => {
      await assertSucceeds(offerCandidate(ALICE));
      await assertSucceeds(answerCandidate(BOB));
    });

    test('each side cannot write the other side\'s candidates', async () => {
      await assertFails(offerCandidate(BOB));
      await assertFails(answerCandidate(ALICE));
    });

    test('only the two parties can read candidates', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'calls', CALL, 'offerCandidates', 'seed'), CANDIDATE);
      });
      await assertSucceeds(getDoc(doc(as(ALICE), 'calls', CALL, 'offerCandidates', 'seed')));
      await assertSucceeds(getDoc(doc(as(BOB), 'calls', CALL, 'offerCandidates', 'seed')));
      await assertFails(getDoc(doc(as(EVE), 'calls', CALL, 'offerCandidates', 'seed')));
    });

    test('a candidate has only the expected fields and a bounded size', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', CALL, 'offerCandidates', 'x1'), { ...CANDIDATE, extra: 1 }));
      await assertFails(
        setDoc(doc(as(ALICE), 'calls', CALL, 'offerCandidates', 'x2'), { ...CANDIDATE, candidate: 'c'.repeat(2049) }),
      );
    });

    test('candidates cannot be rewritten or deleted', async () => {
      await assertSucceeds(offerCandidate(ALICE, 'once'));
      await assertFails(updateDoc(doc(as(ALICE), 'calls', CALL, 'offerCandidates', 'once'), { sdpMid: '1' }));
      await assertFails(deleteDoc(doc(as(ALICE), 'calls', CALL, 'offerCandidates', 'once')));
    });

    test('candidates cannot be attached to a call that does not exist', async () => {
      await assertFails(
        setDoc(doc(as(ALICE), 'calls', 'no-such-call', 'offerCandidates', 'c1'), CANDIDATE),
      );
    });
  });

  describe('voice seats', () => {
    const seat = (who, overrides = {}) => ({
      email: who.email,
      displayName: 'Member',
      uid: who.uid,
      isAudioMuted: false,
      isVideoOn: false,
      joinedAt: serverTimestamp(),
      lastSeenAt: serverTimestamp(),
      ...overrides,
    });

    test('a member takes and frees their own seat', async () => {
      const ref = doc(as(ALICE), ...seatPath(ALICE.email));
      await assertSucceeds(setDoc(ref, seat(ALICE)));
      await assertSucceeds(updateDoc(ref, { lastSeenAt: serverTimestamp() }));
      await assertSucceeds(deleteDoc(ref));
    });

    test('a member cannot sit in someone else\'s seat', async () => {
      await assertFails(setDoc(doc(as(ALICE), ...seatPath(BOB.email)), seat(BOB)));
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...seatPath(BOB.email)), seat(BOB));
      });
      await assertFails(deleteDoc(doc(as(ALICE), ...seatPath(BOB.email))));
    });

    test('the heartbeat must be the server time and the uid must be the caller\'s', async () => {
      const ref = doc(as(ALICE), ...seatPath(ALICE.email));
      await assertFails(setDoc(ref, seat(ALICE, { lastSeenAt: new Date() })));
      await assertFails(setDoc(ref, seat(ALICE, { uid: BOB.uid })));
    });

    test('seats have a fixed field list and bounded names', async () => {
      const ref = doc(as(ALICE), ...seatPath(ALICE.email));
      await assertFails(setDoc(ref, seat(ALICE, { role: 'admin' })));
      await assertFails(setDoc(ref, seat(ALICE, { displayName: 'x'.repeat(81) })));
    });

    test('a non-member cannot take a seat, and cannot read the room', async () => {
      await assertFails(setDoc(doc(as(EVE), ...seatPath(EVE.email)), seat(EVE)));
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...seatPath(BOB.email)), seat(BOB));
      });
      await assertFails(getDoc(doc(as(EVE), ...seatPath(BOB.email))));
    });

    test('members can read the seats', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...seatPath(BOB.email)), seat(BOB));
      });
      await assertSucceeds(getDoc(doc(as(ALICE), ...seatPath(BOB.email))));
    });
  });

  describe('voice signaling', () => {
    const offerDoc = { offer: OFFER };

    test('the two members of a pair can exchange signals', async () => {
      await assertSucceeds(setDoc(doc(as(ALICE), ...signalPath(PAIR)), offerDoc));
      await assertSucceeds(updateDoc(doc(as(BOB), ...signalPath(PAIR)), { answer: ANSWER }));
      await assertSucceeds(getDoc(doc(as(ALICE), ...signalPath(PAIR))));
    });

    test('a member outside the pair cannot read or write the signals', async () => {
      await setDoc(doc(as(ALICE), ...signalPath(PAIR)), offerDoc);
      await assertFails(getDoc(doc(as(CAROL), ...signalPath(PAIR))));
      await assertFails(updateDoc(doc(as(CAROL), ...signalPath(PAIR)), { answer: ANSWER }));
    });

    test('candidates follow the same pair rule', async () => {
      await setDoc(doc(as(ALICE), ...signalPath(PAIR)), offerDoc);
      await assertSucceeds(
        setDoc(doc(as(ALICE), ...signalPath(PAIR), 'offerCandidates', 'c1'), CANDIDATE),
      );
      await assertFails(
        setDoc(doc(as(CAROL), ...signalPath(PAIR), 'offerCandidates', 'c2'), CANDIDATE),
      );
    });

    test('a pair id must name exactly two members, one of them the caller', async () => {
      await assertFails(setDoc(doc(as(ALICE), ...signalPath(ALICE.email)), offerDoc));
      await assertFails(setDoc(doc(as(EVE), ...signalPath(PAIR)), offerDoc));
    });
  });
});
