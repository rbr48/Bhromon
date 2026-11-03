import 'dart:async';

import 'shared_latest_stream.dart';

/// One [SharedLatestStream] held for the session. Its upstream is opened from [_open]
/// on the first listen, and every listener shares it until [reset].
///
/// [reset] ends the upstream and forgets its value. The next listen calls [_open]
/// again and starts from nothing, which is what sign-out and a retry after an
/// error need.
class SessionSharedStream<T> {
  SessionSharedStream(
    this._open, {
    this.onUpstreamStart,
    this.onUpstreamEnd,
  });

  final Stream<T> Function() _open;
  final void Function()? onUpstreamStart;
  final void Function()? onUpstreamEnd;

  SharedLatestStream<T>? _shared;

  /// The shared stream. The same object is returned until [reset].
  Stream<T> get stream {
    final shared = _shared ??= SharedLatestStream<T>(
      _open(),
      onUpstreamStart: onUpstreamStart,
      onUpstreamEnd: onUpstreamEnd,
    );
    return shared.stream;
  }

  /// Live upstream subscriptions (0 or 1). For tests.
  int get upstreamSubscriptions => _shared?.upstreamSubscriptions ?? 0;

  /// Ends the upstream, forgets its value and closes its listeners. A later
  /// [stream] listen opens a new upstream.
  Future<void> reset() async {
    final old = _shared;
    _shared = null;
    await old?.close();
  }
}
