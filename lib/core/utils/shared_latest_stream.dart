import 'dart:async';

/// Shares one subscription to [source] between any number of listeners and
/// replays the latest event to each new one.
///
/// Firestore `snapshots()` streams are broadcast but don't replay, so a
/// second StreamBuilder attached to a cached stream would wait for the next
/// change before showing anything. This keeps one upstream listener while
/// anyone is listening, and drops it (and the cached value) when nobody is.
class SharedLatestStream<T> {
  SharedLatestStream(this._source);

  final Stream<T> _source;
  final Set<MultiStreamController<T>> _listeners = {};
  StreamSubscription<T>? _subscription;
  T? _latest;
  bool _hasLatest = false;

  /// Number of live upstream subscriptions (0 or 1). For tests.
  int get upstreamSubscriptions => _subscription == null ? 0 : 1;

  /// Drops the upstream subscription and the cached value, and closes every
  /// listener. A later listen starts a fresh upstream.
  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    _latest = null;
    _hasLatest = false;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      await listener.close();
    }
    await subscription?.cancel();
  }

  late final Stream<T> stream = Stream<T>.multi((controller) {
    if (_hasLatest) controller.add(_latest as T);
    _listeners.add(controller);
    _subscription ??= _source.listen(
      (event) {
        _latest = event;
        _hasLatest = true;
        for (final listener in _listeners.toList()) {
          listener.add(event);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final listener in _listeners.toList()) {
          listener.addError(error, stackTrace);
        }
      },
      onDone: () {
        _subscription = null;
        _latest = null;
        _hasLatest = false;
        for (final listener in _listeners.toList()) {
          listener.close();
        }
      },
    );
    controller.onCancel = () {
      _listeners.remove(controller);
      if (_listeners.isEmpty) {
        _subscription?.cancel();
        _subscription = null;
        _latest = null;
        _hasLatest = false;
      }
    };
  }, isBroadcast: true);
}
