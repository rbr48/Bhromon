// Tour Group security rules. Runs against the Firestore emulator on port 8080:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "npx jest --runInBand tests/tour_group_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, addDoc, serverTimestamp, FieldPath } = require('firebase/firestore');

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

    test('a member sets their own family size, but not their role', async () => {
      await assertSucceeds(updateDoc(doc(db('member'), 'memberships', `${TOUR}__${people.member.email}`), { familyCount: 3 }));
      await assertFails(updateDoc(doc(db('member'), 'memberships', `${TOUR}__${people.member.email}`), { familyCount: 3, role: 'admin' }));
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

    const transfer = (by, from, to, amountPaisa = 50000) => ({ tourId: TOUR, fromId: from, fromName: 'x', toId: to, toName: 'y', amountPaisa, addedByEmail: by });

    test('settle-up payments: members record ones they took part in; admins any', async () => {
      const t = (id) => doc(db('member'), 'tours', TOUR, 'transfers', id);
      await assertSucceeds(setDoc(t('t1'), transfer(people.member.email, people.member.email, people.other.email)));
      await assertSucceeds(setDoc(t('t2'), transfer(people.member.email, people.other.email, people.member.email)));
      await assertSucceeds(setDoc(t('t3'), transfer(people.member.email, people.member.email, null)));
      // Not between two other people, not under someone else's name, not zero.
      await assertFails(setDoc(t('t4'), transfer(people.member.email, people.other.email, people.admin.email)));
      await assertFails(setDoc(t('t5'), transfer(people.admin.email, people.member.email, null)));
      await assertFails(setDoc(t('t6'), transfer(people.member.email, people.member.email, null, 0)));
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'transfers', 't7'), transfer(people.admin.email, null, people.other.email)));
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'transfers')));
    });

    test('settle-up payments are never edited; the author or an admin deletes', async () => {
      await setDoc(doc(db('member'), 'tours', TOUR, 'transfers', 't1'), transfer(people.member.email, people.member.email, people.other.email));
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'transfers', 't1'), { amountPaisa: 1 }));
      await assertFails(deleteDoc(doc(db('other'), 'tours', TOUR, 'transfers', 't1')));
      await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', TOUR, 'transfers', 't1')));
    });

    test('only admins set the fund budget', async () => {
      const budget = { fundBudget: { categoryPaisa: { Food: 100000 }, perHeadTargetPaisa: 500000 } };
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR), budget));
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR), budget));
    });

    test('only admins post official notices', async () => {
      await assertFails(addDoc(collection(db('member'), 'tours', TOUR, 'notices'), { title: 'x', createdAt: serverTimestamp() }));
      await assertSucceeds(addDoc(collection(db('admin'), 'tours', TOUR, 'notices'), { title: 'x', createdAt: serverTimestamp() }));
    });
  });

  describe('feed', () => {
    const postPath = ['tours', TOUR, 'posts', 'p1'];
    const post = (author) => ({
      tourId: TOUR,
      authorEmail: author,
      caption: 'hi',
      images: [],
      likes: [],
      commentCount: 0,
      createdAt: serverTimestamp(),
    });
    const comment = (author, text = 'nice') => ({ authorEmail: author, text, createdAt: serverTimestamp() });

    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...postPath), post(people.member.email));
      });
    });

    test('members like and comment; outsiders cannot', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), ...postPath), { likes: ['adm@x.com'] }));
      await assertFails(updateDoc(doc(db('outsider'), ...postPath), { likes: ['eve@x.com'] }));
    });

    test('a member adds or removes only their own like', async () => {
      await assertFails(updateDoc(doc(db('admin'), ...postPath), { likes: ['oth@x.com'] }));
      await assertSucceeds(updateDoc(doc(db('admin'), ...postPath), { likes: ['adm@x.com'] }));
      await assertSucceeds(updateDoc(doc(db('other'), ...postPath), { likes: ['adm@x.com', 'oth@x.com'] }));
      await assertSucceeds(updateDoc(doc(db('other'), ...postPath), { likes: ['adm@x.com'] }));
      await assertFails(updateDoc(doc(db('other'), ...postPath), { likes: [] }));
      await assertSucceeds(updateDoc(doc(db('admin'), ...postPath), { likes: [] }));
    });

    test('a new post is stamped by the server and starts with no likes or comments', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'posts', 'p2'), { ...post(people.member.email), createdAt: new Date() }));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'posts', 'p2'), { ...post(people.member.email), likes: ['adm@x.com'] }));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'posts', 'p2'), { ...post(people.member.email), commentCount: 5 }));
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'posts', 'p2'), post(people.member.email)));
    });

    test('the comment count moves by one at a time', async () => {
      await assertSucceeds(updateDoc(doc(db('admin'), ...postPath), { commentCount: 1 }));
      await assertFails(updateDoc(doc(db('admin'), ...postPath), { commentCount: 9 }));
      await assertSucceeds(updateDoc(doc(db('other'), ...postPath), { commentCount: 0 }));
    });

    test('only the author or an admin edits the caption; other members cannot', async () => {
      await assertFails(updateDoc(doc(db('other'), ...postPath), { caption: 'changed' }));
      await assertSucceeds(updateDoc(doc(db('admin'), ...postPath), { caption: 'changed' }));
      await assertSucceeds(updateDoc(doc(db('member'), ...postPath), { caption: 'changed' }));
    });

    test('the author may archive and edit the listed post fields, but not the author or media', async () => {
      await assertSucceeds(updateDoc(doc(db('member'), ...postPath), { isArchived: true, isEdited: true, editedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(doc(db('member'), ...postPath), { tags: ['beach'], location: 'Kuakata' }));
      await assertFails(updateDoc(doc(db('member'), ...postPath), { authorEmail: 'adm@x.com' }));
      await assertFails(updateDoc(doc(db('member'), ...postPath), { images: ['https://evil.example/x.jpg'] }));
      await assertFails(updateDoc(doc(db('other'), ...postPath), { caption: 'hijack' }));
    });

    test('post author can delete comments on their post; other members cannot', async () => {
      await setDoc(doc(db('admin'), ...postPath, 'comments', 'c1'), comment('adm@x.com'));
      await assertFails(deleteDoc(doc(db('other'), ...postPath, 'comments', 'c1')));
      await assertSucceeds(deleteDoc(doc(db('member'), ...postPath, 'comments', 'c1')));
    });

    test('comments are tied to the commenter, stamped by the server, and deleted by author or admin', async () => {
      const comments = collection(db('admin'), ...postPath, 'comments');
      await assertSucceeds(addDoc(comments, comment('adm@x.com')));
      await assertFails(addDoc(collection(db('admin'), ...postPath, 'comments'), comment('mem@x.com', 'spoof')));
      await assertFails(addDoc(collection(db('admin'), ...postPath, 'comments'), { authorEmail: 'adm@x.com', text: 'no time' }));
      await assertFails(addDoc(collection(db('admin'), ...postPath, 'comments'), comment('adm@x.com', 'x'.repeat(501))));
    });

    test('comment likes change only the liker\'s own entry', async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...postPath, 'comments', 'c2'), comment('mem@x.com', 'hello'));
      });
      const ref = doc(db('other'), ...postPath, 'comments', 'c2');
      await assertSucceeds(updateDoc(ref, { likes: ['oth@x.com'] }));
      await assertFails(updateDoc(ref, { likes: ['oth@x.com', 'adm@x.com'] }));
      await assertFails(updateDoc(ref, { text: 'edited' }));
      await assertSucceeds(updateDoc(ref, { likes: [] }));
    });
  });

  describe('stories and highlights', () => {
    const storyPath = ['tours', TOUR, 'stories', 's1'];
    const story = (author) => ({
      authorEmail: author,
      authorName: 'x',
      mediaUrl: 'https://bhromon.fun/media/t1/stories/a.jpg',
      createdAt: serverTimestamp(),
      viewers: [],
      poll: { question: 'Beach?', options: ['Yes', 'No'], votes: {} },
      reactions: {},
    });

    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), ...storyPath), story(people.member.email));
      });
    });

    test('a story is stamped by the server and made under your own email', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'stories', 's2'), { ...story(people.member.email), createdAt: new Date() }));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'stories', 's2'), story(people.owner.email)));
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'stories', 's2'), story(people.member.email)));
    });

    test('members record only their own view', async () => {
      const ref = doc(db('other'), ...storyPath);
      await assertSucceeds(updateDoc(ref, { viewers: ['oth@x.com'] }));
      await assertFails(updateDoc(ref, { viewers: ['oth@x.com', 'adm@x.com'] }));
      await assertFails(updateDoc(ref, { viewers: ['adm@x.com'] }));
    });

    test('each member votes once in a poll, for an option that exists', async () => {
      const ref = doc(db('other'), ...storyPath);
      await assertSucceeds(updateDoc(ref, new FieldPath('poll', 'votes', 'oth@x.com'), 1));
      await assertFails(updateDoc(ref, new FieldPath('poll', 'votes', 'oth@x.com'), 0));
      await assertFails(updateDoc(doc(db('admin'), ...storyPath), new FieldPath('poll', 'votes', 'oth@x.com'), 0));
      await assertFails(updateDoc(doc(db('admin'), ...storyPath), new FieldPath('poll', 'votes', 'adm@x.com'), 5));
      await assertSucceeds(updateDoc(doc(db('admin'), ...storyPath), new FieldPath('poll', 'votes', 'adm@x.com'), 1));
    });

    test('a reaction is keyed by the reacting email as one field, and is their own', async () => {
      const ref = doc(db('other'), ...storyPath);
      await assertSucceeds(updateDoc(ref, new FieldPath('reactions', 'oth@x.com'), '❤️'));
      await assertFails(updateDoc(ref, new FieldPath('reactions', 'adm@x.com'), '❤️'));
      await assertFails(updateDoc(ref, new FieldPath('reactions', 'oth@x.com'), 'x'.repeat(17)));
    });

    test('the author or an admin deletes a story; other members cannot', async () => {
      await assertFails(deleteDoc(doc(db('other'), ...storyPath)));
      await assertSucceeds(deleteDoc(doc(db('admin'), ...storyPath)));
    });

    test('highlights are kept by the member who made them, and by admins', async () => {
      const path = ['tours', TOUR, 'highlights', 'h1'];
      await assertFails(setDoc(doc(db('member'), ...path), { title: 'x', coverUrl: 'u', createdByEmail: 'oth@x.com' }));
      await assertSucceeds(setDoc(doc(db('member'), ...path), { title: 'x', coverUrl: 'u', createdByEmail: 'mem@x.com' }));
      await assertFails(deleteDoc(doc(db('other'), ...path)));
      await assertSucceeds(deleteDoc(doc(db('admin'), ...path)));
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

    test('route stops: anyone adds their own; the author or an admin edits; the author stays', async () => {
      const path = ['tours', TOUR, 'checkpoints', 'c1'];
      const cp = { id: 'c1', name: 'Paduar Bazar', kmFromStart: 100, kind: 'food', legKey: 'origin>a', addedByEmail: people.member.email };
      await assertFails(setDoc(doc(db('member'), ...path), { ...cp, addedByEmail: people.admin.email }));
      await assertSucceeds(setDoc(doc(db('member'), ...path), cp));
      await assertSucceeds(updateDoc(doc(db('member'), ...path), { name: 'Paduar Bazar Bishwaroad' }));
      await assertSucceeds(updateDoc(doc(db('admin'), ...path), { visitedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db('other'), ...path), { name: 'x' }));
      await assertFails(updateDoc(doc(db('member'), ...path), { addedByEmail: people.other.email }));
      await assertFails(deleteDoc(doc(db('other'), ...path)));
      await assertSucceeds(deleteDoc(doc(db('member'), ...path)));
    });

    test('admins save the itinerary and leg plans on the tour; members cannot', async () => {
      const stops = [{ id: 'a', name: "Cox's Bazar", kind: 'beach' }];
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR), { stops }));
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR), { stops, returnHome: true }));
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR), new FieldPath('legPlans', 'origin>a'), { mode: 'road' }));
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR), new FieldPath('legPlans', 'origin>a'), { mode: 'air' }));
    });

    const vehicle = (extra = {}) => ({ id: 'v1', kind: 'trainChair', name: 'Sonar Bangla', rows: 15, pattern: '2-2', locked: false, ...extra });
    const seat = (extra = {}) => ({ vehicleId: 'v1', seatNumber: '12', assignedMemberEmail: people.member.email, assignedMemberName: 'M', isWindow: false, familySlot: 0, ...extra });

    test('vehicles: admins add, edit and delete them; members only read', async () => {
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'vehicles', 'v1'), vehicle()));
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1'), vehicle()));
      await assertSucceeds(getDocs(collection(db('member'), 'tours', TOUR, 'vehicles')));
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'vehicles')));
      await assertFails(updateDoc(doc(db('member'), 'tours', TOUR, 'vehicles', 'v1'), { locked: true }));
      await assertFails(deleteDoc(doc(db('member'), 'tours', TOUR, 'vehicles', 'v1')));
      await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1')));
    });

    test('vehicles: the id must match and the seat map stays a sensible size', async () => {
      await assertFails(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1'), vehicle({ id: 'other' })));
      await assertFails(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1'), vehicle({ rows: 500 })));
      await assertFails(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1'), vehicle({ rows: 0 })));
    });

    test('vehicle seats: members take seats on an existing vehicle under the right id', async () => {
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1'), vehicle()));
      await assertSucceeds(setDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v1__12'), seat()));
      await assertSucceeds(getDocs(collection(db('member'), 'tours', TOUR, 'vehicle_seats')));
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'vehicle_seats')));
      // The document id must be "<vehicleId>__<seatNumber>".
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v1__13'), seat()));
      // No seats on a vehicle that does not exist.
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v9__12'), seat({ vehicleId: 'v9' })));
      // Only the seat fields.
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v1__12'), seat({ price: 5 })));
      await assertSucceeds(deleteDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v1__12')));
    });

    test('vehicle seats: a locked vehicle is changed by admins only', async () => {
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicles', 'v1'), vehicle({ locked: true })));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v1__12'), seat()));
      await assertSucceeds(setDoc(doc(db('admin'), 'tours', TOUR, 'vehicle_seats', 'v1__12'), seat()));
      await assertFails(deleteDoc(doc(db('member'), 'tours', TOUR, 'vehicle_seats', 'v1__12')));
      await assertSucceeds(deleteDoc(doc(db('admin'), 'tours', TOUR, 'vehicle_seats', 'v1__12')));
    });
  });

  describe('safety alerts', () => {
    const alertPath = ['tours', TOUR, 'sos', 'a1'];
    const alert = (sender) => ({ senderEmail: sender, senderName: 'x', resolved: false, createdAt: serverTimestamp() });

    test('members raise an alert under their own email only', async () => {
      await assertSucceeds(setDoc(doc(db('member'), ...alertPath), alert(people.member.email)));
      await assertFails(setDoc(doc(db('member'), 'tours', TOUR, 'sos', 'a2'), alert(people.admin.email)));
    });

    test('an alert starts unresolved and carries the server time', async () => {
      await assertFails(setDoc(doc(db('member'), ...alertPath), { ...alert(people.member.email), resolved: true }));
      await assertFails(setDoc(doc(db('member'), ...alertPath), { ...alert(people.member.email), createdAt: new Date('2020-01-01') }));
    });

    test('outsiders and banned accounts can neither raise nor read alerts', async () => {
      await assertFails(setDoc(doc(db('outsider'), ...alertPath), alert(people.outsider.email)));
      await assertFails(setDoc(doc(db('banned'), ...alertPath), alert(people.banned.email)));
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'sos')));
    });

    test('active members read every alert in the tour', async () => {
      await setDoc(doc(db('member'), ...alertPath), alert(people.member.email));
      await assertSucceeds(getDocs(collection(db('other'), 'tours', TOUR, 'sos')));
    });

    test('the sender or an admin resolves; other members cannot', async () => {
      await setDoc(doc(db('member'), ...alertPath), alert(people.member.email));
      await assertFails(updateDoc(doc(db('other'), ...alertPath), { resolved: true }));
      await assertSucceeds(updateDoc(doc(db('member'), ...alertPath), { resolved: true, resolvedByEmail: people.member.email }));

      await setDoc(doc(db('member'), 'tours', TOUR, 'sos', 'a3'), alert(people.member.email));
      await assertSucceeds(updateDoc(doc(db('admin'), 'tours', TOUR, 'sos', 'a3'), { resolved: true, resolvedByEmail: people.admin.email }));
    });

    test('resolving changes only the resolution fields and cannot reopen', async () => {
      await setDoc(doc(db('member'), ...alertPath), alert(people.member.email));
      await assertFails(updateDoc(doc(db('member'), ...alertPath), { resolved: true, senderName: 'hijack' }));
      await assertFails(updateDoc(doc(db('member'), ...alertPath), { resolved: false }));
    });
  });

  describe('discussion channels', () => {
    const CH = 'general';
    const msgPath = (id) => ['tours', TOUR, 'channels', CH, 'messages', id];
    const message = (sender, extra = {}) => ({
      id: 'm1',
      kind: 'text',
      text: 'hello',
      senderEmail: sender,
      senderName: 'x',
      timestamp: serverTimestamp(),
      attachments: [],
      mentions: [],
      isPinned: false,
      ...extra,
    });
    const seed = (extra = {}) =>
      env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), ...msgPath('m1')), message(people.member.email, extra)));

    test('members post as themselves, and only as themselves', async () => {
      await assertSucceeds(setDoc(doc(db('member'), ...msgPath('a1')), message(people.member.email)));
      await assertFails(setDoc(doc(db('member'), ...msgPath('a2')), message(people.admin.email)));
      await assertFails(setDoc(doc(anon(), ...msgPath('a3')), message(people.member.email)));
    });

    test('a post has at most 1000 characters and four photos, and a known kind', async () => {
      await assertFails(setDoc(doc(db('member'), ...msgPath('b1')), message(people.member.email, { text: 'x'.repeat(1001) })));
      const photos = Array.from({ length: 5 }, (_, i) => ({ url: `https://m.x/${i}.jpg`, kind: 'image' }));
      await assertFails(setDoc(doc(db('member'), ...msgPath('b2')), message(people.member.email, { attachments: photos })));
      await assertSucceeds(setDoc(doc(db('member'), ...msgPath('b3')), message(people.member.email, { attachments: photos.slice(0, 4) })));
      await assertFails(setDoc(doc(db('member'), ...msgPath('b4')), message(people.member.email, { kind: 'video-call' })));
    });

    test('in an admin-only channel, only admins post', async () => {
      await setDoc(doc(db('admin'), 'tours', TOUR, 'channels', 'announce'), { name: 'Announcements', topic: '', adminOnly: true });
      const path = ['tours', TOUR, 'channels', 'announce', 'messages', 'c1'];
      await assertFails(setDoc(doc(db('member'), ...path), message(people.member.email)));
      await assertSucceeds(setDoc(doc(db('admin'), ...path), message(people.admin.email)));
    });

    test('only admins create, change or delete channels, with bounded names', async () => {
      const chPath = ['tours', TOUR, 'channels', 'trek'];
      await assertFails(setDoc(doc(db('member'), ...chPath), { name: 'Trek', topic: '', adminOnly: false }));
      await assertSucceeds(setDoc(doc(db('admin'), ...chPath), { name: 'Trek', topic: '', adminOnly: false }));
      await assertFails(setDoc(doc(db('admin'), 'tours', TOUR, 'channels', 'long'), { name: 'x'.repeat(41), topic: '', adminOnly: false }));
      await assertFails(updateDoc(doc(db('member'), ...chPath), { topic: 'hijack' }));
      await assertFails(deleteDoc(doc(db('member'), ...chPath)));
      await assertSucceeds(deleteDoc(doc(db('admin'), ...chPath)));
    });

    test('the author edits the text; no one else, and no other field', async () => {
      await seed();
      await assertSucceeds(updateDoc(doc(db('member'), ...msgPath('m1')), { text: 'edited', editedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db('other'), ...msgPath('m1')), { text: 'nope', editedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db('admin'), ...msgPath('m1')), { text: 'nope', editedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db('member'), ...msgPath('m1')), { text: 'edited', senderEmail: people.other.email }));
      await assertFails(updateDoc(doc(db('member'), ...msgPath('m1')), { attachments: [{ url: 'https://evil.x/a.jpg', kind: 'image' }] }));
    });

    test('admins pin and unpin, and change nothing else', async () => {
      await seed();
      await assertFails(updateDoc(doc(db('member'), ...msgPath('m1')), { isPinned: true, pinnedByEmail: people.member.email }));
      await assertSucceeds(updateDoc(doc(db('admin'), ...msgPath('m1')), { isPinned: true, pinnedByEmail: people.admin.email }));
      await assertFails(updateDoc(doc(db('admin'), ...msgPath('m1')), { isPinned: true, text: 'changed' }));
      await assertSucceeds(updateDoc(doc(db('admin'), ...msgPath('m1')), { isPinned: false, pinnedByEmail: '' }));
    });

    test('each member sets or clears only their own reaction', async () => {
      await seed();
      await assertSucceeds(updateDoc(doc(db('other'), ...msgPath('m1')), { reactions: { [people.other.email]: '👍' } }));
      await assertSucceeds(updateDoc(doc(db('other'), ...msgPath('m1')), { reactions: { [people.other.email]: '🔥' } }));
      await assertFails(updateDoc(doc(db('other'), ...msgPath('m1')), { reactions: { [people.other.email]: '👍', [people.member.email]: '🔥' } }));
      await assertFails(updateDoc(doc(db('other'), ...msgPath('m1')), { reactions: { [people.other.email]: '👍' }, text: 'x' }));
      await assertSucceeds(updateDoc(doc(db('other'), ...msgPath('m1')), { reactions: {} }));
    });

    test('members vote once, for an option that exists, and cannot vote for others', async () => {
      await seed({ kind: 'poll', text: 'Dinner?', pollOptions: ['Hilsa', 'Chicken'], votes: {} });
      await assertSucceeds(updateDoc(doc(db('member'), ...msgPath('m1')), { votes: { [people.member.email]: 1 } }));
      await assertFails(updateDoc(doc(db('member'), ...msgPath('m1')), { votes: { [people.member.email]: 5 } }));
      await assertFails(updateDoc(doc(db('member'), ...msgPath('m1')), { votes: { [people.other.email]: 0 } }));
      await assertSucceeds(updateDoc(doc(db('member'), ...msgPath('m1')), { votes: {} }));
    });

    test('a text message takes no votes', async () => {
      await seed();
      await assertFails(updateDoc(doc(db('member'), ...msgPath('m1')), { votes: { [people.member.email]: 0 } }));
    });

    test('the author or an admin deletes a message; other members cannot', async () => {
      await seed();
      await assertFails(deleteDoc(doc(db('other'), ...msgPath('m1'))));
      await assertSucceeds(deleteDoc(doc(db('member'), ...msgPath('m1'))));
      await seed();
      await assertSucceeds(deleteDoc(doc(db('admin'), ...msgPath('m1'))));
    });

    test('typing signals are written by their owner and read by members only', async () => {
      const typing = (who) => ['tours', TOUR, 'channels', CH, 'typing', who.email];
      await assertSucceeds(setDoc(doc(db('member'), ...typing(people.member)), { name: 'x', at: serverTimestamp() }));
      await assertFails(setDoc(doc(db('member'), ...typing(people.other)), { name: 'x', at: serverTimestamp() }));
      await assertSucceeds(getDocs(collection(db('other'), 'tours', TOUR, 'channels', CH, 'typing')));
      await assertFails(getDocs(collection(db('outsider'), 'tours', TOUR, 'channels', CH, 'typing')));
    });

    test('only admins set the live itinerary stop; members read it', async () => {
      const live = ['tours', TOUR, 'meta', 'itinerary'];
      await assertFails(setDoc(doc(db('member'), ...live), { currentStopId: 's1' }));
      await assertSucceeds(setDoc(doc(db('admin'), ...live), { currentStopId: 's1' }));
      await assertSucceeds(getDoc(doc(db('member'), ...live)));
    });
  });

  test('unauthenticated users can read nothing in the tour group', async () => {
    await assertFails(getDoc(doc(anon(), 'memberships', `${TOUR}__${people.member.email}`)));
    await assertFails(getDoc(doc(anon(), 'invites', CODE)));
  });
});
