import 'dart:async';

import 'shared_latest_stream.dart';

/// One [SharedLatestStream] per key, such as one per tour.
///
/// Every listener of a key shares one upstream subscription, and each new listener
/// gets the latest value at once. [remove] and [clear] end a key's upstream and
/// forget its cached value, so the next listen starts fresh.
class SharedStreamRegistry<K, T> {
  /// [onUpstreamStart] and [onUpstreamEnd] run with the key when its upstream
  /// opens and when it ends. They are for the debug budget counters.
  SharedStreamRegistry({this.onUpstreamStart, this.onUpstreamEnd});

  final void Function(K key)? onUpstreamStart;
  final void Function(K key)? onUpstreamEnd;

  final Map<K, SharedLatestStream<T>> _byKey = {};

  /// The shared stream for [key]. [open] is called once per key, when the key is new.
  Stream<T> stream(K key, Stream<T> Function() open) {
    return _byKey
        .putIfAbsent(
          key,
          () => SharedLatestStream<T>(
            open(),
            onUpstreamStart: () => onUpstreamStart?.call(key),
            onUpstreamEnd: () => onUpstreamEnd?.call(key),
          ),
        )
        .stream;
  }

  /// Keys that have a stream, whether or not anyone is listening. For tests.
  int get keyCount => _byKey.length;

  /// Live upstream subscriptions across every key (at most one per key). For tests.
  int get liveUpstreams => _byKey.values
      .fold(0, (count, shared) => count + shared.upstreamSubscriptions);

  /// Ends the upstream of [key] and forgets its value.
  Future<void> remove(K key) async {
    final shared = _byKey.remove(key);
    await shared?.close();
  }

  /// Ends every upstream and forgets every value.
  Future<void> clear() async {
    final all = _byKey.values.toList();
    _byKey.clear();
    for (final shared in all) {
      await shared.close();
    }
  }
}
