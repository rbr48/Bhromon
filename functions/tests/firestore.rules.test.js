const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'bhromon-rules-test-project';

describe('Firestore Security Rules', () => {
  let testEnv;
  let rulesContent;

  beforeAll(async () => {
    // Read local rules file
    const rulesPath = path.resolve(__dirname, '../../firestore.rules');
    rulesContent = fs.readFileSync(rulesPath, 'utf8');

    // Initialize rules-unit-testing environment
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: rulesContent,
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  afterAll(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  // Helper to get authenticated context
  function getAuthenticatedContext(uid, email = 'user@example.com') {
    return testEnv.authenticatedContext(uid, {
      email: email,
      email_verified: true,
    });
  }

  // Helper to get unauthenticated context
  function getUnauthenticatedContext() {
    return testEnv.unauthenticatedContext();
  }

  // Helper to seed database as admin
  async function seedDocument(collectionPath, docId, data) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection(collectionPath).doc(docId).set(data);
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Collection 1: users & explorer_profiles
  // ───────────────────────────────────────────────────────────────────────────
  describe('Users & Explorer Profiles', () => {
    const userUid = 'user_123';
    const profileData = {
      uid: userUid,
      displayName: 'Jane Doe',
      // Client-creatable shape: privileged trust fields (tier, score) may
      // only start at their defaults — Cloud Functions promote them later.
      tier: 'unverified',
      isPioneer: false,
      isRegionExpert: false,
      explorerScore: { value: 0, tier: 'unverified' },
      createdAt: new Date(),
    };

    test('allow read/write own explorer profile', async () => {
      const client = getAuthenticatedContext(userUid).firestore();
      await assertSucceeds(client.collection('explorer_profiles').doc(userUid).set(profileData));
      await assertSucceeds(client.collection('explorer_profiles').doc(userUid).get());
    });

    test('deny write to other user explorer profile', async () => {
      const client = getAuthenticatedContext('attacker_456').firestore();
      await assertFails(client.collection('explorer_profiles').doc(userUid).set(profileData));
    });

    test('deny users modifying their own tier directly', async () => {
      await seedDocument('explorer_profiles', userUid, profileData);
      const client = getAuthenticatedContext(userUid).firestore();
      
      // Attempt to upgrade tier directly (rules must protect tier fields)
      await assertFails(
        client.collection('explorer_profiles').doc(userUid).update({
          tier: 'pioneer',
        })
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Collection 2: trip_logs
  // ───────────────────────────────────────────────────────────────────────────
  describe('Trip Logs', () => {
    const ownerUid = 'trip_owner_123';
    const tripLogId = 'trip_abc';
    const tripLogData = {
      id: tripLogId,
      authorId: ownerUid,
      title: 'Beautiful Travel to Sylhet',
      description: 'Sylhet tea gardens and lakes',
      hidden: false,
      tier: 'community',
      trustScore: 80,
      createdAt: new Date(),
    };

    beforeEach(async () => {
      // Seed user explorer profile to satisfy isNotUnverified()
      await seedDocument('explorer_profiles', ownerUid, {
        uid: ownerUid,
        displayName: 'Trip Owner',
        tier: 'community',
      });
    });

    test('allow create trip log by authenticated user matching ownerUid', async () => {
      const client = getAuthenticatedContext(ownerUid).firestore();
      await assertSucceeds(client.collection('trip_logs').doc(tripLogId).set(tripLogData));
    });

    test('deny create trip log by other user or unauthenticated', async () => {
      const attackerClient = getAuthenticatedContext('attacker_456').firestore();
      await assertFails(attackerClient.collection('trip_logs').doc(tripLogId).set(tripLogData));

      const anonymousClient = getUnauthenticatedContext().firestore();
      await assertFails(anonymousClient.collection('trip_logs').doc(tripLogId).set(tripLogData));
    });

    test('deny write trip log with excessively long title (>200 chars)', async () => {
      const client = getAuthenticatedContext(ownerUid).firestore();
      const longTitleTrip = {
        ...tripLogData,
        title: 'A'.repeat(205),
      };
      await assertFails(client.collection('trip_logs').doc(tripLogId).set(longTitleTrip));
    });

    test('deny non-owner from updating trip log', async () => {
      await seedDocument('trip_logs', tripLogId, tripLogData);
      const client = getAuthenticatedContext('attacker_456').firestore();
      await assertFails(client.collection('trip_logs').doc(tripLogId).update({ title: 'Hacked Title' }));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Collection 3: trust_events
  // ───────────────────────────────────────────────────────────────────────────
  describe('Trust Events', () => {
    test('deny direct write to trust_events by client', async () => {
      const client = getAuthenticatedContext('user_123').firestore();
      await assertFails(
        client.collection('trust_events').doc('event_abc').set({
          uid: 'user_123',
          type: 'pioneer_bonus',
          scoreImpact: 50,
          timestamp: new Date(),
        })
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Collection 4: admin_audit_logs
  // ───────────────────────────────────────────────────────────────────────────
  describe('Admin Audit Logs', () => {
    test('deny read/write of admin_audit_logs by standard client', async () => {
      const client = getAuthenticatedContext('user_123').firestore();
      await assertFails(client.collection('admin_audit_logs').doc('log_123').get());
      await assertFails(client.collection('admin_audit_logs').doc('log_123').set({ action: 'hack' }));
    });
  });

  describe('Pin Visits', () => {
    test('anonymous clients cannot read visit history', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().collection('pin_visits').doc('v1').set({
          pinId: 'p1', userId: 'user_123', visitedAt: new Date(),
        });
      });
      const anon = testEnv.unauthenticatedContext().firestore();
      await assertFails(anon.collection('pin_visits').doc('v1').get());
    });

    test('signed-in users can read visits, and only write their own', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().collection('pin_visits').doc('v1').set({
          pinId: 'p1', userId: 'user_123', visitedAt: new Date(),
        });
      });
      const other = getAuthenticatedContext('user_999').firestore();
      await assertSucceeds(other.collection('pin_visits').doc('v1').get());
      await assertFails(other.collection('pin_visits').add({
        pinId: 'p1', userId: 'user_123', visitedAt: new Date(),
      }));
    });
  });
});
