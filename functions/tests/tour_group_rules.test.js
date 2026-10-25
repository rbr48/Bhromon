// Tour Group security rules. Runs against the Firestore emulator on port 8080:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "npx jest tests/tour_group_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, addDoc, serverTimestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 't1';
const CODE = 'ABCDEFGH';
const people = {
  owner: { uid: 'own', email: 'own@x.com' },
  admin: { uid: 'adm', email: 'adm@x.com' },
  member: { uid: 'mem', email: 'mem@x.com' },
  other: { uid: 'oth', email: 'oth@x.com' },
  outsider: { uid: 'eve', email: 'eve@x.com' },
  banned: { uid: 'ban', email: 'ban@x.com' },
};

describe('Tour Group Firestore rules', () => {
  let env;
  const db = (who) => env.authenticatedContext(people[who].uid, { email: people[who].email }).firestore();
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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Trip', ownerEmail: people.owner.email, ownerUid: people.owner.uid, inviteCode: CODE, destination: 'Sajek' });
      await setDoc(doc(f, 'invites', CODE), { tourId: TOUR, code: CODE });
      const membership = (id, email, role) =>
        setDoc(doc(f, 'memberships', `${TOUR}__${email}`), { tourId: TOUR, email, role, status: 'active', displayName: id });
      await membership('owner', people.owner.email, 'owner');
      await membership('admin', people.admin.email, 'admin');
      await membership('member', people.member.email, 'member');
      await membership('other', people.other.email, 'member');
      await setDoc(doc(f, 'tours', TOUR, 'bans', people.banned.email), { email: people.banned.email });
    });
  });

  const membershipFor = (email) => ({ tourId: TOUR, email, role: 'member', status: 'active', joinCode: CODE, displayName: 'x' });

  describe('tours', () => {
    test('outsider cannot read the tour or its invite code', async () => {
      await assertFails(getDoc(doc(db('outsider'), 'tours', TOUR)));
      await assertFails(getDoc(doc(anon(), 'tours', TOUR)));
    });

    test('members read the tour', async () => {
      await assertSucceeds(getDoc(doc(db('member'), 'tours', TOUR)));
    });

    test('tours cannot be listed', async () => {
      await assertFails(getDocs(collection(db('owner'), 'tours')));
    });

    test('admin edits trip details but not ownership or invite code', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR), { name: 'Renamed' }));
      await assertFails(updateDoc(doc(db('admin'), 'tours', TOUR), { inviteCode: 'ZZZZZZZZ' }));
      await assertFails(updateDoc(doc(db('admin'), 'tours', TOUR), { ownerEmail: people.admin.email }));
    });

    test('plain member cannot edit the tour', async () => {
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR), { name: 'Hijack' }));
    });

    test('owner rotates the invite code', async () => {
      await assertSucceeds(updateDoc(doc(db('owner'), 'tours', TOUR), { inviteCode: 'NEWCODE1' }));
    });

    test('a removed tour leaves only its owner row, which the owner may clear', async () => {
      await assertFails(deleteDoc(doc(db('member'), 'memberships', `${TOUR}__${people.owner.email}`)));
      await assertSucceeds(deleteDoc(doc(db('owner'), 'tours', TOUR)));
      await assertSucceeds(deleteDoc(doc(db('owner'), 'memberships', `${TOUR}__${people.owner.email}`)));
    });

    test('admin cannot delete the tour, owner can', async () => {
      await assertFails(deleteDoc(doc(db('admin'), 'tours', TOUR)));
      await assertSucceeds(deleteDoc(doc(db('owner'), 'tours', TOUR)));
    });

    test('creating a tour requires you to be its owner', async () => {
      await assertSucceeds(setDoc(doc(db('outsider'), 'tours', 'new1'), { ownerEmail: people.outsider.email, ownerUid: people.outsider.uid, inviteCode: 'XXXXXXXX' }));
      await assertFails(setDoc(doc(db('outsider'), 'tours', 'new2'), { ownerEmail: people.owner.email, ownerUid: people.outsider.uid, inviteCode: 'XXXXXXXX' }));
    });
  });

  describe('joining and memberships', () => {
    test('valid invite code lets an outsider join as a member', async () => {
      await assertSucceeds(setDoc(doc(db('outsider'), 'memberships', `${TOUR}__${people.outsider.email}`), membershipFor(people.outsider.email)));
    });

    test('wrong invite code is refused', async () => {
      await assertFails(setDoc(doc(db('outsider'), 'memberships', `${TOUR}__${people.outsider.email}`), { ...membershipFor(people.outsider.email), joinCode: 'WRONGCOD' }));
    });

    test('banned person cannot rejoin with the correct code', async () => {
      await assertFails(setDoc(doc(db('banned'), 'memberships', `${TOUR}__${people.banned.email}`), membershipFor(people.banned.email)));
    });

    test('nobody can join as admin or owner through the join path', async () => {
      await assertFails(setDoc(doc(db('outsider'), 'memberships', `${TOUR}__${people.outsider.email}`), { ...membershipFor(people.outsider.email), role: 'admin' }));
      await assertFails(setDoc(doc(db('outsider'), 'memberships', `${TOUR}__${people.outsider.email}`), { ...membershipFor(people.outsider.email), role: 'owner' }));
    });

    test('cannot create a membership for someone else', async () => {
      await assertFails(setDoc(doc(db('outsider'), 'memberships', `${TOUR}__${people.member.email}`), membershipFor(people.outsider.email)));
    });

    test('outsider cannot read the roster; members can', async () => {
      const rosterQuery = query(collection(db('outsider'), 'memberships'), where('tourId', '==', TOUR));
      await assertFails(getDocs(rosterQuery));
      const memberQuery = query(collection(db('member'), 'memberships'), where('tourId', '==', TOUR));
      await assertSucceeds(getDocs(memberQuery));
    });

    test('everyone can list only their own memberships', async () => {
      await assertSucceeds(getDocs(query(collection(db('member'), 'memberships'), where('email', '==', people.member.email))));
      await assertFails(getDocs(collection(db('member'), 'memberships')));
    });

    test('admin cannot promote a member; owner can', async () => {
      await assertFails(updateDoc(doc(db('admin'), 'memberships', `${TOUR}__${people.member.email}`), { role: 'admin' }));
      await assertSucceeds(updateDoc(doc(db('owner'), 'memberships', `${TOUR}__${people.member.email}`), { role: 'admin' }));
    });

    test('member may edit only their own display name, not their role', async () => {
      await assertSucceeds(updateDoc(doc(db('member'), 'memberships', `${TOUR}__${people.member.email}`), { displayName: 'New name' }));
      await assertFails(updateDoc(doc(db('member'), 'memberships', `${TOUR}__${people.member.email}`), { role: 'owner' }));
    });

    test('admin removes a member; the owner row is protected', async () => {
      await assertSucceeds(deleteDoc(doc(db('admin'), 'memberships', `${TOUR}__${people.member.email}`)));
      await assertFails(deleteDoc(doc(db('admin'), 'memberships', `${TOUR}__${people.owner.email}`)));
      await assertFails(deleteDoc(doc(db('owner'), 'memberships', `${TOUR}__${people.owner.email}`)));
    });

    test('member can leave on their own', async () => {
      await assertSucceeds(deleteDoc(doc(db('member'), 'memberships', `${TOUR}__${people.member.email}`)));
    });

    test('admin can record a ban; member cannot', async () => {
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'bans', people.outsider.email), { email: people.outsider.email }));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'bans', people.outsider.email), { email: people.outsider.email }));
    });
  });

  describe('invites', () => {
    test('anyone signed in can fetch an invite by exact code, but not list them', async () => {
      await assertSucceeds(getDoc(doc(db('outsider'), 'invites', CODE)));
      await assertFails(getDocs(collection(db('outsider'), 'invites')));
    });

    test('only the tour owner can create or delete invites', async () => {
      await assertSucceeds(setDoc(doc(db('owner'), 'invites', 'NEWCODE1'), { tourId: TOUR, code: 'NEWCODE1' }));
      await assertFails(setDoc(doc(db('admin'), 'invites', 'NEWCODE2'), { tourId: TOUR, code: 'NEWCODE2' }));
      await assertFails(deleteDoc(doc(db('member'), 'invites', CODE)));
    });
  });

  describe('money', () => {
    const expense = (by) => ({ tourId: TOUR, title: 'Hotel', amountPaisa: 100000, category: 'Hotel', addedByEmail: by, date: '2026-10-25T10:00:00.000' });

    test('member adds an expense under their own email only', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e1'), expense(people.member.email)));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e2'), expense(people.admin.email)));
    });

    test('outsider cannot read or add expenses', async () => {
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'expenses')));
      await assertFails(setDoc(doc(db('outsider'), 'tours', TOUR, 'expenses', 'e3'), expense(people.outsider.email)));
    });

    test('only the author or an admin edits or deletes an expense', async () => {
      await setDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e1'), expense(people.member.email));
      await assertFails(updateDoc(doc(db('other'), 'tours', TOUR, 'expenses', 'e1'), { title: 'Hijack' }));
      await assertFails(deleteDoc(doc(db('other'), 'tours', TOUR, 'expenses', 'e1')));
      await assertSucceeds(updateDoc(doc(db('member'), 'tours', TOUR, 'expenses', 'e1'), { title: 'Hotel 2' }));
      await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', TOUR, 'expenses', 'e1')));
    });

    test('only admins post official notices', async () => {
      await assertFails(addDoc(collection(db('member'), 'tours', TOUR, 'notices'), { title: 'x', createdAt: serverTimestamp() }));
      await assertSucceeds(addDoc(collection(db('admin'), 'tours', TOUR, 'notices'), { title: 'x', createdAt: serverTimestamp() }));
    });
  });

  describe('feed', () => {
    const postPath = ['tours', TOUR, 'posts', 'p1'];
    const post = (author) => ({ tourId: TOUR, authorEmail: author, caption: 'hi', images: [], likes: [], commentCount: 0 });

    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...postPath), post(people.member.email));
      });
    });

    test('members like and comment; outsiders cannot', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), ...postPath), { likes: ['adm@x.com'] }));
      await assertFails(updateDoc(doc(db('outsider'), ...postPath), { likes: ['eve@x.com'] }));
    });

    test('only the author edits the caption', async () => {
      await assertFails(updateDoc(doc(db('admin'), ...postPath), { caption: 'changed' }));
      await assertSucceeds(updateDoc(doc(db('member'), ...postPath), { caption: 'changed' }));
    });

    test('post author can delete comments on their post; other members cannot', async () => {
      await setDoc(doc(db('admin'), ...postPath, 'comments', 'c1'), { authorEmail: 'adm@x.com', text: 'nice' });
      await assertFails(deleteDoc(doc(db('other'), ...postPath, 'comments', 'c1')));
      await assertSucceeds(deleteDoc(doc(db('member'), ...postPath, 'comments', 'c1')));
    });

    test('comments are tied to the commenter and deleted by author or admin', async () => {
      const comments = collection(db('admin'), ...postPath, 'comments');
      await assertSucceeds(addDoc(comments, { authorEmail: 'adm@x.com', text: 'nice' }));
      await assertFails(addDoc(collection(db('admin'), ...postPath, 'comments'), { authorEmail: 'mem@x.com', text: 'spoof' }));
    });

    test('cannot post as someone else', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'posts', 'p2'), post(people.owner.email)));
    });
  });

  describe('live location and logistics', () => {
    test('each person writes only their own location; members read all', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'locations', 'l1'), { email: people.member.email, lat: 1, lng: 2 }));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'locations', 'l2'), { email: people.admin.email, lat: 1, lng: 2 }));
      await assertSucceeds(getDoc(doc(db('admin'), 'tours', TOUR, 'locations', 'l1')));
      await assertFails(getDoc(doc(db('outsider'), 'tours', TOUR, 'locations', 'l1')));
    });

    test('bus seats are readable and writable by members, not outsiders', async () => {
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'bus_seats', 'A1'), { seatNumber: 'A1', assignedMemberEmail: people.member.email }));
      await assertSucceeds(getDocs(collection(db('member'), 'tours', TOUR, 'bus_seats')));
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'bus_seats')));
    });

    test('hotel rooms: admins create and delete, members update guests', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'hotel_rooms', 'r1'), { roomNumber: '301' }));
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'hotel_rooms', 'r1'), { roomNumber: '301' }));
      await assertSucceeds(updateDoc(doc(db('member'), 'tours', TOUR, 'hotel_rooms', 'r1'), { assignedMemberEmails: [people.member.email] }));
      await assertFails(deleteDoc(doc(db('member'), 'tours', TOUR, 'hotel_rooms', 'r1')));
    });
  });

  test('unauthenticated users can read nothing in the tour group', async () => {
    await assertFails(getDoc(doc(anon(), 'memberships', `${TOUR}__${people.member.email}`)));
    await assertFails(getDoc(doc(anon(), 'invites', CODE)));
  });
});
