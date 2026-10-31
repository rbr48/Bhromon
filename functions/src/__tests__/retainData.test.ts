import { getFirestore, Timestamp } from 'firebase-admin/firestore';
jest.mock('firebase-admin/firestore', () => ({ ...jest.requireActual<object>('firebase-admin/firestore'), getFirestore: jest.fn() }));
import { getApps, initializeApp } from 'firebase-admin/app';
import { FakeFirestore } from './helpers/fakeFirestore';

if (getApps().length === 0) initializeApp();

const db = new FakeFirestore();
jest.mocked(getFirestore).mockReturnValue(db as any);

const { runRetention } = require('../retainData');

describe('retainData', () => {
  const now = 1_800_000_000; // seconds
  const ts = (secondsAgo: number) => new Timestamp(now - secondsAgo, 0);
  const DAY = 24 * 3600;

  beforeEach(() => {
    db.collections.clear();
    db.stats = { queryGets: 0, docGets: 0, getAllCalls: 0, batchCommits: 0, maxBatchWrites: 0, singleUpdates: 0 };
  });

  it('clears the whole backlog in one run, not 100 per day', async () => {
    for (let i = 0; i < 950; i++) db.seed('trust_events', `old${i}`, { timestamp: ts(400 * DAY) });
    for (let i = 0; i < 5; i++) db.seed('trust_events', `new${i}`, { timestamp: ts(30 * DAY) });
    for (let i = 0; i < 420; i++) db.seed('admin_audit_logs', `old${i}`, { timestamp: ts(800 * DAY) });
    for (let i = 0; i < 3; i++) db.seed('admin_audit_logs', `keep${i}`, { timestamp: ts(400 * DAY) });

    const result = await runRetention(now);

    expect(result.trust).toEqual({ handled: 950, exhausted: true });
    expect(result.audit).toEqual({ handled: 420, exhausted: true });
    expect(db.docs('trust_events').size).toBe(5);
    expect(db.docs('admin_audit_logs').size).toBe(3);
    expect(db.stats.maxBatchWrites).toBeLessThanOrEqual(500);
  });

  it('does nothing when no documents are old enough', async () => {
    db.seed('trust_events', 'recent', { timestamp: ts(DAY) });
    const result = await runRetention(now);
    expect(result.trust.handled).toBe(0);
    expect(db.stats.batchCommits).toBe(0);
  });
});
