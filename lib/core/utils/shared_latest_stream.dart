import 'dart:async';

/// Shares one subscription to [source] between any number of listeners and
/// replays the latest event to each new one.
///
/// Firestore `snapshots()` streams are broadcast but don't replay, so a
/// second StreamBuilder attached to a cached stream would wait for the next
/// change before showing anything. This keeps one upstream listener while
/// anyone is listening, and drops it (and the cached value) when nobody is.
class SharedLatestStream<T> {
  /// [onUpstreamStart] runs when the upstream subscription opens and
  /// [onUpstreamEnd] when it ends: no listener is left, [close] was called, or
  /// the source finished. Each runs once per upstream, so they can keep a count
  /// for the debug budget.
  SharedLatestStream(
    this._source, {
    this.onUpstreamStart,
    this.onUpstreamEnd,
  });

  final Stream<T> _source;
  final void Function()? onUpstreamStart;
  final void Function()? onUpstreamEnd;
  final Set<MultiStreamController<T>> _listeners = {};
  StreamSubscription<T>? _subscription;
  T? _latest;
  bool _hasLatest = false;

  /// Number of live upstream subscriptions (0 or 1). For tests.
  int get upstreamSubscriptions => _subscription == null ? 0 : 1;

  /// Drops the upstream subscription and the cached value, and closes every
  /// listener. A later listen starts a fresh upstream.
  Future<void> close() async {
    final subscription = _endUpstream();
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      await listener.close();
    }
    await subscription?.cancel();
  }

  /// Forgets the cached value and ends the upstream. Returns the subscription
  /// that was open, so the caller can cancel it.
  StreamSubscription<T>? _endUpstream() {
    _latest = null;
    _hasLatest = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) onUpstreamEnd?.call();
    return subscription;
  }

  late final Stream<T> stream = Stream<T>.multi((controller) {
    if (_hasLatest) controller.add(_latest as T);
    _listeners.add(controller);
    if (_subscription == null) {
      _subscription = _source.listen(
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
          _endUpstream();
          final listeners = _listeners.toList();
          _listeners.clear();
          for (final listener in listeners) {
            listener.close();
          }
        },
      );
      onUpstreamStart?.call();
    }
    controller.onCancel = () {
      _listeners.remove(controller);
      if (_listeners.isEmpty) {
        _endUpstream()?.cancel();
      }
    };
  }, isBroadcast: true);
}
