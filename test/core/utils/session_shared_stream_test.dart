import 'dart:async';

import 'package:bhromon/core/utils/session_shared_stream.dart';
import 'package:bhromon/core/utils/shared_stream_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<StreamController<int>> sources;
  late int opens;

  // Each open makes a fresh source, as the repository's upstream does.
  SessionSharedStream<int> makeShared({
    void Function()? start,
    void Function()? end,
  }) {
    return SessionSharedStream<int>(
      () {
        opens++;
        final controller = StreamController<int>.broadcast();
        sources.add(controller);
        return controller.stream;
      },
      onUpstreamStart: start,
      onUpstreamEnd: end,
    );
  }

  setUp(() {
    sources = <StreamController<int>>[];
    opens = 0;
  });

  tearDown(() async {
    for (final controller in sources) {
      await controller.close();
    }
  });

  group('SessionSharedStream', () {
    test('listeners share one upstream, opened once', () async {
      final shared = makeShared();
      final a = shared.stream.listen((_) {});
      final b = shared.stream.listen((_) {});

      expect(opens, 1);
      expect(shared.upstreamSubscriptions, 1);
      expect(identical(shared.stream, shared.stream), isTrue);

      await a.cancel();
      await b.cancel();
      expect(shared.upstreamSubscriptions, 0);
    });

    test(
        'reset ends the upstream; the next listen opens a new one and sees no old value',
        () async {
      final shared = makeShared();
      final first = <int>[];
      final firstSub = shared.stream.listen(first.add);
      sources.single.add(1);
      await pumpEventQueue();
      expect(first, [1]);

      await shared.reset();
      expect(shared.upstreamSubscriptions, 0);
      await firstSub.cancel();

      final second = <int>[];
      final secondSub = shared.stream.listen(second.add);
      expect(opens, 2, reason: 'the reset makes the next listen open again');
      await pumpEventQueue();
      expect(second, isEmpty,
          reason: 'the value from before the reset is gone');

      sources.last.add(2);
      await pumpEventQueue();
      expect(second, [2]);
      await secondSub.cancel();
    });

    test(
        'the start and end hooks balance across listeners, a reset and a re-listen',
        () async {
      var starts = 0;
      var ends = 0;
      final shared = makeShared(start: () => starts++, end: () => ends++);

      final a = shared.stream.listen((_) {});
      final b = shared.stream.listen((_) {});
      expect((starts, ends), (1, 0));

      await a.cancel();
      expect((starts, ends), (1, 0), reason: 'one listener is still on');

      await b.cancel();
      expect((starts, ends), (1, 1), reason: 'the last listener ended it');

      final c = shared.stream.listen((_) {});
      expect((starts, ends), (2, 1));

      await shared.reset();
      expect((starts, ends), (2, 2));

      await c.cancel();
      await shared.reset();
      expect((starts, ends), (2, 2),
          reason: 'an ended upstream is not ended twice');
    });

    test('an error from the source reaches every listener', () async {
      final shared = makeShared();
      final errors = <Object>[];
      final a = shared.stream.listen((_) {}, onError: errors.add);
      final b = shared.stream.listen((_) {}, onError: errors.add);

      sources.single.addError(StateError('boom'));
      await pumpEventQueue();

      expect(errors, hasLength(2));
      await a.cancel();
      await b.cancel();
    });

    test(
        'when the source finishes, the upstream ends once and the listeners close',
        () async {
      var starts = 0;
      var ends = 0;
      final shared = makeShared(start: () => starts++, end: () => ends++);
      var done = false;
      shared.stream.listen((_) {}, onDone: () => done = true);

      await sources.single.close();
      await pumpEventQueue();

      expect(done, isTrue);
      expect((starts, ends), (1, 1));
      expect(shared.upstreamSubscriptions, 0);
    });
  });

  group('SharedStreamRegistry hooks', () {
    test('start and end run with the key, and remove ends only that key',
        () async {
      final starts = <String>[];
      final ends = <String>[];
      final registry = SharedStreamRegistry<String, int>(
        onUpstreamStart: starts.add,
        onUpstreamEnd: ends.add,
      );
      Stream<int> open() {
        final controller = StreamController<int>.broadcast();
        sources.add(controller);
        return controller.stream;
      }

      final a = registry.stream('t1', open).listen((_) {});
      final b = registry.stream('t1', open).listen((_) {});
      final c = registry.stream('t2', open).listen((_) {});

      expect(starts, ['t1', 't2']);
      expect(ends, isEmpty);
      expect(registry.liveUpstreams, 2);

      await registry.remove('t1');
      expect(ends, ['t1']);
      expect(registry.liveUpstreams, 1);

      await a.cancel();
      await b.cancel();
      await c.cancel();
      expect(ends, ['t1', 't2']);
      expect(registry.liveUpstreams, 0);
    });
  });
}
