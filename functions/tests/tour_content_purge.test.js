// A person's content leaves a tour with them, and a deleted tour leaves nothing:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/tour_content_purge"
const admin = require('firebase-admin');
const {
  purgeMemberContent,
  purgeTour,
  runPurgeJob,
  retryPendingJobs,
} = require('../src/tourContentPurge');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tour_sajek';
const OTHER_TOUR = 'tour_dhaka';
const LEAVER = 'leaver@x.com';
const OTHER = 'friend@x.com';

// Each phase queries the emulator in turn, which takes seconds on a slow machine.
jest.setTimeout(120000);

let db;

async function clearEmulator() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
}

async function exists(path) {
  return (await db.doc(path).get()).exists;
}

async function read(path) {
  return (await db.doc(path).get()).data();
}

async function seed() {
  const set = (path, data) => db.doc(path).set(data);

  await set(`tours/${TOUR}`, { ownerEmail: OTHER, name: 'Sajek' });
  await set(`tours/${OTHER_TOUR}`, { ownerEmail: OTHER, name: 'Dhaka' });
  await set(`memberships/${TOUR}__${LEAVER}`, { tourId: TOUR, email: LEAVER });
  await set(`memberships/${TOUR}__${OTHER}`, { tourId: TOUR, email: OTHER });
  await set(`memberships/${OTHER_TOUR}__${LEAVER}`, {
    tourId: OTHER_TOUR,
    email: LEAVER,
  });
  await set('invites/CODE1', { tourId: TOUR });

  // Posts, and comments under them.
  await set(`tours/${TOUR}/posts/p_leaver`, {
    authorEmail: LEAVER,
    likes: [OTHER],
  });
  await set(`tours/${TOUR}/posts/p_leaver/comments/c_leaver`, {
    authorEmail: LEAVER,
  });
  await set(`tours/${TOUR}/posts/p_other`, {
    authorEmail: OTHER,
    likes: [LEAVER, OTHER],
    viewers: [LEAVER],
  });
  await set(`tours/${TOUR}/posts/p_other/comments/c_other`, {
    authorEmail: OTHER,
    likes: [LEAVER],
  });
  await set(`tours/${TOUR}/posts/p_other/comments/c_leaver`, {
    authorEmail: LEAVER,
    likes: [],
  });

  // Stories, with the leaver's views, reactions and poll vote on another's.
  await set(`tours/${TOUR}/stories/s_leaver`, {
    authorEmail: LEAVER,
    viewers: [OTHER],
  });
  await set(`tours/${TOUR}/stories/s_other`, {
    authorEmail: OTHER,
    viewers: [LEAVER, OTHER],
    reactions: { [LEAVER]: '😀', [OTHER]: '👍' },
    poll: { votes: { [LEAVER]: 0, [OTHER]: 1 } },
  });

  // Highlights.
  await set(`tours/${TOUR}/highlights/h_leaver`, { createdByEmail: LEAVER });
  await set(`tours/${TOUR}/highlights/h_other`, { createdByEmail: OTHER });

  // Group chat: messages, reactions and votes, typing and voice presence.
  await set(`tours/${TOUR}/channels/general`, { name: 'General' });
  await set(`tours/${TOUR}/channels/general/messages/m_leaver`, {
    senderEmail: LEAVER,
    text: 'hi',
  });
  await set(`tours/${TOUR}/channels/general/messages/m_other`, {
    senderEmail: OTHER,
    text: 'hello',
    reactions: { [LEAVER]: '❤️', [OTHER]: '👍' },
    votes: { [LEAVER]: 1, [OTHER]: 0 },
  });
  await set(`tours/${TOUR}/channels/general/typing/${LEAVER}`, { at: 1 });
  await set(`tours/${TOUR}/channels/general/typing/${OTHER}`, { at: 1 });
  await set(`tours/${TOUR}/channels/general/voice_participants/${LEAVER}`, {
    muted: false,
  });

  // Presence.
  await set(`tours/${TOUR}/presence/${LEAVER}`, { online: true });
  await set(`tours/${TOUR}/presence/${OTHER}`, { online: true });

  // The same person's content in another tour.
  await set(`tours/${OTHER_TOUR}/posts/p_leaver`, {
    authorEmail: LEAVER,
    likes: [LEAVER],
  });
  await set(`tours/${OTHER_TOUR}/channels/general/messages/m_leaver`, {
    senderEmail: LEAVER,
    text: 'hi',
  });
}

beforeAll(() => {
  if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
  db = admin.firestore();
});

beforeEach(async () => {
  await clearEmulator();
  await seed();
});

describe('tour content purge', () => {
  it('removing a member clears their content from the tour and keeps everyone else’s', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const media = [];
    await purgeMemberContent(db, TOUR, LEAVER, async (tourId, email) => {
      media.push([tourId, email]);
    });

    // Their own content is gone, with the comments under their posts.
    expect(await exists(`tours/${TOUR}/posts/p_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/posts/p_leaver/comments/c_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/posts/p_other/comments/c_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/stories/s_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/highlights/h_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/channels/general/messages/m_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/channels/general/typing/${LEAVER}`)).toBe(false);
    expect(await exists(`tours/${TOUR}/channels/general/voice_participants/${LEAVER}`)).toBe(false);
    expect(await exists(`tours/${TOUR}/presence/${LEAVER}`)).toBe(false);

    // Everyone else’s content stays, with the person taken out of it.
    const post = await read(`tours/${TOUR}/posts/p_other`);
    expect(post.likes).toEqual([OTHER]);
    expect(post.viewers).toEqual([]);
    expect((await read(`tours/${TOUR}/posts/p_other/comments/c_other`)).likes).toEqual([]);

    const story = await read(`tours/${TOUR}/stories/s_other`);
    expect(story.viewers).toEqual([OTHER]);
    expect(story.reactions).toEqual({ [OTHER]: '👍' });
    expect(story.poll.votes).toEqual({ [OTHER]: 1 });
    expect(await exists(`tours/${TOUR}/highlights/h_other`)).toBe(true);

    const message = await read(`tours/${TOUR}/channels/general/messages/m_other`);
    expect(message.reactions).toEqual({ [OTHER]: '👍' });
    expect(message.votes).toEqual({ [OTHER]: 0 });
    expect(await exists(`tours/${TOUR}/channels/general/typing/${OTHER}`)).toBe(true);
    expect(await exists(`tours/${TOUR}/presence/${OTHER}`)).toBe(true);
    expect(await exists(`memberships/${TOUR}__${OTHER}`)).toBe(true);

    // Another tour is untouched.
    expect((await read(`tours/${OTHER_TOUR}/posts/p_leaver`)).likes).toEqual([LEAVER]);
    expect(await exists(`tours/${OTHER_TOUR}/channels/general/messages/m_leaver`)).toBe(true);

    expect(media).toEqual([[TOUR, LEAVER]]);
  });

  it('deleting a tour removes everything in it and its media, and no other tour', async () => {
    const media = [];
    await purgeTour(db, TOUR, async (tourId, email) => {
      media.push([tourId, email]);
    });

    expect(await exists(`tours/${TOUR}`)).toBe(false);
    expect(await exists(`tours/${TOUR}/posts/p_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/posts/p_other/comments/c_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/stories/s_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/channels/general/messages/m_other`)).toBe(false);
    expect(await exists(`memberships/${TOUR}__${LEAVER}`)).toBe(false);
    expect(await exists(`memberships/${TOUR}__${OTHER}`)).toBe(false);
    expect(await exists('invites/CODE1')).toBe(false);

    expect(await exists(`tours/${OTHER_TOUR}/posts/p_leaver`)).toBe(true);
    expect(await exists(`memberships/${OTHER_TOUR}__${LEAVER}`)).toBe(true);

    expect(media).toEqual([[TOUR, null]]);
  });

  it('a purge whose media step fails stays pending until a retry finishes it', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const failing = async () => {
      throw new Error('media server down');
    };
    await runPurgeJob(db, { kind: 'member', tourId: TOUR, email: LEAVER }, failing);

    const pending = await db.collection('tour_purge_jobs').get();
    expect(pending.size).toBe(1);
    expect(pending.docs[0].data()).toMatchObject({ status: 'pending', attempts: 1 });
    // The content steps ran before the media step failed.
    expect(await exists(`tours/${TOUR}/posts/p_leaver`)).toBe(false);

    const media = [];
    await retryPendingJobs(db, async (tourId, email) => {
      media.push([tourId, email]);
    });

    expect(media).toEqual([[TOUR, LEAVER]]);
    expect((await db.collection('tour_purge_jobs').get()).size).toBe(0);
  });

  it('a person who has rejoined keeps their content', async () => {
    // The membership row from the seed still exists: they hold a place again.
    const media = [];
    await purgeMemberContent(db, TOUR, LEAVER, async (tourId, email) => {
      media.push([tourId, email]);
    });

    expect(await exists(`tours/${TOUR}/posts/p_leaver`)).toBe(true);
    expect(await exists(`tours/${TOUR}/channels/general/messages/m_leaver`)).toBe(true);
    expect(media).toEqual([]);
  });
});
