import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/database/app_database.dart';
import 'package:bhromon/core/entities/outbox_entry.dart';
import 'package:bhromon/features/notifications/geo_fence_service.dart';
import 'package:bhromon/features/offline_vault/data/datasources/sync_manager.dart';

import '../helpers/fake_firestore.dart';

OutboxEntry _entry(int i,
        {String op = 'set',
        String? doc,
        Map<String, dynamic>? payload,
        int retry = 0}) =>
    OutboxEntry(
      id: 'e$i',
      operation: op,
      collectionPath: 'trip_logs',
      documentId: doc ?? 'doc$i',
      payload: payload ?? {'n': i},
      enqueuedAt: DateTime.fromMillisecondsSinceEpoch(1000000 + i),
      retryCount: retry,
      status: 'pending',
    );

Future<void> _enqueue(AppDatabase db, OutboxEntry e,
        {String status = 'pending'}) =>
    db.enqueueOutbox(
        e.id, e.enqueuedAt.millisecondsSinceEpoch, jsonEncode(e.toJson()),
        status: status);

void main() {
  late AppDatabase db;
  late FakeFirestore fs;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fs = FakeFirestore();
  });

  tearDown(() => db.close());

  group('SyncManager.flushOutbox', () {
    SyncManager manager({DateTime Function()? now}) =>
        SyncManager.withDependencies(db, fs,
            isOnline: () async => true, now: now);

    test('1,200 entries go out in 3 batches, not 1,200 round trips', () async {
      for (var i = 0; i < 1200; i++) {
        await _enqueue(db, _entry(i));
      }
      final sync = manager();
      addTearDown(sync.dispose);

      await sync.flushOutbox();

      expect(fs.committedBatchSizes, [500, 500, 200]);
      expect(fs.singleWrites, 0);
      expect(fs.docsIn('trip_logs'), hasLength(1200));
      expect(await db.getOutboxEntriesOrdered(), isEmpty);
    });

    test('a bad entry does not hold back the rest', () async {
      for (var i = 0; i < 10; i++) {
        await _enqueue(db, _entry(i));
      }
      fs.failingWrites['trip_logs/doc3'] = 'permission-denied';
      final sync = manager();
      addTearDown(sync.dispose);

      await sync.flushOutbox();

      // Batch rejected -> per-entry fallback: 9 sent, 1 parked as conflict.
      expect(fs.docsIn('trip_logs').keys.toSet(), {
        for (var i = 0; i < 10; i++)
          if (i != 3) 'doc$i'
      });
      expect(await db.getOutboxEntriesOrdered(), isEmpty);
      final conflicts = await db.getConflictsOrdered();
      expect(conflicts, hasLength(1));
      expect(conflicts.single, contains('"e3"'));
    });

    test('a transient failure backs off without blocking or waiting', () async {
      var now = DateTime(2026, 10, 1);
      final sync = manager(now: () => now);
      addTearDown(sync.dispose);
      for (var i = 0; i < 5; i++) {
        await _enqueue(db, _entry(i));
      }
      fs.failingWrites['trip_logs/doc0'] = 'unavailable';

      final sw = Stopwatch()..start();
      await sync.flushOutbox();

      // The old loop slept through the backoff (>= 1.5 s here) and then
      // stopped at the first failure, leaving every later entry unsent.
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(fs.docsIn('trip_logs').keys.toSet(),
          {'doc1', 'doc2', 'doc3', 'doc4'});
      expect(sync.hasScheduledRetry, isTrue);

      // Not due yet: another flush leaves it alone.
      fs.failingWrites.clear();
      await sync.flushOutbox();
      expect(fs.docsIn('trip_logs').keys, isNot(contains('doc0')));

      // Once the backoff has passed it goes out.
      now = now.add(const Duration(seconds: 5));
      await sync.flushOutbox();
      expect(fs.docsIn('trip_logs').keys, contains('doc0'));
      expect(await db.getOutboxEntriesOrdered(), isEmpty);
    });

    test('merged payloads are stored before the originals are dropped',
        () async {
      await _enqueue(
          db, _entry(1, op: 'update', doc: 'same', payload: {'a': 1}));
      await _enqueue(
          db, _entry(2, op: 'update', doc: 'same', payload: {'b': 2}));
      fs.seed('trip_logs', 'same', {'x': 0});
      fs.failingWrites['trip_logs/same'] = 'unavailable';
      final sync = manager();
      addTearDown(sync.dispose);

      await sync.flushOutbox();

      // Send failed: exactly one row remains, holding the merged payload.
      final rows = await db.getOutboxEntriesOrdered();
      expect(rows, hasLength(1));
      final stored =
          OutboxEntry.fromJson(jsonDecode(rows.single) as Map<String, dynamic>);
      expect(stored.payload, {'a': 1, 'b': 2});
      expect(stored.retryCount, 1);
    });

    test('claims left by a crashed flush are released and resent', () async {
      await _enqueue(db, _entry(1),
          status: 'processing'); // older app, no timestamp
      final sync = manager();
      addTearDown(sync.dispose);

      await sync.flushOutbox();

      expect(fs.docsIn('trip_logs').keys, ['doc1']);
    });

    test('an entry claimed moments ago by another isolate is left alone',
        () async {
      await _enqueue(db, _entry(1));
      await db.applyOutboxChanges(statusIds: ['e1'], status: 'processing');
      final sync = manager();
      addTearDown(sync.dispose);

      await sync.flushOutbox();

      expect(fs.docsIn('trip_logs'), isEmpty);
    });
  });

  group('AppDatabase schema v4', () {
    Future<Set<String>> indexNames(AppDatabase db) async {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      return rows.map((r) => r.read<String>('name')).toSet();
    }

    const wanted = {
      'trip_logs_pin_idx',
      'trip_logs_pin_draft_idx',
      'poi_district_idx',
      'outbox_status_enqueued_idx',
    };

    test('a fresh install gets the secondary indexes', () async {
      expect(await indexNames(db), containsAll(wanted));
    });

    test('upgrading a v3 database adds the column and the indexes', () async {
      // Build a v3 database: today's tables minus processing_since, no
      // secondary indexes, user_version 3.
      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      final ddl = await fresh
          .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL")
          .get();
      await fresh.close();
      final v3Tables = [
        for (final row in ddl)
          row
              .read<String>('sql')
              .replaceAll(RegExp(r',\s*"processing_since" INTEGER NULL'), ''),
      ];
      expect(v3Tables.any((t) => t.contains('processing_since')), isFalse);

      final upgraded =
          AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        for (final sql in v3Tables) {
          raw.execute(sql);
        }
        raw.execute(
            "INSERT INTO sync_outbox_table (id, enqueued_at, status, json_data) VALUES ('old', 1, 'processing', '{}')");
        raw.execute('PRAGMA user_version = 3');
      }));
      addTearDown(upgraded.close);

      expect(await indexNames(upgraded), containsAll(wanted));
      // The stuck claim from before the upgrade can now be released.
      final released = await upgraded
          .releaseStaleOutboxClaims(DateTime.now().millisecondsSinceEpoch);
      expect(released, 1);
    });

    test('draft lookups use the composite index', () async {
      final plan = await db.customSelect(
          'EXPLAIN QUERY PLAN SELECT * FROM trip_logs_table WHERE location_pin_id = ? AND is_draft = ?',
          variables: [
            const Variable<String>('p'),
            const Variable<int>(1)
          ]).get();
      final detail = plan.map((r) => r.read<String>('detail')).join(' ');
      expect(detail, contains('trip_logs_pin_draft_idx'));
    });

    test('applyOutboxChanges stamps and clears processing_since', () async {
      await _enqueue(db, _entry(1));
      await db.applyOutboxChanges(statusIds: ['e1'], status: 'processing');
      expect(await db.releaseStaleOutboxClaims(0), 0,
          reason: 'claimed just now');
      expect(
          await db.releaseStaleOutboxClaims(DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch),
          1);
      expect(await db.getOutboxEntriesOrdered(), hasLength(1));
    });

    test('savePointsOfInterest upserts in place', () async {
      await db.savePointsOfInterest([
        PointsOfInterestTableCompanion.insert(
            id: 'a',
            districtId: 'd',
            title: 'Old',
            category: 'c',
            latitude: 1,
            longitude: 1),
      ]);
      await db.savePointsOfInterest([
        PointsOfInterestTableCompanion.insert(
            id: 'a',
            districtId: 'd',
            title: 'New',
            category: 'c',
            latitude: 1,
            longitude: 1,
            description: const Value('x')),
      ]);
      final rows = await db.getAllPointsOfInterest();
      expect(rows.single.title, 'New');
    });
  });

  group('geo-fence pin selection', () {
    double flatDistance(double lat1, double lng1, double lat2, double lng2) =>
        ((lat1 - lat2).abs() + (lng1 - lng2).abs()) * 111000;
    final now = DateTime(2026, 10, 1, 12);

    test('picks the nearest visible pin in range, not the first match', () {
      final hit = nearestUntriggeredPin(
        lat: 0,
        lng: 0,
        candidates: const [
          GeoFenceCandidate(pinId: 'far', name: 'far', lat: 0.04, lng: 0),
          GeoFenceCandidate(pinId: 'near', name: 'near', lat: 0.01, lng: 0),
          GeoFenceCandidate(
              pinId: 'hidden', name: 'h', lat: 0.001, lng: 0, hidden: true),
          GeoFenceCandidate(pinId: 'out', name: 'o', lat: 1, lng: 0),
        ],
        lastTriggered: const {},
        now: now,
        distance: flatDistance,
      );
      expect(hit?.pin.pinId, 'near');
    });

    test('a pin fires at most once a day per device', () {
      GeoFenceCandidate near() => const GeoFenceCandidate(
          pinId: 'near', name: 'near', lat: 0.01, lng: 0);
      expect(
        nearestUntriggeredPin(
          lat: 0,
          lng: 0,
          candidates: [near()],
          lastTriggered: {'near': now.subtract(const Duration(hours: 3))},
          now: now,
          distance: flatDistance,
        ),
        isNull,
      );
      expect(
        nearestUntriggeredPin(
          lat: 0,
          lng: 0,
          candidates: [near()],
          lastTriggered: {'near': now.subtract(const Duration(hours: 25))},
          now: now,
          distance: flatDistance,
        )?.pin.pinId,
        'near',
      );
    });
  });

  group('lazy feed lists', () {
    // The feed used ListView(shrinkWrap: true, NeverScrollableScrollPhysics)
    // inside a SingleChildScrollView; it now uses a SliverList.
    testWidgets(
        'shrinkWrap-in-scroll-view builds every card; a sliver builds what is visible',
        (tester) async {
      var eagerBuilds = 0;
      await tester.pumpWidget(MaterialApp(
        home: SingleChildScrollView(
          child: Column(children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 300,
              itemBuilder: (_, i) {
                eagerBuilds++;
                return SizedBox(height: 120, child: Text('card $i'));
              },
            ),
          ]),
        ),
      ));

      var lazyBuilds = 0;
      await tester.pumpWidget(MaterialApp(
        home: CustomScrollView(slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 200)),
          SliverList.builder(
            itemCount: 300,
            itemBuilder: (_, i) {
              lazyBuilds++;
              return SizedBox(height: 120, child: Text('card $i'));
            },
          ),
        ]),
      ));

      // ignore: avoid_print
      print(
          '300 cards: shrinkWrap built $eagerBuilds, sliver built $lazyBuilds');
      expect(eagerBuilds, 300);
      expect(lazyBuilds, lessThan(15));
    });
  });
}
