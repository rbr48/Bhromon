// A study group's reading sessions: the agenda, the link, the timer and the recap, and each member's answer
// (going, maybe or cannot) and check-in. The reminder times belong to the media server. Runs against the
// Firestore emulator on port 8080:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/study_sessions_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
  deleteField,
} = require('firebase/firestore');

// Starting the emulator and loading the rules can take longer than Jest's default five seconds.
jest.setTimeout(60000);

const PROJECT_ID = 'bhromon-rules-test-project';
const CLUB = 'sessclub';
const BOOK = 'b1';
const SOON = 's1'; // planned by the member, starts in 2099
const STARTED = 's2'; // planned by the member, started in 2000
const REMINDED = 's3'; // planned by the member, the media server has sent its reminders
const people = {
  owner: { uid: 'ssowner', email: 'ssowner@x.com' },
  admin: { uid: 'ssadmin', email: 'ssadmin@x.com' },
  member: { uid: 'ssmem', email: 'ssmem@x.com' },
  other: { uid: 'ssother', email: 'ssother@x.com' },
  outsider: { uid: 'sseve', email: 'sseve@x.com' },
};

const sessionFields = (by, extra = {}) => ({
  title: 'Chapters 1 to 3',
  bookId: BOOK,
  chapterIds: null,
  startsAt: Timestamp.fromDate(new Date('2099-01-01T18:00:00Z')),
  place: null,
  notes: null,
  createdByEmail: by,
  ...extra,
});

const sessionRef = (f, id = SOON) => doc(f, 'tours', CLUB, 'reading_sessions', id);
const rsvpRef = (f, email, id = SOON) =>
  doc(f, 'tours', CLUB, 'reading_sessions', id, 'rsvps', email);

describe('study sessions: agenda, link, timer, recap, RSVPs and check-ins', () => {
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
      await setDoc(doc(f, 'tours', CLUB), {
        name: 'Reading group',
        kind: 'family',
        preset: 'study',
        ownerEmail: people.owner.email,
        ownerUid: people.owner.uid,
        inviteCode: 'SESSCL001',
      });
      const membership = (email, role) =>
        setDoc(doc(f, 'memberships', `${CLUB}__${email}`), { tourId: CLUB, email, role, status: 'active', displayName: email });
      await membership(people.owner.email, 'owner');
      await membership(people.admin.email, 'admin');
      await membership(people.member.email, 'member');
      await membership(people.other.email, 'member');
      await setDoc(doc(f, 'tours', CLUB, 'study_books', BOOK), {
        title: 'Anna Karenina',
        createdByEmail: people.admin.email,
        approval: 'listed',
        status: 'toRead',
      });
      await setDoc(sessionRef(f, SOON), sessionFields(people.member.email));
      await setDoc(sessionRef(f, STARTED), sessionFields(people.member.email, {
        startsAt: Timestamp.fromDate(new Date('2000-01-01T18:00:00Z')),
      }));
      await setDoc(sessionRef(f, REMINDED), sessionFields(people.member.email, {
        reminder24Sent: Timestamp.fromDate(new Date('2098-12-31T18:00:00Z')),
      }));
    });
  });

  describe('editing a session', () => {
    test('its creator sets the agenda, a link, a timer and a recap', async () => {
      await assertSucceeds(updateDoc(sessionRef(db('member')), {
        agenda: 'Read chapter 1; note the train scene.',
        link: 'https://meet.example.com/room',
        timerStartsAt: serverTimestamp(),
        timerSeconds: 1500,
        recap: { covered: 'Chapter 1', hard: 'The names', openQuestions: ['Why the train?'] },
        recapAt: serverTimestamp(),
      }));
    });

    test('another member cannot edit the session; an admin can write its recap', async () => {
      await assertFails(updateDoc(sessionRef(db('other')), { agenda: 'Mine now' }));
      await assertSucceeds(updateDoc(sessionRef(db('admin')), { recap: { covered: 'Chapter 1' } }));
    });

    test('the agenda can be any length', async () => {
      await assertSucceeds(updateDoc(sessionRef(db('member')), { agenda: 'x'.repeat(500) }));
      await assertSucceeds(updateDoc(sessionRef(db('member')), { agenda: 'x'.repeat(501) }));
    });

    test('a link is an https address', async () => {
      await assertFails(updateDoc(sessionRef(db('member')), { link: 'http://meet.example.com' }));
      await assertFails(updateDoc(sessionRef(db('member')), { link: 'meet.example.com' }));
      await assertSucceeds(updateDoc(sessionRef(db('member')), { link: 'https://meet.example.com/x' }));
    });

    test('a timer is between one minute and four hours', async () => {
      await assertFails(updateDoc(sessionRef(db('member')), { timerSeconds: 59 }));
      await assertSucceeds(updateDoc(sessionRef(db('member')), { timerSeconds: 60 }));
      await assertSucceeds(updateDoc(sessionRef(db('member')), { timerSeconds: 14400 }));
      await assertFails(updateDoc(sessionRef(db('member')), { timerSeconds: 14401 }));
    });

    test('a recap has at most ten open questions and no other fields', async () => {
      const ten = Array.from({ length: 10 }, (_, i) => `Question ${i}`);
      const eleven = Array.from({ length: 11 }, (_, i) => `Question ${i}`);
      await assertSucceeds(updateDoc(sessionRef(db('member')), { recap: { openQuestions: ten } }));
      await assertFails(updateDoc(sessionRef(db('member')), { recap: { openQuestions: eleven } }));
      await assertFails(updateDoc(sessionRef(db('member')), { recap: { covered: 'Ch 1', rating: 5 } }));
    });

    test('a session cannot be created with reminder times already set', async () => {
      await assertFails(setDoc(sessionRef(db('member'), 'n1'), {
        ...sessionFields(people.member.email),
        reminder24Sent: Timestamp.fromDate(new Date('2098-12-31T18:00:00Z')),
      }));
    });

    test('an edit keeps the reminder times the media server has set', async () => {
      await assertSucceeds(updateDoc(sessionRef(db('member'), REMINDED), { agenda: 'Read chapter 2' }));
      await assertFails(updateDoc(sessionRef(db('member'), REMINDED), { reminder24Sent: deleteField() }));
    });

    test('a change to the start may clear the reminder times, so they go out for the new time', async () => {
      await assertSucceeds(updateDoc(sessionRef(db('member'), REMINDED), {
        startsAt: Timestamp.fromDate(new Date('2099-02-01T18:00:00Z')),
        reminder24Sent: deleteField(),
      }));
    });
  });

  describe('answering and checking in', () => {
    test('a member answers for themselves: going, maybe or cannot', async () => {
      await assertSucceeds(setDoc(rsvpRef(db('other'), people.other.email), {
        response: 'going',
        updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(setDoc(rsvpRef(db('other'), people.other.email), {
        response: 'maybe',
        updatedAt: serverTimestamp(),
      }));
    });

    test('nobody answers for someone else, or with another answer', async () => {
      await assertFails(setDoc(rsvpRef(db('other'), people.member.email), {
        response: 'going',
        updatedAt: serverTimestamp(),
      }));
      await assertFails(setDoc(rsvpRef(db('other'), people.other.email), {
        response: 'yes',
        updatedAt: serverTimestamp(),
      }));
    });

    test('an answer carries the server time', async () => {
      await assertFails(setDoc(rsvpRef(db('other'), people.other.email), {
        response: 'going',
        updatedAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')),
      }));
    });

    test('a check-in is refused before the session starts', async () => {
      await assertFails(setDoc(rsvpRef(db('other'), people.other.email, SOON), {
        response: 'going',
        checkedInAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }));
    });

    test('a member checks in once the session has started, and a missed check-in is no fault', async () => {
      await assertSucceeds(setDoc(rsvpRef(db('other'), people.other.email, STARTED), {
        response: 'going',
        checkedInAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(setDoc(rsvpRef(db('member'), people.member.email, STARTED), {
        response: 'going',
        updatedAt: serverTimestamp(),
      }));
    });

    test('members read the answers; an outsider does not', async () => {
      await assertSucceeds(setDoc(rsvpRef(db('other'), people.other.email), {
        response: 'going',
        updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(getDoc(rsvpRef(db('member'), people.other.email)));
      await assertFails(getDoc(rsvpRef(db('outsider'), people.other.email)));
    });

    test('a member withdraws only their own answer', async () => {
      await assertSucceeds(setDoc(rsvpRef(db('other'), people.other.email), {
        response: 'going',
        updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(deleteDoc(rsvpRef(db('other'), people.other.email)));
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(rsvpRef(ctx.firestore(), people.member.email), {
          response: 'going',
          updatedAt: Timestamp.fromDate(new Date('2026-11-02T10:00:00Z')),
        });
      });
      await assertFails(deleteDoc(rsvpRef(db('other'), people.member.email)));
    });
  });
});
