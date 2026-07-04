import * as admin from 'firebase-admin';

// Initialize mock app for tests
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// ─── Shared Mock State ──────────────────────────────────────────────────────
let capturedSets: Record<string, any[]> = {};
let currentEvents: any[] = [];

const mockDb = {
  collection: (collectionName: string) => {
    return {
      where: () => ({
        get: async () => ({
          forEach: (cb: (doc: { data: () => any }) => void) => {
            currentEvents.forEach(evt => cb({ data: () => evt }));
          },
        }),
      }),
      doc: (uid: string) => ({
        set: async (data: any, options: any) => {
          if (!capturedSets[collectionName]) {
            capturedSets[collectionName] = [];
          }
          capturedSets[collectionName].push({ data, options });
        },
        // Pioneer lookup in computeExplorerScore; no profile doc in tests.
        get: async () => ({ data: () => undefined, exists: false }),
      }),
    };
  },
};

// Global mock of firestore BEFORE importing the module under test
jest.spyOn(admin, 'firestore' as any).mockReturnValue(mockDb as any);
(admin.firestore as any).FieldValue = {
  serverTimestamp: () => 'mock-server-timestamp',
};

const { computeExplorerScore } = require('../computeExplorerScore');

describe('computeExplorerScore', () => {
  beforeEach(() => {
    capturedSets = {};
    currentEvents = [];
  });

  // computeExplorerScore is an authenticated https.onCall: invoke it with a
  // callable context (the old Firestore-trigger signature no longer exists).
  async function runFunction(events: any[], triggerUid: string) {
    currentEvents = events;
    await computeExplorerScore.run({}, { auth: { uid: triggerUid } } as any);
    return capturedSets;
  }

  describe('score calculation', () => {
    it('correctly sums weights from all trust_events for the user', async () => {
      const events = [
        { type: 'helpful_vote', targetUid: 'uid1', weight: 10 },
        { type: 'trip_published', targetUid: 'uid1', weight: 20 },
        { type: 'endorsement', targetUid: 'uid1', weight: 15 },
      ];

      const sets = await runFunction(events, 'uid1');
      const scoreData = sets['explorer_scores']?.[0]?.data;
      expect(scoreData).toBeDefined();
      expect(scoreData!.score).toBe(45);
    });
  });

  describe('tier assignment', () => {
    async function getTier(score: number): Promise<string> {
      const events = [{ type: 'helpful_vote', targetUid: 'uid2', weight: score }];
      const sets = await runFunction(events, 'uid2');
      return sets['explorer_scores']?.[0]?.data?.tier;
    }

    it('sets tier to "unverified" for score < 50', async () => {
      expect(await getTier(49)).toBe('unverified');
    });

    it('sets tier to "community" for score = 50', async () => {
      expect(await getTier(50)).toBe('community');
    });

    it('sets tier to "community" for score = 199', async () => {
      expect(await getTier(199)).toBe('community');
    });

    it('sets tier to "verified" for score = 200', async () => {
      expect(await getTier(200)).toBe('verified');
    });

    it('sets tier to "verified" for score = 499', async () => {
      expect(await getTier(499)).toBe('verified');
    });

    it('sets tier to "regionExpert" for score = 500', async () => {
      expect(await getTier(500)).toBe('regionExpert');
    });
  });
});
