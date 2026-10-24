import { chunk, drainQuery, getAllInChunks } from '../lib/batching';
import { FakeFirestore } from './helpers/fakeFirestore';

describe('chunk', () => {
  it('splits into pieces no larger than the size, keeping order', () => {
    const items = Array.from({ length: 1201 }, (_, i) => i);
    const parts = chunk(items, 500);
    expect(parts.map((p) => p.length)).toEqual([500, 500, 201]);
    expect(parts.flat()).toEqual(items);
  });

  it('handles empty input and rejects a non-positive size', () => {
    expect(chunk([], 10)).toEqual([]);
    expect(() => chunk([1], 0)).toThrow();
  });
});

describe('getAllInChunks', () => {
  it('reads N documents in ceil(N/100) getAll calls and no single gets', async () => {
    const db = new FakeFirestore();
    for (let i = 0; i < 250; i++) db.seed('fcm_tokens', `u${i}`, { token: `t${i}` });
    const refs = Array.from({ length: 250 }, (_, i) => db.collection('fcm_tokens').doc(`u${i}`));

    const snaps = await getAllInChunks(db as any, refs as any);

    expect(snaps).toHaveLength(250);
    expect(snaps[249].data()?.token).toBe('t249');
    expect(db.stats.getAllCalls).toBe(3);
    expect(db.stats.docGets).toBe(0);
  });

  it('makes no call for no refs', async () => {
    const db = new FakeFirestore();
    expect(await getAllInChunks(db as any, [])).toEqual([]);
    expect(db.stats.getAllCalls).toBe(0);
  });
});

describe('drainQuery', () => {
  it('processes pages until the query is empty', async () => {
    const db = new FakeFirestore();
    for (let i = 0; i < 950; i++) db.seed('logs', `d${i}`, { old: true });
    const query = db.collection('logs').where('old', '==', true);

    const result = await drainQuery(query as any, async (docs) => {
      const batch = db.batch();
      docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }, { pageSize: 400 });

    expect(result).toEqual({ handled: 950, exhausted: true });
    expect(db.docs('logs').size).toBe(0);
    expect(db.stats.batchCommits).toBe(3);
    expect(db.stats.maxBatchWrites).toBeLessThanOrEqual(400);
  });

  it('stops after maxPages and reports that work remains', async () => {
    const db = new FakeFirestore();
    for (let i = 0; i < 100; i++) db.seed('logs', `d${i}`, { old: true });
    const query = db.collection('logs').where('old', '==', true);

    const result = await drainQuery(query as any, async (docs) => {
      const batch = db.batch();
      docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }, { pageSize: 10, maxPages: 3 });

    expect(result).toEqual({ handled: 30, exhausted: false });
    expect(db.docs('logs').size).toBe(70);
  });
});
