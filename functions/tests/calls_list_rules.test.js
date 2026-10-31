// The Calls tab lists the calls a person took part in. Runs against the Firestore
// emulator on port 8080, like the other rules suites:
//   npx firebase-tools@13.35.1 emulators:exec --only firestore --project bhromon-rules-test-project "cd functions && npx jest --runInBand tests/calls_list_rules"
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');
const { doc, setDoc, collection, getDocs, query, where, orderBy, limit, serverTimestamp } = require('firebase/firestore');

const PROJECT_ID = 'bhromon-rules-test-project';
const people = {
  a: { uid: 'calla', email: 'calla@x.com' },
  b: { uid: 'callb', email: 'callb@x.com' },
  outsider: { uid: 'calle', email: 'calle@x.com' },
};

describe('calls list rules', () => {
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
      await setDoc(doc(f, 'calls', 'c1'), {
        callerId: people.a.uid,
        calleeId: people.b.uid,
        participants: [people.a.uid, people.b.uid],
        sharedTourId: 'tour1',
        memberEmails: { [people.a.uid]: people.a.email, [people.b.uid]: people.b.email },
        isVideo: false,
        status: 'ended',
        createdAt: serverTimestamp(),
      });
    });
  });

  // The rules judge a list query by the fields it filters on. A filter on
  // `participants` cannot prove the caller or callee rule, so that query is denied,
  // and the Calls tab could not load. These filters can be proven, so they work.
  test('calls a person made, by the caller field', async () => {
    await assertSucceeds(getDocs(query(collection(db('a'), 'calls'), where('callerId', '==', people.a.uid))));
  });

  test('calls a person received, by the callee field', async () => {
    await assertSucceeds(getDocs(query(collection(db('b'), 'calls'), where('calleeId', '==', people.b.uid))));
  });

  test('calls stored with the email address, as older calls may be', async () => {
    await assertSucceeds(getDocs(query(collection(db('a'), 'calls'), where('callerId', '==', people.a.email))));
    await assertSucceeds(getDocs(query(collection(db('b'), 'calls'), where('calleeId', '==', people.b.email))));
  });

  test('a person who is not in a call cannot list it', async () => {
    await assertFails(getDocs(query(collection(db('outsider'), 'calls'), where('participants', 'array-contains', people.a.uid))));
  });
});
