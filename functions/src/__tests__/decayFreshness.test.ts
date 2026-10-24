import * as admin from 'firebase-admin';
import { FakeFirestore } from './helpers/fakeFirestore';

if (admin.apps.length === 0) admin.initializeApp();

const db = new FakeFirestore();
const sendEach = jest.fn(async (messages: any[]) => ({
  successCount: messages.length,
  failureCount: 0,
}));
jest.spyOn(admin, 'firestore' as any).mockReturnValue(db as any);
jest.spyOn(admin, 'messaging' as any).mockReturnValue({ sendEach } as any);

const { runDecayFreshness } = require('../decayFreshness');

describe('decayFreshness', () => {
  const now = new Date('2026-10-01T00:00:00Z');
  const old = new Date('2025-01-01T00:00:00Z');
  const recent = new Date('2026-09-01T00:00:00Z');

  beforeEach(() => {
    db.collections.clear();
    db.stats = { queryGets: 0, docGets: 0, getAllCalls: 0, batchCommits: 0, maxBatchWrites: 0 };
    sendEach.mockClear();
  });

  it('marks more than 500 stale tips without exceeding the batch limit', async () => {
    // 1,234 stale tips from 700 authors; the old single-batch version threw here.
    for (let i = 0; i < 1234; i++) {
      db.seed('pro_tips', `tip${i}`, {
        lastConfirmed: old,
        decayStatus: 'fresh',
        authorId: `author${i % 700}`,
      });
    }
    db.seed('pro_tips', 'fresh_tip', { lastConfirmed: recent, decayStatus: 'fresh', authorId: 'a' });
    db.seed('pro_tips', 'already', { lastConfirmed: old, decayStatus: 'stale', authorId: 'b' });
    for (let i = 0; i < 700; i++) db.seed('fcm_tokens', `author${i}`, { token: `tok${i}` });

    const result = await runDecayFreshness(now);

    expect(result.handled).toBe(1234);
    expect(result.exhausted).toBe(true);
    const stale = [...db.docs('pro_tips').values()].filter((t) => t.decayStatus === 'stale');
    expect(stale).toHaveLength(1235);
    expect(db.docs('pro_tips').get('fresh_tip')!.decayStatus).toBe('fresh');
    expect(db.stats.maxBatchWrites).toBeLessThanOrEqual(500);
  });

  it('notifies each author once, in batched sends with batched token reads', async () => {
    for (let i = 0; i < 1234; i++) {
      db.seed('pro_tips', `tip${i}`, {
        lastConfirmed: old,
        decayStatus: 'fresh',
        authorId: `author${i % 700}`,
      });
    }
    for (let i = 0; i < 700; i++) db.seed('fcm_tokens', `author${i}`, { token: `tok${i}` });

    const result = await runDecayFreshness(now);

    expect(result.notified).toBe(700);
    // 700 messages => two sendEach calls of at most 500.
    expect(sendEach).toHaveBeenCalledTimes(2);
    for (const [messages] of sendEach.mock.calls) {
      expect(messages.length).toBeLessThanOrEqual(500);
    }
    // Tokens via getAll (7 calls of 100), never one get() per author.
    expect(db.stats.docGets).toBe(0);
    expect(db.stats.getAllCalls).toBe(7);
  });

  it('skips authors without a token', async () => {
    db.seed('pro_tips', 't1', { lastConfirmed: old, decayStatus: 'fresh', authorId: 'has' });
    db.seed('pro_tips', 't2', { lastConfirmed: old, decayStatus: 'fresh', authorId: 'none' });
    db.seed('fcm_tokens', 'has', { token: 'x' });

    const result = await runDecayFreshness(now);

    expect(result.notified).toBe(1);
    expect(sendEach.mock.calls[0][0]).toHaveLength(1);
    expect(sendEach.mock.calls[0][0][0].data.uid).toBe('has');
  });
});
