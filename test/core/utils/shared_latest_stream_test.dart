import 'dart:async';

import 'package:bhromon/core/utils/shared_latest_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<int> source;
  late int upstreamListens;

  setUp(() {
    upstreamListens = 0;
    source = StreamController<int>.broadcast(
      onListen: () => upstreamListens++,
      onCancel: () => upstreamListens--,
    );
  });

  tearDown(() async {
    await source.close();
  });

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('listeners share one upstream subscription', () async {
    final shared = SharedLatestStream<int>(source.stream);
    final subscriptions = [
      for (var i = 0; i < 4; i++) shared.stream.listen((_) {}),
    ];
    await tick();
    expect(upstreamListens, 1);
    expect(shared.upstreamSubscriptions, 1);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });

  test('a listener that joins later gets the latest value at once', () async {
    final shared = SharedLatestStream<int>(source.stream);
    final first = shared.stream.listen((_) {});
    source.add(7);
    await tick();
    final seen = <int>[];
    final late = shared.stream.listen(seen.add);
    await tick();
    expect(seen, [7]);
    await first.cancel();
    await late.cancel();
  });

  test(
      'the upstream is released with the last listener and starts again on the next',
      () async {
    final shared = SharedLatestStream<int>(source.stream);
    final first = shared.stream.listen((_) {});
    await first.cancel();
    await tick();
    expect(upstreamListens, 0);
    expect(shared.upstreamSubscriptions, 0);

    final second = shared.stream.listen((_) {});
    await tick();
    expect(upstreamListens, 1);
    await second.cancel();
  });

  test('an error reaches every listener', () async {
    final shared = SharedLatestStream<int>(source.stream);
    final errors = <Object>[];
    final a =
        shared.stream.listen((_) {}, onError: (Object e) => errors.add(e));
    final b =
        shared.stream.listen((_) {}, onError: (Object e) => errors.add(e));
    source.addError(StateError('boom'));
    await tick();
    expect(errors, hasLength(2));
    await a.cancel();
    await b.cancel();
  });

  test(
      'close ends the listeners, drops the value, and a new listen starts fresh',
      () async {
    final shared = SharedLatestStream<int>(source.stream);
    var done = false;
    final first = shared.stream.listen((_) {}, onDone: () => done = true);
    source.add(3);
    await tick();

    await shared.close();
    await tick();
    expect(done, isTrue);
    expect(shared.upstreamSubscriptions, 0);
    expect(upstreamListens, 0);

    final seen = <int>[];
    final second = shared.stream.listen(seen.add);
    await tick();
    expect(seen, isEmpty, reason: 'the old value must not replay after close');
    expect(upstreamListens, 1);
    await first.cancel();
    await second.cancel();
  });
}
