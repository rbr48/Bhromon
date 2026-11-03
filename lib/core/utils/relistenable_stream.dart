import 'dart:async';

/// A broadcast stream that asks [source] for a fresh stream each time it gains
/// its first listener, and cancels that stream when the last listener leaves.
///
/// Streams built with `map` or `where` can be listened to only once. A cached
/// one would fail when a page showing it is built again, so a cache keeps this
/// wrapper instead.
Stream<T> relistenableStream<T>(Stream<T> Function() source) {
  StreamSubscription<T>? subscription;
  late final StreamController<T> controller;
  controller = StreamController<T>.broadcast(
    onListen: () {
      subscription = source().listen(
        controller.add,
        onError: controller.addError,
        onDone: () => subscription = null,
      );
    },
    onCancel: () {
      final current = subscription;
      subscription = null;
      if (current != null) unawaited(current.cancel());
    },
  );
  return controller.stream;
}
