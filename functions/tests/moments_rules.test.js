// Moments (tour feed) rules: story size limits and comments that a post's author has
// switched off. Runs against the Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/moments_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, setDoc, collection, addDoc, serverTimestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'trip';
const people = {
  author: { uid: 'mau', email: 'mau@x.com' },
  member: { uid: 'mme', email: 'mme@x.com' },
  outsider: { uid: 'mev', email: 'mev@x.com' },
};

describe('Moments rules', () => {
  let env;
  const db = (who) =>
    env.authenticatedContext(people[who].uid, { email: people[who].email, email_verified: true }).firestore();

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
      await setDoc(doc(f, 'tours', TOUR), { name: 'Trip', ownerEmail: 'owner@x.com', inviteCode: 'MOMENTS1' });
      const membership = (email) =>
        setDoc(doc(f, 'memberships', `${TOUR}__${email}`), { tourId: TOUR, email, role: 'member', status: 'active' });
      await membership(people.author.email);
      await membership(people.member.email);
      await setDoc(doc(f, 'tours', TOUR, 'posts', 'open'), {
        authorEmail: people.author.email,
        caption: 'Sunrise',
        images: [],
        disableComments: false,
        createdAt: serverTimestamp(),
      });
      await setDoc(doc(f, 'tours', TOUR, 'posts', 'closed'), {
        authorEmail: people.author.email,
        caption: 'Quiet',
        images: [],
        disableComments: true,
        createdAt: serverTimestamp(),
      });
    });
  });

  const story = (overrides = {}) => ({
    authorEmail: people.member.email,
    authorName: 'Member',
    mediaUrl: 'https://bhromon.fun/media/trip/stories/a.jpg',
    caption: null,
    viewers: [],
    createdAt: serverTimestamp(),
    ...overrides,
  });

  test('a story with a caption of 2200 characters is accepted', async () => {
    const stories = collection(db('member'), 'tours', TOUR, 'stories');
    await assertSucceeds(addDoc(stories, story({ caption: 'a'.repeat(2200) })));
  });

  test('a story with a caption over 2200 characters is refused', async () => {
    const stories = collection(db('member'), 'tours', TOUR, 'stories');
    await assertFails(addDoc(stories, story({ caption: 'a'.repeat(2201) })));
  });

  test('a story with a very long media link is refused', async () => {
    const stories = collection(db('member'), 'tours', TOUR, 'stories');
    const longLink = `https://bhromon.fun/media/trip/stories/${'a'.repeat(2100)}.jpg`;
    await assertFails(addDoc(stories, story({ mediaUrl: longLink })));
  });

  test('a poll with two options is accepted and one with five is refused', async () => {
    const stories = collection(db('member'), 'tours', TOUR, 'stories');
    const poll = (options) => ({ question: 'Lunch?', options, votes: {} });
    await assertSucceeds(addDoc(stories, story({ poll: poll(['Yes', 'No']) })));
    await assertFails(addDoc(stories, story({ poll: poll(['a', 'b', 'c', 'd', 'e']) })));
  });

  test('a story without a caption or poll is still accepted', async () => {
    const stories = collection(db('member'), 'tours', TOUR, 'stories');
    await assertSucceeds(addDoc(stories, story()));
  });

  test('a member can comment on a post that allows comments', async () => {
    const comments = collection(db('member'), 'tours', TOUR, 'posts', 'open', 'comments');
    await assertSucceeds(
      addDoc(comments, { authorEmail: people.member.email, text: 'Lovely', createdAt: serverTimestamp() }),
    );
  });

  test('nobody can comment on a post whose author turned comments off', async () => {
    const comments = collection(db('member'), 'tours', TOUR, 'posts', 'closed', 'comments');
    await assertFails(
      addDoc(comments, { authorEmail: people.member.email, text: 'Hello?', createdAt: serverTimestamp() }),
    );
  });
});
