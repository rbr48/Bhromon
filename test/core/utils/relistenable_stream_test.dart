import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/utils/relistenable_stream.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('each first listener starts a fresh source, and leaving cancels it',
      () async {
    final sources = <StreamController<int>>[];
    final stream = relistenableStream<int>(() {
      // A single-subscription source, as a mapped query is.
      final source = StreamController<int>();
      sources.add(source);
      return source.stream;
    });

    final first = <int>[];
    final firstSub = stream.listen(first.add);
    sources.last.add(1);
    await _settle();
    expect(first, [1]);
    expect(sources.last.hasListener, isTrue);

    await firstSub.cancel();
    expect(
      sources.last.hasListener,
      isFalse,
      reason: 'the source is cancelled with the last listener',
    );

    final second = <int>[];
    final secondSub = stream.listen(second.add);
    sources.last.add(2);
    await _settle();
    expect(second, [2]);
    expect(sources, hasLength(2));

    await secondSub.cancel();
    for (final source in sources) {
      await source.close();
    }
  });

  test('two listeners at once share one source', () async {
    var made = 0;
    final source = StreamController<int>();
    final stream = relistenableStream<int>(() {
      made++;
      return source.stream;
    });

    final a = <int>[];
    final b = <int>[];
    final subA = stream.listen(a.add);
    final subB = stream.listen(b.add);
    source.add(7);
    await _settle();

    expect(made, 1);
    expect(a, [7]);
    expect(b, [7]);
    await subA.cancel();
    await subB.cancel();
    await source.close();
  });
}
