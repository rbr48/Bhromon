import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/security/hive_encryption_service.dart';
import 'package:bhromon/core/utils/concurrency.dart';
import 'package:bhromon/core/utils/doc_future_cache.dart';
import 'package:bhromon/core/utils/image_sizing.dart';
import 'package:bhromon/core/utils/shared_latest_stream.dart';

import '../helpers/fake_firestore.dart';
import '../helpers/perf_fixtures.dart';

void main() {
  group('HiveEncryptionService', () {
    late Future<void> Function() cleanup;
    setUp(() async => cleanup = await setUpTempHive());
    tearDown(() => cleanup());

    test('reads the key from secure storage once, however many opens',
        () async {
      final storage = CountingSecureStorage();
      final service = HiveEncryptionService.withStorage(storage);

      // Concurrent opens (feed load + sync bar + saved logs at startup)...
      final boxes = await Future.wait([
        for (var i = 0; i < 20; i++)
          service.openEncryptedBox<dynamic>('feed_box'),
        for (var i = 0; i < 20; i++)
          service.openEncryptedBox<dynamic>('other_box'),
      ]);
      // ...and later ones, e.g. a draft save per edit.
      for (var i = 0; i < 50; i++) {
        await service.openEncryptedBox<dynamic>('feed_box');
      }

      expect(storage.reads, 1, reason: 'was one keystore read per open (90)');
      expect(boxes.take(20).toSet(), hasLength(1));
      expect(boxes.first.isOpen, isTrue);
    });

    test('reopens a box that was closed', () async {
      final service =
          HiveEncryptionService.withStorage(CountingSecureStorage());
      final box = await service.openEncryptedBox<dynamic>('b');
      await box.put('k', 'v');
      await box.close();
      final again = await service.openEncryptedBox<dynamic>('b');
      expect(again.isOpen, isTrue);
      expect(again.get('k'), 'v');
    });
  });

  group('SharedLatestStream', () {
    test('one upstream subscription, latest value replayed to late listeners',
        () async {
      var listens = 0;
      final source = StreamController<int>.broadcast(onListen: () => listens++);
      final shared = SharedLatestStream<int>(source.stream);

      final first = <int>[];
      final sub1 = shared.stream.listen(first.add);
      source.add(1);
      await Future<void>.delayed(Duration.zero);

      final late = <int>[];
      final sub2 = shared.stream.listen(late.add);
      await Future<void>.delayed(Duration.zero);

      expect(late, [1], reason: 'a plain broadcast stream would give []');
      source.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(first, [1, 2]);
      expect(late, [1, 2]);
      expect(listens, 1);
      expect(shared.upstreamSubscriptions, 1);

      await sub1.cancel();
      expect(shared.upstreamSubscriptions, 1);
      await sub2.cancel();
      expect(shared.upstreamSubscriptions, 0, reason: 'upstream released');
      await source.close();
    });

    test('errors reach every listener', () async {
      final source = StreamController<int>.broadcast();
      final shared = SharedLatestStream<int>(source.stream);
      final errors = <Object>[];
      final a = shared.stream.listen((_) {}, onError: errors.add);
      final b = shared.stream.listen((_) {}, onError: errors.add);
      source.addError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(errors, ['boom', 'boom']);
      await a.cancel();
      await b.cancel();
      await source.close();
    });
  });

  group('DocFutureCache', () {
    test('one read per document while fresh, a new one when stale', () async {
      final fs = FakeFirestore()..seed('users', 'u1', {'avatarUrl': 'a'});
      var now = DateTime(2026);
      final cache = DocFutureCache(now: () => now);
      final ref = fs.collection('users').doc('u1');

      final f1 = cache.get(ref);
      final f2 = cache.get(fs.collection('users').doc('u1'));
      expect(identical(f1, f2), isTrue);
      await f1;
      for (var i = 0; i < 25; i++) {
        await cache.get(ref); // rows rebuilding / scrolling back into view
      }
      expect(fs.documentsRead, 1, reason: 'was one read per row build');

      now = now.add(const Duration(minutes: 6));
      await cache.get(ref);
      expect(fs.documentsRead, 2);
    });
  });

  group('mapWithConcurrency', () {
    test('never runs more than the limit and keeps input order', () async {
      var running = 0;
      var peak = 0;
      final results = await mapWithConcurrency<int, String>(
        List.generate(10, (i) => i),
        3,
        (item, index) async {
          running++;
          peak = running > peak ? running : peak;
          await Future<void>.delayed(Duration(milliseconds: 20 - item));
          running--;
          return 'r$item';
        },
      );
      expect(peak, 3);
      expect(results, [for (var i = 0; i < 10; i++) 'r$i']);
    });

    test('three at a time finishes ~3x sooner than one at a time', () async {
      Future<int> slow(int i, int _) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return i;
      }

      final sw = Stopwatch()..start();
      await mapWithConcurrency(List.generate(9, (i) => i), 1, slow);
      final serial = sw.elapsedMilliseconds;
      sw.reset();
      await mapWithConcurrency(List.generate(9, (i) => i), 3, slow);
      final pooled = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('9 uploads x 30 ms: serial $serial ms, pool of 3 $pooled ms');
      expect(pooled, lessThan(serial));
    });
  });

  group('image decode sizing', () {
    test('decode size is display size x pixel ratio, capped', () {
      expect(decodeSizeFor(40, 3), 120);
      expect(decodeSizeFor(36, 2.625), 95);
      expect(decodeSizeFor(5000, 3), kMaxDecodeDimension);
      expect(decodeSizeFor(double.infinity, 3), kMaxDecodeDimension);
      expect(decodeSizeFor(0, 3), kMaxDecodeDimension);
    });

    testWidgets('context.decodeWidth uses screen width for full-width images',
        (tester) async {
      late int avatar;
      late int fullWidth;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(400, 800), devicePixelRatio: 3),
        child: Builder(builder: (context) {
          avatar = context.decodeWidth(40);
          fullWidth = context.decodeWidth();
          return const SizedBox();
        }),
      ));
      expect(avatar, 120);
      expect(fullWidth, 1200);
    });

    test('a 12 MP photo shown as a 40 px avatar decodes ~3,000x fewer pixels',
        () {
      const fullPixels = 4000 * 3000;
      final w = decodeSizeFor(40, 3);
      final h = (w * 3000 / 4000).round();
      expect(fullPixels / (w * h), greaterThan(1000));
    });
  });
}
