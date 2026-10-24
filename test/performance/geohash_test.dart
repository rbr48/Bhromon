import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/database/app_database.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/core/geo/geohash.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/map/data/datasources/nearby_pins_query.dart';
import 'package:bhromon/features/map/data/repositories/map_repository_impl.dart';

import '../helpers/fake_firestore.dart';
import '../helpers/perf_fixtures.dart';

void main() {
  group('encodeGeohash', () {
    test('matches published reference values (same as the Cloud Function)', () {
      expect(encodeGeohash(57.64911, 10.40744, 11), 'u4pruydqqvj');
      expect(encodeGeohash(0, 0, 1), '7');
      expect(encodeGeohash(-90, -180, 6), '000000');
      expect(encodeGeohash(90, 180, 6), 'zzzzzz');
      expect(encodeGeohash(37.7853074, -122.4054274, 10), '9q8yywe56g');
      expect(encodeGeohash(23.8103, 90.4125), startsWith('wh'));
    });

    test('rejects invalid coordinates', () {
      expect(() => encodeGeohash(91, 0), throwsArgumentError);
      expect(() => encodeGeohash(double.nan, 0), throwsArgumentError);
    });
  });

  group('geohashQueryBounds', () {
    test('never misses a point inside the radius', () {
      final rng = math.Random(42);
      for (final radius in [500.0, 5000.0, 25000.0, 100000.0]) {
        for (var trial = 0; trial < 40; trial++) {
          final cLat = 20.6 + rng.nextDouble() * 6;
          final cLng = 88.0 + rng.nextDouble() * 4.6;
          final bounds = geohashQueryBounds(cLat, cLng, radius);
          for (var p = 0; p < 50; p++) {
            // Random point inside the circle.
            final r = radius * math.sqrt(rng.nextDouble()) * 0.999;
            final theta = rng.nextDouble() * 2 * math.pi;
            final pLat = cLat + (r * math.cos(theta)) / 111320;
            final pLng = cLng +
                (r * math.sin(theta)) /
                    (111320 * math.cos(cLat * math.pi / 180));
            if (distanceInMeters(cLat, cLng, pLat, pLng) > radius) continue;
            final hash = encodeGeohash(pLat, pLng);
            final covered = bounds.any(
                (b) => hash.compareTo(b.$1) >= 0 && hash.compareTo(b.$2) <= 0);
            expect(covered, isTrue,
                reason: 'r=$radius centre=($cLat,$cLng) point=($pLat,$pLng)');
          }
        }
      }
    });

    test('gives at most nine ranges', () {
      expect(geohashQueryBounds(23.8, 90.4, 5000).length, lessThanOrEqualTo(9));
    });

    test('distance matches known values', () {
      // Dhaka to Chattogram is ~215 km as the crow flies.
      final d = distanceInMeters(23.8103, 90.4125, 22.3569, 91.7832);
      expect(d, closeTo(215000, 10000));
    });
  });

  group('queryPinsNear', () {
    late FakeFirestore fs;

    setUp(() {
      fs = FakeFirestore();
      final rng = math.Random(7);
      // 2,000 pins across Bangladesh, with correct geohashes (backfilled).
      for (var i = 0; i < 2000; i++) {
        final lat = 20.6 + rng.nextDouble() * 6;
        final lng = 88.0 + rng.nextDouble() * 4.6;
        fs.seed('location_pins', 'p$i', {
          ...pinDoc(i, lat: lat, lng: lng),
          'geoHash': encodeGeohash(lat, lng)
        });
      }
      // Three pins near central Dhaka.
      for (var i = 0; i < 3; i++) {
        final lat = 23.8103 + i * 0.005, lng = 90.4125;
        fs.seed('location_pins', 'dhaka$i', {
          ...pinDoc(i, lat: lat, lng: lng),
          'geoHash': encodeGeohash(lat, lng)
        });
      }
    });

    test('finds exactly the pins in range while reading a small slice',
        () async {
      final docs = await queryPinsNear(fs, 23.8103, 90.4125, 5000);

      final expected = fs.docsIn('location_pins').entries.where((e) =>
          distanceInMeters(23.8103, 90.4125, e.value['lat'] as double,
              e.value['lng'] as double) <=
          5000);
      expect(docs.map((d) => d.id).toSet(), expected.map((e) => e.key).toSet());
      expect(
          docs.map((d) => d.id), containsAll(['dhaka0', 'dhaka1', 'dhaka2']));
      expect(fs.documentsRead, lessThan(60),
          reason: 'the whole collection is 2,003 documents');
    });

    test('falls back to a latitude band before the backfill has run', () async {
      final legacy = FakeFirestore();
      for (var i = 0; i < 100; i++) {
        legacy.seed('location_pins', 'p$i',
            pinDoc(i, lat: 22.0 + i * 0.05, lng: 90.4)); // no geoHash field
      }
      legacy.seed(
          'location_pins', 'near', pinDoc(0, lat: 23.8103, lng: 90.4125));

      final docs = await queryPinsNear(legacy, 23.8103, 90.4125, 5000);

      expect(docs.map((d) => d.id), contains('near'));
      expect(
          docs.every((d) =>
              distanceInMeters(23.8103, 90.4125, d.data()['lat'] as double,
                  d.data()['lng'] as double) <=
              5000),
          isTrue);
    });
  });

  test('new pins are saved with a real geohash', () async {
    final fs = FakeFirestore();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = MapRepositoryImpl.withDependencies(
        fs, db, () async => true, DateTime.now);

    final saved = (await repo.addPin(LocationPin(
      pinId: 'new',
      name: 'Lalbagh Fort',
      geoHash: 'w3', // what the add-pin dialog sends
      lat: 23.7188,
      lng: 90.3883,
      trustTier: TrustTier.unverified,
      lastConfirmed: DateTime(2026),
      linkedTripIds: const [],
      linkedTipIds: const [],
      division: 'Dhaka',
      district: 'Dhaka',
      createdByUid: 'me',
    )))
        .getOrElse(() => throw 'x');

    expect(saved.geoHash, encodeGeohash(23.7188, 90.3883));
    expect(fs.read('location_pins/new')!['geoHash'], saved.geoHash);
  });
}
