import * as admin from 'firebase-admin';
import { encodeGeohash } from '../lib/geohash';
import { FakeFirestore } from './helpers/fakeFirestore';

if (admin.apps.length === 0) admin.initializeApp();

const db = new FakeFirestore();
const { FieldPath } = admin.firestore;
jest.spyOn(admin, 'firestore' as any).mockReturnValue(db as any);
(admin.firestore as any).FieldPath = FieldPath;

const { expectedGeohash, maintainPinGeohash, runBackfill } = require('../maintainPinGeohash');

describe('encodeGeohash', () => {
  it('matches published reference values', () => {
    // Wikipedia's example, and geofire-common's test vectors.
    expect(encodeGeohash(57.64911, 10.40744, 11)).toBe('u4pruydqqvj');
    expect(encodeGeohash(0, 0, 1)).toBe('7');
    expect(encodeGeohash(-90, -180, 6)).toBe('000000');
    expect(encodeGeohash(90, 180, 6)).toBe('zzzzzz');
    expect(encodeGeohash(37.7853074, -122.4054274, 10)).toBe('9q8yywe56g');
  });

  it('puts Bangladesh in the w-cells', () => {
    expect(encodeGeohash(23.8103, 90.4125).startsWith('wh')).toBe(true); // Dhaka
    expect(encodeGeohash(21.4272, 92.0058).startsWith('w')).toBe(true); // Cox's Bazar
  });

  it('rejects invalid coordinates', () => {
    expect(() => encodeGeohash(91, 0)).toThrow();
    expect(() => encodeGeohash(NaN, 0)).toThrow();
  });
});

describe('maintainPinGeohash', () => {
  beforeEach(() => {
    db.collections.clear();
    db.stats = { queryGets: 0, docGets: 0, getAllCalls: 0, batchCommits: 0, maxBatchWrites: 0, singleUpdates: 0 };
  });

  const change = (id: string, after: any) => ({
    after: {
      exists: after !== undefined,
      data: () => after,
      ref: db.collection('location_pins').doc(id),
    },
  });

  it('writes the geohash for a pin missing one (or carrying a bad one)', async () => {
    db.seed('location_pins', 'p1', { lat: 23.8103, lng: 90.4125, geoHash: 'w3' });
    await maintainPinGeohash.run(change('p1', db.docs('location_pins').get('p1')), {} as any);
    expect(db.docs('location_pins').get('p1')!.geoHash).toBe(encodeGeohash(23.8103, 90.4125));
  });

  it('does not write when the stored geohash is already right (no trigger loop)', async () => {
    const good = { lat: 23.8103, lng: 90.4125, geoHash: encodeGeohash(23.8103, 90.4125) };
    db.seed('location_pins', 'p1', good);
    await maintainPinGeohash.run(change('p1', good), {} as any);
    expect(db.stats.singleUpdates).toBe(0);
  });

  it('ignores deletes and pins without coordinates', async () => {
    await maintainPinGeohash.run(change('gone', undefined), {} as any);
    await maintainPinGeohash.run(change('nocoords', { name: 'x' }), {} as any);
    expect(db.stats.singleUpdates).toBe(0);
    expect(expectedGeohash({ lat: '23', lng: 90 })).toBeNull();
  });
});

describe('runBackfill', () => {
  beforeEach(() => {
    db.collections.clear();
    db.stats = { queryGets: 0, docGets: 0, getAllCalls: 0, batchCommits: 0, maxBatchWrites: 0, singleUpdates: 0 };
  });

  it('fixes every pin in batches and reports when it is done', async () => {
    for (let i = 0; i < 1000; i++) {
      const id = `pin${String(i).padStart(4, '0')}`;
      const lat = 20.6 + (i % 50) * 0.1;
      const lng = 88.1 + Math.floor(i / 50) * 0.2;
      // Every third pin already correct.
      db.seed('location_pins', id, {
        lat, lng, geoHash: i % 3 === 0 ? encodeGeohash(lat, lng) : 'w3',
      });
    }

    const result = await runBackfill(null);

    expect(result.scanned).toBe(1000);
    expect(result.updated).toBe(666);
    expect(result.next).toBeNull();
    expect(db.stats.maxBatchWrites).toBeLessThanOrEqual(500);
    for (const [, pin] of db.docs('location_pins')) {
      expect(pin.geoHash).toBe(encodeGeohash(pin.lat, pin.lng));
    }
  });

  it('continues from the cursor it returned', async () => {
    for (let i = 0; i < 30; i++) {
      db.seed('location_pins', `p${String(i).padStart(2, '0')}`, { lat: 23, lng: 90 });
    }
    const result = await runBackfill('p19');
    expect(result.scanned).toBe(10);
    expect(db.docs('location_pins').get('p05')!.geoHash).toBeUndefined();
    expect(db.docs('location_pins').get('p25')!.geoHash).toBe(encodeGeohash(23, 90));
  });
});
