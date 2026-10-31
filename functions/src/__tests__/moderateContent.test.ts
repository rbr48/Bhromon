import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
jest.mock('firebase-admin/firestore', () => ({ ...jest.requireActual<object>('firebase-admin/firestore'), getFirestore: jest.fn() }));
jest.mock('firebase-admin/messaging', () => ({ ...jest.requireActual<object>('firebase-admin/messaging'), getMessaging: jest.fn() }));
import { getApps, initializeApp } from 'firebase-admin/app';

// Initialize mock app for tests
if (getApps().length === 0) {
  initializeApp();
}

// ─── Shared Mock State ──────────────────────────────────────────────────────
let updateCalls: Record<string, any[]> = {};
let addCalls: any[] = [];
let targetAuthorId = 'author_123';
let spamFlagCount = 1;
let pioneerCount = 1;

let tokenGetAllCalls = 0;
let tokenDocGets = 0;

const mockDb = {
  getAll: async (...refs: any[]) => {
    tokenGetAllCalls++;
    return refs.map((ref) => ({
      exists: true,
      data: () => ({ token: `token_${ref.id}` }),
    }));
  },
  collection: (collectionName: string) => {
    return {
      doc: (docId: string) => ({
        id: docId,
        get: async () => {
          if (collectionName === 'trip_logs' || collectionName === 'pro_tips') {
            return {
              exists: true,
              data: () => ({ authorId: targetAuthorId, title: 'Sylhet Trip' }),
            };
          }
          if (collectionName === 'fcm_tokens') {
            tokenDocGets++;
            return {
              exists: true,
              data: () => ({ token: 'token_abc' }),
            };
          }
          return { exists: false };
        },
        update: async (data: any) => {
          if (!updateCalls[docId]) {
            updateCalls[docId] = [];
          }
          updateCalls[docId].push(data);
        },
      }),
      where: (field: string, op: string, value: any) => {
        return {
          get: async () => {
            if (collectionName === 'explorer_profiles' && field === 'tier' && value === 'pioneer') {
              return {
                docs: Array.from({ length: pioneerCount }, (_, i) => ({
                  id: `pioneer_${i + 1}`,
                  data: () => ({ tier: 'pioneer' }),
                })),
              };
            }
            return { docs: [] };
          },
          where: (field2: string, op2: string, value2: any) => ({
            count: () => ({
              get: async () => ({
                data: () => ({ count: spamFlagCount }),
              }),
            }),
          }),
        };
      },
      add: async (data: any) => {
        addCalls.push(data);
        return { id: 'new_event_id' };
      },
    };
  },
};

// Global mock of firestore and messaging BEFORE importing the module under test
jest.mocked(getFirestore).mockReturnValue(mockDb as any);
jest.spyOn(FieldValue, 'serverTimestamp').mockReturnValue('mock-server-timestamp' as any);
jest.mocked(getMessaging).mockReturnValue({
  sendEachForMulticast: jest.fn().mockResolvedValue({ successCount: 1, failureCount: 0 }),
} as any);

const { moderateContent } = require('../moderateContent');

describe('moderateContent', () => {
  beforeEach(() => {
    updateCalls = {};
    addCalls = [];
    targetAuthorId = 'author_123';
    spamFlagCount = 1;
    pioneerCount = 1;
    tokenGetAllCalls = 0;
    tokenDocGets = 0;
  });

  it('reads pioneer tokens with batched getAll, not one get per pioneer', async () => {
    pioneerCount = 250;
    const afterSnap = {
      data: () => ({
        type: 'safety_flag',
        targetId: 'trip_999',
        targetType: 'trip_log',
        actorId: 'reporter_1',
      }),
      exists: true,
    };

    await moderateContent.run(afterSnap as any, {} as any);

    expect(tokenDocGets).toBe(0);
    expect(tokenGetAllCalls).toBe(3); // 250 refs in chunks of 100
    const messaging = getMessaging() as any;
    const lastCall = messaging.sendEachForMulticast.mock.calls.at(-1)[0];
    expect(lastCall.tokens).toHaveLength(250);
  });

  it('handles safety_flag by immediately hiding the content and adding penalty', async () => {
    const afterSnap = {
      data: () => ({
        type: 'safety_flag',
        targetId: 'trip_123',
        targetType: 'trip_log',
        actorId: 'reporter_456',
      }),
      exists: true,
    };

    await moderateContent.run(afterSnap as any, {} as any);

    // Assert that the trip log was hidden
    expect(updateCalls['trip_123']).toBeDefined();
    expect(updateCalls['trip_123']![0]).toEqual({
      hidden: true,
      hiddenReason: 'safety_flag',
    });

    // Assert penalty event was created targeting the author
    expect(addCalls.length).toBe(1);
    expect(addCalls[0]).toEqual(expect.objectContaining({
      type: 'safety_flag_received',
      targetUid: 'author_123',
      actorId: 'reporter_456',
      weight: -10,
    }));
  });

  it('handles spam_flag and hides content if threshold of 2 is reached', async () => {
    spamFlagCount = 2; // threshold reached

    const afterSnap = {
      data: () => ({
        type: 'spam_flag',
        targetId: 'trip_123',
        targetType: 'trip_log',
        actorId: 'reporter_456',
      }),
      exists: true,
    };

    await moderateContent.run(afterSnap as any, {} as any);

    // Assert penalty event was created for spam
    expect(addCalls.length).toBe(1);
    expect(addCalls[0]).toEqual(expect.objectContaining({
      type: 'spam_flag_received',
      targetUid: 'author_123',
      actorId: 'reporter_456',
      weight: -5,
    }));

    // Assert content was hidden due to spam threshold
    expect(updateCalls['trip_123']![0]).toEqual({
      hidden: true,
      hiddenReason: 'spam_threshold',
    });
  });
});
