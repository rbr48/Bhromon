import 'dart:async';

/// Joins several streams of lists into one stream of their merged lists.
///
/// The merged list is sent once every source has sent a list, and again each time
/// any source sends a new one. An item that more than one source sends is kept
/// once, identified by [idOf]. An error from a source is passed on, and the
/// sources are cancelled when the merged stream is cancelled.
Stream<List<T>> mergeLatestLists<T>(
  List<Stream<List<T>>> sources, {
  required Object Function(T item) idOf,
}) {
  final listeners = <MultiStreamController<List<T>>>{};
  final latest = List<List<T>?>.filled(sources.length, null);
  final subscriptions = <StreamSubscription<List<T>>>[];
  List<T>? lastMerged;

  void send() {
    if (latest.any((list) => list == null)) return;
    final byId = <Object, T>{};
    for (final list in latest) {
      for (final item in list!) {
        byId[idOf(item)] = item;
      }
    }
    lastMerged = byId.values.toList();
    for (final listener in listeners.toList()) {
      listener.add(lastMerged!);
    }
  }

  void start() {
    for (var i = 0; i < sources.length; i++) {
      subscriptions.add(sources[i].listen(
        (list) {
          latest[i] = list;
          send();
        },
        onError: (Object error, StackTrace stackTrace) {
          for (final listener in listeners.toList()) {
            listener.addError(error, stackTrace);
          }
        },
      ));
    }
  }

  void stop() {
    for (final sub in subscriptions) {
      sub.cancel();
    }
    subscriptions.clear();
    // A restart must not merge or replay what the old subscriptions sent.
    for (var i = 0; i < latest.length; i++) {
      latest[i] = null;
    }
    lastMerged = null;
  }

  return Stream<List<T>>.multi((controller) {
    if (lastMerged != null) {
      controller.add(lastMerged!);
    }
    listeners.add(controller);
    if (subscriptions.isEmpty) {
      start();
    }
    controller.onCancel = () {
      listeners.remove(controller);
      if (listeners.isEmpty) {
        stop();
      }
    };
  }, isBroadcast: true);
}
