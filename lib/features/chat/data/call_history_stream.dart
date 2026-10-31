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
  late final StreamController<List<T>> controller;
  final latest = List<List<T>?>.filled(sources.length, null);
  final subscriptions = <StreamSubscription<List<T>>>[];

  void send() {
    if (latest.any((list) => list == null)) return;
    final byId = <Object, T>{};
    for (final list in latest) {
      for (final item in list!) {
        byId[idOf(item)] = item;
      }
    }
    controller.add(byId.values.toList());
  }

  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        subscriptions.add(sources[i].listen(
          (list) {
            latest[i] = list;
            send();
          },
          onError: controller.addError,
        ));
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
