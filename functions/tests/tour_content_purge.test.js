// A person's content leaves a tour with them, and a deleted tour leaves nothing:
//   firebase emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/tour_content_purge"
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  purgeMemberContent,
  purgeTour,
  runPurgeJob,
  retryPendingJobs,
} = require('../src/tourContentPurge');
const { formerMemberId, FORMER_MEMBER_NAME } = require('../src/lib/tourContentPlan');

const PROJECT_ID = 'bhromon-rules-test-project';
const TOUR = 'tour_sajek';
const OTHER_TOUR = 'tour_dhaka';
const LEAVER = 'leaver@x.com';
const OTHER = 'friend@x.com';
const LEAVER_UID = 'uid_leaver';
const STAND_IN = formerMemberId(TOUR, LEAVER);

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

/** A player row as the app writes it at a game table. */
function seated(email, seatIndex, extra = {}) {
  return {
    email,
    displayName: email.split('@')[0],
    seatIndex,
    isReady: true,
    isHost: false,
    isBot: false,
    ...extra,
  };
}

async function seed() {
  const set = (path, data) => db.doc(path).set(data);

  await set(`tours/${TOUR}`, { ownerEmail: OTHER, name: 'Sajek' });
  await set(`tours/${OTHER_TOUR}`, { ownerEmail: OTHER, name: 'Dhaka' });
  await set(`memberships/${TOUR}__${LEAVER}`, { tourId: TOUR, email: LEAVER, uid: LEAVER_UID, status: 'active' });
  await set(`memberships/${TOUR}__${OTHER}`, { tourId: TOUR, email: OTHER, uid: 'uid_other', status: 'active' });
  await set(`memberships/${OTHER_TOUR}__${LEAVER}`, {
    tourId: OTHER_TOUR,
    email: LEAVER,
    status: 'active',
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
    tags: [LEAVER, OTHER],
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
  await set(`tours/${TOUR}/channels/general`, {
    name: 'General',
    createdByEmail: LEAVER,
    updatedByEmail: OTHER,
  });
  await set(`tours/${TOUR}/channels/general/messages/m_leaver`, {
    senderEmail: LEAVER,
    text: 'hi',
  });
  await set(`tours/${TOUR}/channels/general/messages/m_other`, {
    senderEmail: OTHER,
    text: 'hello',
    reactions: { [LEAVER]: '❤️', [OTHER]: '👍' },
    votes: { [LEAVER]: 1, [OTHER]: 0 },
    pinnedByEmail: LEAVER,
    mentions: [LEAVER, OTHER],
  });
  await set(`tours/${TOUR}/channels/general/typing/${LEAVER}`, { at: 1 });
  await set(`tours/${TOUR}/channels/general/typing/${OTHER}`, { at: 1 });
  await set(`tours/${TOUR}/channels/general/voice_participants/${LEAVER}`, {
    muted: false,
  });
  // A voice pair named by the two emails, sorted, with a candidate under it.
  await set(`tours/${TOUR}/channels/general/voice_signals/${OTHER}__${LEAVER}`, { offer: 'x' });
  await set(`tours/${TOUR}/channels/general/voice_signals/${OTHER}__${LEAVER}/offerCandidates/c1`, { c: 'x' });
  await set(`tours/${TOUR}/channels/general/voice_signals/a@x.com__${OTHER}`, { offer: 'y' });

  // Presence, location, battery telemetry and the legacy member row.
  await set(`tours/${TOUR}/presence/${LEAVER}`, { online: true });
  await set(`tours/${TOUR}/presence/${OTHER}`, { online: true });
  await set(`tours/${TOUR}/locations/${LEAVER}`, { email: LEAVER, lat: 23.8, lng: 90.4 });
  await set(`tours/${TOUR}/locations/${OTHER}`, { email: OTHER, lat: 22.3, lng: 91.8 });
  await set(`tours/${TOUR}/telemetry/${LEAVER}`, { email: LEAVER, batteryLevel: 40 });
  await set(`tours/${TOUR}/telemetry/${OTHER}`, { email: OTHER, batteryLevel: 80 });
  await set(`tours/${TOUR}/members/m_leaver`, { email: LEAVER, name: 'Leaver' });
  await set(`tours/${TOUR}/members/m_other`, { email: OTHER, name: 'Friend' });

  // Safety alerts: one the leaver raised, one of another's that the leaver resolved.
  await set(`tours/${TOUR}/sos/a_leaver`, {
    senderEmail: LEAVER,
    senderName: 'Rajib',
    latitude: 23.8,
    longitude: 90.4,
    resolved: false,
  });
  await set(`tours/${TOUR}/sos/a_other`, {
    senderEmail: OTHER,
    resolved: true,
    resolvedByEmail: LEAVER,
  });

  // The group's shared record: money, notices and route stops.
  await set(`tours/${TOUR}/expenses/e_leaver`, {
    title: 'Lunch',
    amountPaisa: 50000,
    addedByEmail: LEAVER,
    paidById: LEAVER,
    paidByName: 'Leaver',
    participantIds: [LEAVER, OTHER],
    splitShares: { [LEAVER]: 30000, [OTHER]: 20000 },
    receiptUrl: `https://bhromon.fun/media/${TOUR}/expenses/r1.jpg`,
  });
  await set(`tours/${TOUR}/expenses/e_other`, {
    title: 'Tea',
    amountPaisa: 9000,
    addedByEmail: OTHER,
    paidById: OTHER,
    participantIds: [OTHER, LEAVER],
    receiptUrl: `https://bhromon.fun/media/${TOUR}/expenses/r2.jpg`,
  });
  await set(`tours/${TOUR}/deposits/d_leaver`, {
    addedByEmail: LEAVER,
    memberId: LEAVER,
    memberName: 'Leaver',
    amountPaisa: 100000,
  });
  await set(`tours/${TOUR}/transfers/t_leaver`, {
    addedByEmail: LEAVER,
    fromId: LEAVER,
    fromName: 'Leaver',
    toId: OTHER,
    toName: 'Friend',
    amountPaisa: 5000,
  });
  await set(`tours/${TOUR}/notices/n1`, {
    authorEmail: LEAVER,
    author: 'Leaver',
    ackBy: [LEAVER, OTHER],
    text: 'Bus at six',
  });
  await set(`tours/${TOUR}/checklist/c1`, { title: 'Torch', checkedBy: [LEAVER, OTHER] });
  await set(`tours/${TOUR}/checkpoints/cp1`, { name: 'Tea stall', addedByEmail: LEAVER, kmFromStart: 10 });
  await set(`tours/${TOUR}/meta/itinerary`, { currentStopId: 's1', updatedByEmail: LEAVER });

  // What only the person used: luggage, seats, rooms, game tables and their profile.
  await set(`tours/${TOUR}/luggage/l_leaver`, { ownerEmail: LEAVER, ownerName: 'Leaver', title: 'Bag' });
  await set(`tours/${TOUR}/luggage/l_other`, {
    ownerEmail: OTHER,
    custodianEmail: LEAVER,
    custodianName: 'Leaver',
    title: 'Box',
  });
  await set(`tours/${TOUR}/bus_seats/A1`, { seatNumber: 'A1', assignedMemberEmail: LEAVER, assignedMemberName: 'Leaver' });
  await set(`tours/${TOUR}/bus_seats/A2`, { seatNumber: 'A2', assignedMemberEmail: OTHER });
  await set(`tours/${TOUR}/vehicle_seats/v1__1A`, { seatNumber: '1A', vehicleId: 'v1', assignedMemberEmail: LEAVER });
  await set(`tours/${TOUR}/hotel_rooms/r1`, {
    hotelName: 'Hill Inn',
    assignedMemberEmails: [OTHER, LEAVER],
    assignedMemberNames: ['Friend', 'Leaver'],
  });
  await set(`tours/${TOUR}/games/g1`, {
    gameType: 'carrom',
    hostEmail: OTHER,
    players: [{ email: OTHER }, { email: LEAVER }],
  });
  await set(`tours/${TOUR}/games/g1/private/s1`, { owner: LEAVER, cards: ['AS'] });
  await set(`tours/${TOUR}/games/g2`, { gameType: 'ludo', hostEmail: OTHER, players: [{ email: OTHER }] });
  // A 29 table in play, with the person as host in seat 0 and bots in the rest.
  await set(`tours/${TOUR}/games/g3`, {
    gameType: 'card29',
    status: 'inProgress',
    hostEmail: LEAVER,
    players: [
      seated(LEAVER, 0, { isHost: true }),
      seated(OTHER, 1),
      seated('bot_seat_2@bhromon.fun', 2, { isBot: true }),
      seated('bot_seat_3@bhromon.fun', 3, { isBot: true }),
    ],
  });
  await set(`tours/${TOUR}/games/g3/private/seat0`, { owner: LEAVER, cards: ['AS'] });
  await set(`tours/${TOUR}/games/g3/private/seat1`, { owner: OTHER, cards: ['KD'] });
  // A Teen Patti lobby the person hosts, with another member at it.
  await set(`tours/${TOUR}/games/g4`, {
    gameType: 'teen_patti',
    status: 'waiting',
    hostEmail: LEAVER,
    players: [seated(LEAVER, 0, { isHost: true }), seated(OTHER, 1)],
  });
  // A Teen Patti lobby the person hosts, with only a bot left at it.
  await set(`tours/${TOUR}/games/g8`, {
    gameType: 'teen_patti',
    status: 'waiting',
    hostEmail: LEAVER,
    players: [seated(LEAVER, 0, { isHost: true }), seated('bot_seat_1@bhromon.fun', 1, { isBot: true })],
  });
  // A chess table the person is alone at, and a ludo table they host with another member.
  await set(`tours/${TOUR}/games/g5`, {
    gameType: 'chess',
    status: 'waiting',
    hostEmail: LEAVER,
    players: [seated(LEAVER, 0, { isHost: true })],
  });
  await set(`tours/${TOUR}/games/g6`, {
    gameType: 'ludo',
    status: 'waiting',
    hostEmail: LEAVER,
    players: [seated(LEAVER, 0, { isHost: true }), seated(OTHER, 1)],
  });
  // A 29 table in play that the person is alone at, with a bot in the other seat.
  await set(`tours/${TOUR}/games/g7`, {
    gameType: 'card29',
    status: 'inProgress',
    hostEmail: LEAVER,
    players: [seated(LEAVER, 0, { isHost: true }), seated('bot_seat_1@bhromon.fun', 1, { isBot: true })],
  });
  await set(`tours/${TOUR}/games/g7/private/seat0`, { owner: LEAVER, cards: ['9H'] });
  await set(`tours/${TOUR}/profiles/pr_leaver`, { uid: LEAVER_UID, email: LEAVER, displayName: 'Leaver' });
  await set(`tours/${TOUR}/profiles/pr_other`, { uid: 'uid_other', email: OTHER });

  // The same person's content in another tour.
  await set(`tours/${OTHER_TOUR}/posts/p_leaver`, {
    authorEmail: LEAVER,
    likes: [LEAVER],
  });
  await set(`tours/${OTHER_TOUR}/channels/general/messages/m_leaver`, {
    senderEmail: LEAVER,
    text: 'hi',
  });
  await set(`tours/${OTHER_TOUR}/expenses/e_leaver`, {
    addedByEmail: LEAVER,
    paidById: LEAVER,
    paidByName: 'Leaver',
    participantIds: [LEAVER],
    amountPaisa: 100,
  });
}

// Fake outside services. The media fake records what it was asked, and
// returns the paths it removed.
function fakes(removedPaths = []) {
  const calls = { media: [], storage: [] };
  return {
    calls,
    deps: {
      purgeMedia: async (tourId, email) => {
        calls.media.push([tourId, email]);
        return removedPaths;
      },
      purgeStorage: async (tourId, email) => {
        calls.storage.push([tourId, email]);
      },
      resolveUid: async (email) => (email === LEAVER ? LEAVER_UID : null),
    },
  };
}

beforeAll(() => {
  if (!getApps().length) initializeApp({ projectId: PROJECT_ID });
  db = getFirestore();
});

beforeEach(async () => {
  await clearEmulator();
  await seed();
});

describe('tour content purge', () => {
  it('removing a member clears their content from the tour and keeps everyone else’s', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { calls, deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

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
    expect(post.tags).toEqual([OTHER]);
    expect((await read(`tours/${TOUR}/posts/p_other/comments/c_other`)).likes).toEqual([]);

    const story = await read(`tours/${TOUR}/stories/s_other`);
    expect(story.viewers).toEqual([OTHER]);
    expect(story.reactions).toEqual({ [OTHER]: '👍' });
    expect(story.poll.votes).toEqual({ [OTHER]: 1 });
    expect(await exists(`tours/${TOUR}/highlights/h_other`)).toBe(true);

    const message = await read(`tours/${TOUR}/channels/general/messages/m_other`);
    expect(message.reactions).toEqual({ [OTHER]: '👍' });
    expect(message.votes).toEqual({ [OTHER]: 0 });
    expect(message.mentions).toEqual([OTHER]);
    expect(message.pinnedByEmail).toBe(STAND_IN);
    expect(await exists(`tours/${TOUR}/channels/general/typing/${OTHER}`)).toBe(true);
    expect(await exists(`tours/${TOUR}/presence/${OTHER}`)).toBe(true);
    expect(await exists(`memberships/${TOUR}__${OTHER}`)).toBe(true);

    // Another tour is untouched.
    expect((await read(`tours/${OTHER_TOUR}/posts/p_leaver`)).likes).toEqual([LEAVER]);
    expect(await exists(`tours/${OTHER_TOUR}/channels/general/messages/m_leaver`)).toBe(true);
    expect((await read(`tours/${OTHER_TOUR}/expenses/e_leaver`)).addedByEmail).toBe(LEAVER);

    expect(calls.media).toEqual([[TOUR, LEAVER]]);
    expect(calls.storage).toEqual([[TOUR, LEAVER]]);
  });

  it('the ledger keeps every amount and balance, with the person replaced by the stand-in', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    const lunch = await read(`tours/${TOUR}/expenses/e_leaver`);
    expect(lunch).toMatchObject({
      title: 'Lunch',
      amountPaisa: 50000,
      addedByEmail: STAND_IN,
      paidById: STAND_IN,
      paidByName: FORMER_MEMBER_NAME,
      participantIds: [STAND_IN, OTHER],
      splitShares: { [STAND_IN]: 30000, [OTHER]: 20000 },
    });

    // An expense they did not enter keeps its author, and only the share changes hands.
    const tea = await read(`tours/${TOUR}/expenses/e_other`);
    expect(tea.addedByEmail).toBe(OTHER);
    expect(tea.participantIds).toEqual([OTHER, STAND_IN]);
    expect(tea.amountPaisa).toBe(9000);

    expect(await read(`tours/${TOUR}/deposits/d_leaver`)).toMatchObject({
      addedByEmail: STAND_IN,
      memberId: STAND_IN,
      memberName: FORMER_MEMBER_NAME,
      amountPaisa: 100000,
    });
    expect(await read(`tours/${TOUR}/transfers/t_leaver`)).toMatchObject({
      addedByEmail: STAND_IN,
      fromId: STAND_IN,
      fromName: FORMER_MEMBER_NAME,
      toId: OTHER,
      toName: 'Friend',
      amountPaisa: 5000,
    });
  });

  it('notices, the packing list and route stops keep the record and drop the person', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect(await read(`tours/${TOUR}/notices/n1`)).toMatchObject({
      authorEmail: STAND_IN,
      author: FORMER_MEMBER_NAME,
      ackBy: [OTHER],
      text: 'Bus at six',
    });
    expect((await read(`tours/${TOUR}/checklist/c1`)).checkedBy).toEqual([OTHER]);
    expect((await read(`tours/${TOUR}/checkpoints/cp1`)).addedByEmail).toBe(STAND_IN);
    expect((await read(`tours/${TOUR}/meta/itinerary`)).updatedByEmail).toBe(STAND_IN);
    expect((await read(`tours/${TOUR}/channels/general`)).createdByEmail).toBe(STAND_IN);
    expect((await read(`tours/${TOUR}/channels/general`)).updatedByEmail).toBe(OTHER);
  });

  it('removes what the person alone used: luggage, seats, rooms and profiles', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect(await exists(`tours/${TOUR}/luggage/l_leaver`)).toBe(false);
    expect(await read(`tours/${TOUR}/luggage/l_other`)).toMatchObject({
      custodianEmail: null,
      custodianName: null,
    });
    expect(await exists(`tours/${TOUR}/bus_seats/A1`)).toBe(false);
    expect(await exists(`tours/${TOUR}/bus_seats/A2`)).toBe(true);
    expect(await exists(`tours/${TOUR}/vehicle_seats/v1__1A`)).toBe(false);

    expect(await read(`tours/${TOUR}/hotel_rooms/r1`)).toMatchObject({
      assignedMemberEmails: [OTHER],
      assignedMemberNames: ['Friend'],
    });

    expect(await exists(`tours/${TOUR}/profiles/pr_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/profiles/pr_other`)).toBe(true);
  });

  it('at a game table only the person’s seat goes: the table keeps the others, and their cards go', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    const carrom = await read(`tours/${TOUR}/games/g1`);
    expect(carrom.players).toEqual([{ email: OTHER }]);
    expect(carrom.hostEmail).toBe(OTHER);
    expect(await exists(`tours/${TOUR}/games/g1/private/s1`)).toBe(false);

    // A table the person is not at is untouched.
    expect(await read(`tours/${TOUR}/games/g2`)).toMatchObject({ hostEmail: OTHER, players: [{ email: OTHER }] });
  });

  it('a 29 table in play hands the person’s seat to a bot, and passes the host on', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    const table = await read(`tours/${TOUR}/games/g3`);
    expect(table.hostEmail).toBe(OTHER);
    expect(table.players).toHaveLength(4);
    expect(table.players[0]).toMatchObject({ email: 'bot_seat_0@bhromon.fun', seatIndex: 0, isBot: true, isHost: false });
    expect(table.players[1]).toMatchObject({ email: OTHER, isHost: true });
    expect(table.players.some((p) => p.email === LEAVER)).toBe(false);
    // The cards at the person's seat now belong to the bot; the other seat is untouched.
    expect(await read(`tours/${TOUR}/games/g3/private/seat0`)).toMatchObject({ owner: 'bot_seat_0@bhromon.fun' });
    expect(await read(`tours/${TOUR}/games/g3/private/seat1`)).toMatchObject({ owner: OTHER });
  });

  it('a lobby passes its host on rather than closing, and a lobby with only bots left ends', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    const lobby = await read(`tours/${TOUR}/games/g4`);
    expect(lobby.hostEmail).toBe(OTHER);
    expect(lobby.players).toHaveLength(1);
    expect(lobby.players[0]).toMatchObject({ email: OTHER, isHost: true });

    expect(await read(`tours/${TOUR}/games/g6`)).toMatchObject({
      hostEmail: OTHER,
      players: [{ email: OTHER, isHost: true }],
    });
    expect(await exists(`tours/${TOUR}/games/g8`)).toBe(false);
  });

  it('a table the person is alone at ends with its seats, whether in play or not', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect(await exists(`tours/${TOUR}/games/g5`)).toBe(false);
    expect(await exists(`tours/${TOUR}/games/g7`)).toBe(false);
    expect(await exists(`tours/${TOUR}/games/g7/private/seat0`)).toBe(false);
  });

  it('removes the location, telemetry and legacy member row of the person, and keeps their safety alerts', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect(await exists(`tours/${TOUR}/locations/${LEAVER}`)).toBe(false);
    expect(await exists(`tours/${TOUR}/locations/${OTHER}`)).toBe(true);
    expect(await exists(`tours/${TOUR}/telemetry/${LEAVER}`)).toBe(false);
    expect(await exists(`tours/${TOUR}/telemetry/${OTHER}`)).toBe(true);
    expect(await exists(`tours/${TOUR}/members/m_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/members/m_other`)).toBe(true);

    // The alert the person raised stays, resolved, under the stand-in, with no location.
    const raised = await read(`tours/${TOUR}/sos/a_leaver`);
    expect(raised).toMatchObject({
      senderEmail: STAND_IN,
      senderName: FORMER_MEMBER_NAME,
      resolved: true,
      resolvedByEmail: STAND_IN,
    });
    expect(raised).not.toHaveProperty('latitude');
    expect(raised).not.toHaveProperty('longitude');
    expect(raised.resolvedAt).toBeDefined();

    expect(await read(`tours/${TOUR}/sos/a_other`)).toMatchObject({
      senderEmail: OTHER,
      resolved: true,
      resolvedByEmail: STAND_IN,
    });
  });

  it('removes the person’s voice pairs, and keeps the pairs of others', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    const pairs = `tours/${TOUR}/channels/general/voice_signals`;
    expect(await exists(`${pairs}/${OTHER}__${LEAVER}`)).toBe(false);
    expect(await exists(`${pairs}/${OTHER}__${LEAVER}/offerCandidates/c1`)).toBe(false);
    expect(await exists(`${pairs}/a@x.com__${OTHER}`)).toBe(true);
  });

  it('a receipt whose file was removed loses its link and nothing else', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes(['expenses/r1.jpg']);
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect((await read(`tours/${TOUR}/expenses/e_leaver`)).receiptUrl).toBeNull();
    expect((await read(`tours/${TOUR}/expenses/e_other`)).receiptUrl).toBe(
      `https://bhromon.fun/media/${TOUR}/expenses/r2.jpg`,
    );
  });

  it('the person is found by their account id when the job does not carry it', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const { deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect(await exists(`tours/${TOUR}/profiles/pr_leaver`)).toBe(false);
  });

  it('a purge whose media step fails stays pending until a retry finishes it', async () => {
    await db.doc(`memberships/${TOUR}__${LEAVER}`).delete();
    const failing = async () => {
      throw new Error('media server down');
    };
    const failingDeps = { ...fakes().deps, purgeMedia: failing };
    await runPurgeJob(db, { kind: 'member', tourId: TOUR, email: LEAVER, uid: LEAVER_UID }, failingDeps);

    const pending = await db.collection('tour_purge_jobs').get();
    expect(pending.size).toBe(1);
    expect(pending.docs[0].data()).toMatchObject({ status: 'pending', attempts: 1, uid: LEAVER_UID });
    // The content steps ran before the media step failed.
    expect(await exists(`tours/${TOUR}/posts/p_leaver`)).toBe(false);

    const { calls, deps } = fakes();
    await retryPendingJobs(db, deps);

    expect(calls.media).toEqual([[TOUR, LEAVER]]);
    expect((await db.collection('tour_purge_jobs').get()).size).toBe(0);
  });

  it('a person who has rejoined keeps their content', async () => {
    // The membership row from the seed still exists: they hold a place again.
    const { calls, deps } = fakes();
    await purgeMemberContent(db, TOUR, LEAVER, deps);

    expect(await exists(`tours/${TOUR}/posts/p_leaver`)).toBe(true);
    expect(await exists(`tours/${TOUR}/channels/general/messages/m_leaver`)).toBe(true);
    expect((await read(`tours/${TOUR}/expenses/e_leaver`)).addedByEmail).toBe(LEAVER);
    expect(calls.media).toEqual([]);
    expect(calls.storage).toEqual([]);
  });

  it('deleting a tour removes everything in it and its media, and no other tour', async () => {
    const { calls, deps } = fakes();
    await purgeTour(db, TOUR, deps);

    expect(await exists(`tours/${TOUR}`)).toBe(false);
    expect(await exists(`tours/${TOUR}/posts/p_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/posts/p_other/comments/c_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/stories/s_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/channels/general/messages/m_other`)).toBe(false);
    expect(await exists(`tours/${TOUR}/expenses/e_leaver`)).toBe(false);
    expect(await exists(`tours/${TOUR}/games/g1/private/s1`)).toBe(false);
    expect(await exists(`tours/${TOUR}/locations/${LEAVER}`)).toBe(false);
    expect(await exists(`memberships/${TOUR}__${LEAVER}`)).toBe(false);
    expect(await exists(`memberships/${TOUR}__${OTHER}`)).toBe(false);
    expect(await exists('invites/CODE1')).toBe(false);

    expect(await exists(`tours/${OTHER_TOUR}/posts/p_leaver`)).toBe(true);
    expect(await exists(`memberships/${OTHER_TOUR}__${LEAVER}`)).toBe(true);
    expect((await read(`tours/${OTHER_TOUR}/expenses/e_leaver`)).addedByEmail).toBe(LEAVER);

    expect(calls.media).toEqual([[TOUR, null]]);
    expect(calls.storage).toEqual([[TOUR, null]]);
  });
});
