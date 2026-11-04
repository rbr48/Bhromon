// Journey events security rules (roadmap LJ-4.1). Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/journey_events_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tj1';
const people = {
  owner: { uid: 'own', email: 'own@x.com' },
  admin: { uid: 'adm', email: 'adm@x.com' },
  member: { uid: 'mem', email: 'mem@x.com' },
  other: { uid: 'oth', email: 'oth@x.com' },
  outsider: { uid: 'eve', email: 'eve@x.com' },
};

const eventId = (stopId, email, type) => `${stopId}__${email}__${type}`;

describe('Journey events Firestore rules', () => {
  let env;
  const db = (who) => env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();
  const anon = () => env.unauthenticatedContext().firestore();
  const eventsRef = (f, id) => doc(f, 'tours', TOUR, 'journey_events', id);
  const payload = (who, stopId, type, extra = {}) => ({
    type,
    stopId,
    email: people[who].email,
    uid: people[who].uid,
    createdAt: serverTimestamp(),
    ...extra,
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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Trip', ownerEmail: people.owner.email, ownerUid: people.owner.uid, destination: 'Sajek' });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${TOUR}__${email}`), { tourId: TOUR, email, role, status: 'active', uid: null });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
    });
  });

  describe('creating an event', () => {
    test('a member records their own arrival', async () => {
      await assertSucceeds(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'arrive')),
        payload('member', 'hub', 'arrive')));
    });

    test('a member records their own departure', async () => {
      await assertSucceeds(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'depart')),
        payload('member', 'hub', 'depart')));
    });

    test('a member cannot record another member\'s arrival', async () => {
      await assertFails(setDoc(eventsRef(db('member'), eventId('hub', people.other.email, 'arrive')),
        payload('other', 'hub', 'arrive')));
    });

    test('the document id must name the stop, the member and the type', async () => {
      await assertFails(setDoc(eventsRef(db('member'), 'hub__someone@x.com__arrive'),
        payload('member', 'hub', 'arrive')));
      await assertFails(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'depart')),
        payload('member', 'hub', 'arrive')));
    });

    test('only arrive and depart are accepted', async () => {
      await assertFails(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'wave')),
        payload('member', 'hub', 'wave')));
    });

    test('no coordinates or other fields are stored', async () => {
      await assertFails(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'arrive')),
        payload('member', 'hub', 'arrive', { lat: 23.7, lng: 90.4 })));
    });

    test('the time is the server time, not a client clock', async () => {
      await assertFails(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'arrive')),
        payload('member', 'hub', 'arrive', { createdAt: new Date() })));
    });

    test('the uid must be the caller\'s own', async () => {
      await assertFails(setDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'arrive')),
        payload('member', 'hub', 'arrive', { uid: people.other.uid })));
    });

    test('an outsider cannot record an event', async () => {
      await assertFails(setDoc(eventsRef(db('outsider'), eventId('hub', people.outsider.email, 'arrive')),
        payload('outsider', 'hub', 'arrive')));
      await assertFails(setDoc(eventsRef(anon(), eventId('hub', people.outsider.email, 'arrive')),
        payload('outsider', 'hub', 'arrive')));
    });

    test('a stop id that is empty or too long is refused', async () => {
      await assertFails(setDoc(eventsRef(db('member'), `__${people.member.email}__arrive`),
        payload('member', '', 'arrive')));
      const long = 'x'.repeat(81);
      await assertFails(setDoc(eventsRef(db('member'), eventId(long, people.member.email, 'arrive')),
        payload('member', long, 'arrive')));
    });
  });

  describe('reading and changing events', () => {
    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        const f = ctx.firestore();
        await setDoc(eventsRef(f, eventId('hub', people.member.email, 'arrive')), {
          type: 'arrive', stopId: 'hub', email: people.member.email, uid: people.member.uid, createdAt: new Date(),
        });
        await setDoc(eventsRef(f, eventId('hub', people.other.email, 'arrive')), {
          type: 'arrive', stopId: 'hub', email: people.other.email, uid: people.other.uid, createdAt: new Date(),
        });
      });
    });

    test('members read the events of their tour', async () => {
      await assertSucceeds(getDoc(eventsRef(db('admin'), eventId('hub', people.member.email, 'arrive'))));
      await assertSucceeds(getDoc(eventsRef(db('other'), eventId('hub', people.member.email, 'arrive'))));
    });

    test('an outsider cannot read the events', async () => {
      await assertFails(getDoc(eventsRef(db('outsider'), eventId('hub', people.member.email, 'arrive'))));
      await assertFails(getDoc(eventsRef(anon(), eventId('hub', people.member.email, 'arrive'))));
    });

    test('an event cannot be edited, even by its author', async () => {
      await assertFails(updateDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'arrive')),
        { type: 'depart' }));
    });

    test('the author deletes their event', async () => {
      await assertSucceeds(deleteDoc(eventsRef(db('member'), eventId('hub', people.member.email, 'arrive'))));
    });

    test('an admin deletes any event', async () => {
      await assertSucceeds(deleteDoc(eventsRef(db('admin'), eventId('hub', people.member.email, 'arrive'))));
    });

    test('another member cannot delete someone else\'s event', async () => {
      await assertFails(deleteDoc(eventsRef(db('other'), eventId('hub', people.member.email, 'arrive'))));
    });
  });
});
