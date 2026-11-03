import 'dart:async';

import 'package:bhromon/core/utils/shared_stream_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, StreamController<int>> sources;
  late Map<String, int> opened;
  late SharedStreamRegistry<String, int> registry;

  setUp(() {
    sources = {};
    opened = {};
    registry = SharedStreamRegistry<String, int>();
  });

  tearDown(() async {
    for (final source in sources.values) {
      await source.close();
    }
  });

  Stream<int> open(String key) {
    opened[key] = (opened[key] ?? 0) + 1;
    return sources
        .putIfAbsent(key, () => StreamController<int>.broadcast())
        .stream;
  }

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('one key opens one upstream however many listeners it has', () async {
    final a = registry.stream('tour-a', () => open('tour-a')).listen((_) {});
    final b = registry.stream('tour-a', () => open('tour-a')).listen((_) {});
    await tick();
    expect(opened['tour-a'], 1);
    expect(registry.liveUpstreams, 1);
    expect(registry.keyCount, 1);
    await a.cancel();
    await b.cancel();
  });

  test('each key has its own upstream', () async {
    final a = registry.stream('tour-a', () => open('tour-a')).listen((_) {});
    final b = registry.stream('tour-b', () => open('tour-b')).listen((_) {});
    await tick();
    expect(registry.liveUpstreams, 2);
    expect(registry.keyCount, 2);
    await a.cancel();
    await b.cancel();
  });

  test('remove ends a key and the next listen opens it again', () async {
    final first =
        registry.stream('tour-a', () => open('tour-a')).listen((_) {});
    await tick();
    await registry.remove('tour-a');
    await first.cancel();
    expect(registry.keyCount, 0);
    expect(registry.liveUpstreams, 0);

    final second =
        registry.stream('tour-a', () => open('tour-a')).listen((_) {});
    await tick();
    expect(opened['tour-a'], 2);
    await second.cancel();
  });

  test('clear ends every key', () async {
    final a = registry.stream('tour-a', () => open('tour-a')).listen((_) {});
    final b = registry.stream('tour-b', () => open('tour-b')).listen((_) {});
    await tick();
    await registry.clear();
    expect(registry.keyCount, 0);
    expect(registry.liveUpstreams, 0);
    await a.cancel();
    await b.cancel();
  });
}
