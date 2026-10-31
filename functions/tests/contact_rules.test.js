// Contact and directory rules: people reach only the members of a tour they
// share. Needs the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/contact_rules"
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, setDoc, updateDoc, addDoc, collection, query, where, serverTimestamp } = require('firebase/firestore');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tour_a';
const OTHER_TOUR = 'tour_b';
const CODE = 'JOINCODE';
const OWNER = { uid: 'owner-uid', email: 'owner@x.com' };
const ALICE = { uid: 'alice-uid', email: 'alice@x.com' };
const BOB = { uid: 'bob-uid', email: 'bob@x.com' };
const CAROL = { uid: 'carol-uid', email: 'carol@x.com' };
const EVE = { uid: 'eve-uid', email: 'eve@x.com' };
const CHAT = `${ALICE.uid}_${BOB.uid}`;

describe('contact and directory rules', () => {
  let env;
  const as = (who) => env.authenticatedContext(who.uid, { email: who.email, email_verified: true }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();

  // A chat or call between two people, bound to the tour they share.
  const sharedChat = (a, b, tourId = TOUR) => ({
    participants: [a.uid, b.uid],
    sharedTourId: tourId,
    memberEmails: { [a.uid]: a.email, [b.uid]: b.email },
  });

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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Sajek', ownerEmail: OWNER.email, ownerUid: OWNER.uid, inviteCode: CODE });
      await setDoc(doc(f, 'tours', OTHER_TOUR), { name: 'Sylhet', ownerEmail: EVE.email, ownerUid: EVE.uid, inviteCode: 'OTHERCODE' });
      await setDoc(doc(f, 'invites', CODE), { tourId: TOUR, code: CODE });
      const row = (tourId, who, role) =>
        setDoc(doc(f, 'memberships', `${tourId}__${who.email}`), {
          tourId, email: who.email, uid: who.uid, role, status: 'active', displayName: who.uid,
        });
      await row(TOUR, OWNER, 'owner');
      await row(TOUR, ALICE, 'member');
      await row(TOUR, BOB, 'member');
      // Carol is in no tour with Alice. Eve runs a tour of her own.
      await row(OTHER_TOUR, EVE, 'owner');
      await setDoc(doc(f, 'explorer_profiles', ALICE.uid), { displayName: 'Alice', tier: 'unverified' });
      await setDoc(doc(f, 'explorer_profiles', BOB.uid), { displayName: 'Bob', tier: 'unverified' });
      await setDoc(doc(f, 'explorer_profiles', CAROL.uid), { displayName: 'Carol', tier: 'unverified' });
      await setDoc(doc(f, 'users', BOB.uid), { email: BOB.email });
      await setDoc(doc(f, 'trip_logs', 'carol-diary'), { authorId: CAROL.uid, title: 'Private to Carol', visibility: 'community' });
    });
  });

  describe('opening a chat', () => {
    test('two members of one tour can open a chat', async () => {
      await assertSucceeds(setDoc(doc(as(ALICE), 'chats', CHAT), { ...sharedChat(ALICE, BOB), lastMessage: 'hi' }));
    });

    test('nobody can open a chat with someone outside the tour', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'chats', `${ALICE.uid}_${CAROL.uid}`), sharedChat(ALICE, CAROL)));
    });

    test('a chat must name the tour the two share', async () => {
      const { sharedTourId, ...noTour } = sharedChat(ALICE, BOB);
      await assertFails(setDoc(doc(as(ALICE), 'chats', CHAT), noTour));
    });

    test('nobody can claim a tour they are not in', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'chats', CHAT), sharedChat(ALICE, BOB, OTHER_TOUR)));
    });

    test('a uid cannot be paired with someone else\'s email', async () => {
      // Bob's uid, Carol's email: Carol is not in the tour.
      const claim = { ...sharedChat(ALICE, BOB), memberEmails: { [ALICE.uid]: ALICE.email, [BOB.uid]: CAROL.email } };
      await assertFails(setDoc(doc(as(ALICE), 'chats', CHAT), claim));
    });

    test('nobody opens a chat in someone else\'s name', async () => {
      await assertFails(setDoc(doc(as(EVE), 'chats', CHAT), sharedChat(ALICE, BOB)));
    });
  });

  describe('messages', () => {
    beforeEach(async () => {
      await setDoc(doc(as(ALICE), 'chats', CHAT), sharedChat(ALICE, BOB));
    });

    test('members of the tour exchange messages', async () => {
      await assertSucceeds(addDoc(collection(as(ALICE), 'chats', CHAT, 'messages'), {
        senderId: ALICE.uid, type: 'text', text: 'Bus at six', timestamp: serverTimestamp(),
      }));
      await assertSucceeds(getDocs(collection(as(BOB), 'chats', CHAT, 'messages')));
    });

    test('someone outside the chat reads and writes nothing in it', async () => {
      await assertFails(getDocs(collection(as(EVE), 'chats', CHAT, 'messages')));
      await assertFails(addDoc(collection(as(EVE), 'chats', CHAT, 'messages'), {
        senderId: EVE.uid, type: 'text', text: 'hi', timestamp: serverTimestamp(),
      }));
    });

    test('once a person leaves the tour, the chat is closed to them', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'memberships', `${TOUR}__${BOB.email}`), {
          tourId: TOUR, email: BOB.email, uid: BOB.uid, role: 'member', status: 'invited',
        });
      });
      await assertFails(getDocs(collection(as(BOB), 'chats', CHAT, 'messages')));
      await assertFails(addDoc(collection(as(ALICE), 'chats', CHAT, 'messages'), {
        senderId: ALICE.uid, type: 'text', text: 'still there?', timestamp: serverTimestamp(),
      }));
    });

    test('an old chat from before tours (no shared tour) is closed', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'chats', 'old_chat'), { participants: [ALICE.uid, CAROL.uid] });
      });
      await assertFails(addDoc(collection(as(ALICE), 'chats', 'old_chat', 'messages'), {
        senderId: ALICE.uid, type: 'text', text: 'old friend', timestamp: serverTimestamp(),
      }));
    });

    test('an old chat opens again only when its people share a tour now', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'chats', 'old_chat'), { participants: [ALICE.uid, BOB.uid] });
      });
      await assertSucceeds(updateDoc(doc(as(ALICE), 'chats', 'old_chat'), sharedChat(ALICE, BOB)));
      await assertSucceeds(addDoc(collection(as(ALICE), 'chats', 'old_chat', 'messages'), {
        senderId: ALICE.uid, type: 'text', text: 'back in touch', timestamp: serverTimestamp(),
      }));
    });

    test('an old chat cannot be claimed for someone outside the tour', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'chats', 'old_chat'), { participants: [ALICE.uid, CAROL.uid] });
      });
      await assertFails(updateDoc(doc(as(ALICE), 'chats', 'old_chat'), sharedChat(ALICE, CAROL)));
    });
  });

  describe('calls', () => {
    const call = (a, b, tourId = TOUR) => ({
      ...sharedChat(a, b, tourId),
      callerId: a.uid,
      calleeId: b.uid,
      isVideo: false,
      status: 'calling',
      offer: { type: 'offer', sdp: 'v=0' },
      createdAt: serverTimestamp(),
    });

    test('members of the tour can ring each other', async () => {
      await assertSucceeds(setDoc(doc(as(ALICE), 'calls', 'c1'), call(ALICE, BOB)));
    });

    test('nobody rings someone outside the tour', async () => {
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'c2'), call(ALICE, CAROL)));
    });

    test('a call cannot claim a uid for someone outside the tour', async () => {
      const claim = { ...call(ALICE, BOB), memberEmails: { [ALICE.uid]: ALICE.email, [BOB.uid]: CAROL.email } };
      await assertFails(setDoc(doc(as(ALICE), 'calls', 'c3'), claim));
    });
  });

  describe('chat notices', () => {
    const notice = (sender, chatId, extra = {}) => ({
      title: `New message from ${sender.uid}`,
      body: 'hi',
      action: 'chat',
      uid: sender.uid,
      itemId: chatId,
      timestamp: serverTimestamp(),
      ...extra,
    });

    beforeEach(async () => {
      await setDoc(doc(as(ALICE), 'chats', CHAT), sharedChat(ALICE, BOB));
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'chats', `${ALICE.uid}_${CAROL.uid}`), { participants: [ALICE.uid, CAROL.uid] });
      });
    });

    test('a chat notice reaches the other person of an open chat', async () => {
      await assertSucceeds(addDoc(collection(as(ALICE), 'users', BOB.uid, 'notifications'), notice(ALICE, CHAT)));
    });

    test('nobody sends a notice into the inbox of someone outside the tour', async () => {
      await assertFails(addDoc(collection(as(ALICE), 'users', CAROL.uid, 'notifications'), notice(ALICE, `${ALICE.uid}_${CAROL.uid}`)));
    });

    test('only chat notices reach another person', async () => {
      await assertFails(addDoc(collection(as(ALICE), 'users', BOB.uid, 'notifications'), notice(ALICE, CHAT, { action: 'follow' })));
    });
  });

  describe('membership rows', () => {
    test('a person joins a tour under their own uid only', async () => {
      await assertFails(setDoc(doc(as(EVE), 'memberships', `${TOUR}__${EVE.email}`), {
        tourId: TOUR, email: EVE.email, uid: ALICE.uid, role: 'member', status: 'active', joinCode: CODE,
      }));
      await assertSucceeds(setDoc(doc(as(EVE), 'memberships', `${TOUR}__${EVE.email}`), {
        tourId: TOUR, email: EVE.email, uid: EVE.uid, role: 'member', status: 'active', joinCode: CODE,
      }));
    });

    test('nobody writes a uid onto someone else\'s row', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'memberships', `${TOUR}__${CAROL.email}`), {
          tourId: TOUR, email: CAROL.email, role: 'member', status: 'active',
        });
      });
      // The owner may add Carol, but cannot name her uid.
      await assertFails(updateDoc(doc(as(OWNER), 'memberships', `${TOUR}__${CAROL.email}`), { uid: CAROL.uid }));
      // Carol names her own uid on her own row.
      await assertSucceeds(updateDoc(doc(as(CAROL), 'memberships', `${TOUR}__${CAROL.email}`), { uid: CAROL.uid }));
    });

    test('a member cannot change their uid to someone else\'s', async () => {
      await assertFails(updateDoc(doc(as(BOB), 'memberships', `${TOUR}__${BOB.email}`), { uid: ALICE.uid }));
    });
  });

  describe('directory', () => {
    test('a person reads their own account record, not someone else\'s', async () => {
      await assertSucceeds(getDoc(doc(as(BOB), 'users', BOB.uid)));
      await assertFails(getDoc(doc(as(ALICE), 'users', BOB.uid)));
    });

    test('a profile opens by its user ID, but profiles are never listed', async () => {
      await assertSucceeds(getDoc(doc(as(ALICE), 'explorer_profiles', BOB.uid)));
      await assertFails(getDocs(collection(as(ALICE), 'explorer_profiles')));
      await assertFails(getDocs(query(collection(as(ALICE), 'explorer_profiles'), where('displayName', '==', 'Bob'))));
    });

    test('no explorer scores are listed', async () => {
      await assertFails(getDocs(collection(as(ALICE), 'explorer_scores')));
    });

    test('a diary belongs to its author', async () => {
      await assertFails(getDoc(doc(as(ALICE), 'trip_logs', 'carol-diary')));
      await assertFails(getDocs(collection(as(ALICE), 'trip_logs')));
      await assertSucceeds(getDocs(query(collection(as(CAROL), 'trip_logs'), where('authorId', '==', CAROL.uid))));
    });

    test('location pins are listed by admins only', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'location_pins', 'pin1'), { name: 'Pin', createdByUid: ALICE.uid, hidden: false });
      });
      await assertFails(getDocs(collection(as(BOB), 'location_pins')));
      await assertSucceeds(getDoc(doc(as(BOB), 'location_pins', 'pin1')));
    });

    test('signed-out visitors read none of it', async () => {
      await assertFails(getDoc(doc(anon(), 'explorer_profiles', BOB.uid)));
      await assertFails(getDocs(collection(anon(), 'trip_logs')));
    });
  });
});
