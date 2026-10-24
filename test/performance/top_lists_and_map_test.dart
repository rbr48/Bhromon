import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/database/app_database.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/core/value_objects/trust_tier.dart';
import 'package:bhromon/features/explorer/data/repositories/explorer_repository_impl.dart';
import 'package:bhromon/features/map/data/repositories/map_repository_impl.dart';
import 'package:bhromon/features/map/presentation/utils/map_math.dart';
import 'package:bhromon/features/offline_vault/data/datasources/sync_manager.dart';
import 'package:bhromon/features/pro_tip/data/repositories/pro_tip_repository_impl.dart';

import '../helpers/fake_firestore.dart';
import '../helpers/perf_fixtures.dart';

void main() {
  late FakeFirestore fs;

  setUp(() => fs = FakeFirestore());

  group('top-N lists read only N documents', () {
    test('top explorers: 10 reads from 2,000 profiles, highest first',
        () async {
      for (var i = 0; i < 2000; i++) {
        fs.seed('explorer_profiles', 'u$i', profileDoc((i * 7919) % 2000));
      }
      final repo = ExplorerRepositoryImpl(fs);

      final top =
          (await repo.getTopExplorers(limit: 10)).getOrElse(() => throw 'x');

      expect(fs.documentsRead, 10, reason: 'was 2,000 reads per feed load');
      final scores = top.map((p) => p.explorerScore.value).toList();
      expect(
          scores, [1999, 1998, 1997, 1996, 1995, 1994, 1993, 1992, 1991, 1990]);
    });

    test('latest tips: 20 reads from 1,500 tips, most helpful first', () async {
      for (var i = 0; i < 1500; i++) {
        fs.seed('pro_tips', 't$i', tipDoc(i));
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ProTipRepositoryImpl.withOnlineCheck(
        fs,
        HiveEncryptionService.withStorage(CountingSecureStorage()),
        SyncManager.withDependencies(db, fs, isOnline: () async => true),
        () async => true,
      );

      final tips =
          (await repo.getLatestTips(limit: 20)).getOrElse(() => throw 'x');

      expect(fs.documentsRead, 20, reason: 'was 1,500 reads per feed load');
      expect(tips.first.helpfulVotes, 1499);
      expect(tips.map((t) => t.helpfulVotes).toList(),
          [for (var v = 1499; v > 1479; v--) v]);
    });
  });

  group('MapRepositoryImpl', () {
    late AppDatabase db;
    late DateTime now;
    late MapRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      now = DateTime(2026, 10, 1, 12);
      repo = MapRepositoryImpl.withDependencies(
          fs, db, () async => true, () => now);
      for (var i = 0; i < 1000; i++) {
        fs.seed('location_pins', 'p$i', pinDoc(i));
      }
    });

    tearDown(() => db.close());

    test('concurrent screens share one network read', () async {
      // The feed, map and Discover each ask for pins as they open.
      final results = await Future.wait([
        repo.getPinsInProximity(23.6, 90.3, 50),
        repo.getPinsInProximity(23.6, 90.3, 50),
        repo.getPinsInProximity(23.6, 90.3, 500),
      ]);

      expect(fs.queriesByCollection['location_pins'], 1);
      for (final r in results) {
        expect(r.getOrElse(() => []), hasLength(1000));
      }
    });

    test('cache serves repeat requests until it expires', () async {
      await repo.getPinsInProximity(0, 0, 1);
      now = now.add(const Duration(minutes: 9));
      await repo.getPinsInProximity(0, 0, 1);
      expect(fs.queriesByCollection['location_pins'], 1);

      now = now.add(const Duration(minutes: 2));
      await repo.getPinsInProximity(0, 0, 1);
      expect(fs.queriesByCollection['location_pins'], 2);
    });

    test('confirming a pin invalidates the cache', () async {
      await repo.getPinsInProximity(0, 0, 1);
      await repo.confirmPin('p1');
      await repo.getPinsInProximity(0, 0, 1);
      expect(fs.queriesByCollection['location_pins'], 2);
    });

    test('1,000 pins are cached locally in one batch', () async {
      await repo.getPinsInProximity(0, 0, 1);
      final rows = await db.getAllPointsOfInterest();
      expect(rows, hasLength(1000));
      expect(rows.firstWhere((r) => r.id == 'p7').title, 'Pin 7');
    });

    test('batched write beats one statement per row (timing, informational)',
        () async {
      final rows = [
        for (var i = 0; i < 1000; i++)
          PointsOfInterestTableCompanion.insert(
            id: 'x$i',
            districtId: 'd',
            title: 't',
            category: 'c',
            latitude: 1,
            longitude: 1,
          ),
      ];
      final sw = Stopwatch()..start();
      await db.savePointsOfInterest(rows);
      final batched = sw.elapsedMicroseconds;

      sw.reset();
      for (var i = 0; i < 1000; i++) {
        await db.savePointOfInterest('y$i', 'd', 't', 'c', 1, 1, null, null);
      }
      final sequential = sw.elapsedMicroseconds;
      // ignore: avoid_print
      print('1,000 POI upserts: batched ${batched ~/ 1000} ms, '
          'sequential ${sequential ~/ 1000} ms');
      expect((await db.getAllPointsOfInterest()).length, 2000);
    });
  });

  group('map math', () {
    LocationPin pin(String id, double lat, double lng) => LocationPin(
          pinId: id,
          name: id,
          geoHash: '',
          lat: lat,
          lng: lng,
          trustTier: TrustTier.verified,
          lastConfirmed: DateTime(2026),
          linkedTripIds: const [],
          linkedTipIds: const [],
          division: 'Dhaka',
          district: 'Dhaka',
          createdByUid: 'u',
        );

    test('tracking mode does not flap on GPS speed noise at a boundary', () {
      // Speed jitters around the old 1.0 m/s cut-off.
      final noisy = [for (var i = 0; i < 200; i++) i.isEven ? 0.9 : 1.1];

      MapTrackingMode oldMode(double s) => s < 1.0
          ? MapTrackingMode.stationary
          : s < 8.0
              ? MapTrackingMode.moving
              : MapTrackingMode.fast;

      var oldSwitches = 0;
      var prevOld = MapTrackingMode.moving;
      var newSwitches = 0;
      var mode = MapTrackingMode.moving;
      for (final s in noisy) {
        final o = oldMode(s);
        if (o != prevOld) oldSwitches++;
        prevOld = o;
        final n = nextTrackingMode(mode, s);
        if (n != mode) newSwitches++;
        mode = n;
      }

      expect(oldSwitches, greaterThan(150),
          reason: 'each switch restarted the GPS stream');
      expect(newSwitches, 0);
    });

    test('tracking mode still follows real speed changes', () {
      var mode = MapTrackingMode.stationary;
      mode = nextTrackingMode(mode, 2.0);
      expect(mode, MapTrackingMode.moving);
      mode = nextTrackingMode(mode, 12.0);
      expect(mode, MapTrackingMode.fast);
      mode = nextTrackingMode(mode, 8.0); // inside the band: stays fast
      expect(mode, MapTrackingMode.fast);
      mode = nextTrackingMode(mode, 5.0);
      expect(mode, MapTrackingMode.moving);
      mode = nextTrackingMode(mode, 0.2);
      expect(mode, MapTrackingMode.stationary);
      expect(nextTrackingMode(mode, double.nan), MapTrackingMode.stationary);
    });

    test('clustering assigns every pin exactly once and groups neighbours', () {
      final pins = [
        pin('a', 23.700, 90.400),
        pin('b', 23.701, 90.401),
        pin('c', 22.300, 91.800),
      ];
      final clusters = clusterPins(pins, 8);
      final ids = clusters.expand((c) => c.pins).map((p) => p.pinId).toList()
        ..sort();
      expect(ids, ['a', 'b', 'c']);
      expect(
          clusters
              .firstWhere((c) => c.pins.length == 2)
              .pins
              .map((p) => p.pinId),
          containsAll(['a', 'b']));
    });

    test('clustering 20,000 pins is a single pass (timing, informational)', () {
      final pins = [
        for (var i = 0; i < 20000; i++)
          pin('p$i', 20.5 + (i % 400) * 0.015, 88.0 + (i ~/ 400) * 0.08),
      ];
      final sw = Stopwatch()..start();
      final clusters = clusterPins(pins, 6);
      final elapsed = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print(
          'clusterPins: 20,000 pins -> ${clusters.length} clusters in $elapsed ms');
      expect(clusters.fold<int>(0, (n, c) => n + c.pins.length), 20000);
      expect(elapsed, lessThan(2000));
    });

    test('viewport culling keeps only pins in the padded bounds', () {
      final pins = [
        pin('in', 23.7, 90.4),
        pin('edge', 23.95, 90.4),
        pin('out', 25.0, 90.4)
      ];
      const bounds =
          GeoBounds(south: 23.5, west: 90.2, north: 23.9, east: 90.6);
      expect(pinsInBounds(pins, bounds).map((p) => p.pinId), ['in']);
      expect(pinsInBounds(pins, bounds.expandedBy(0.5)).map((p) => p.pinId),
          ['in', 'edge']);
      expect(pinsInBounds(pins, null), hasLength(3));
    });
  });
}
