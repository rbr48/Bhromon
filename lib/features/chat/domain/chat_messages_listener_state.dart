/// Tracks the messages listener of a one-to-one chat, and says when it must be
/// opened again.
///
/// The rules refuse a chat's messages while the chat document does not exist,
/// so a listener opened before the first message is refused, and Firestore then
/// closes it for good. The chat document can be watched before it exists, so
/// its listener reports the moment the chat appears. The sender's own first
/// write does the same once the server has confirmed it. Either moment means
/// the messages listener has to be opened again.
///
/// Pure Dart, so the decision can be tested without Firestore.
library;

class ChatMessagesListenerState {
  bool _delivering = false;

  // Whether the chat document existed on the server at the last server snapshot.
  // Null until one arrives, so a chat that already exists is never "new".
  bool? _documentOnServer;

  /// True once the listener has delivered a snapshot and has not failed since.
  bool get isDelivering => _delivering;

  /// A messages listener was opened. It is not delivering until its first snapshot.
  void opened() => _delivering = false;

  /// The messages listener delivered a snapshot.
  void delivered() => _delivering = true;

  /// The messages listener failed. Firestore has closed it.
  void failed() => _delivering = false;

  /// The server confirmed a write to the chat document. Returns true when the
  /// messages listener must be opened again.
  bool documentWriteConfirmed() => !_delivering;

  /// A snapshot of the chat document. A snapshot that only reflects this
  /// device's own unconfirmed write says nothing about the server yet, so it is
  /// ignored. Returns true the first time the document is seen on the server
  /// after it was seen missing, while the messages listener is not delivering.
  bool documentSnapshot({
    required bool exists,
    required bool hasPendingWrites,
  }) {
    if (hasPendingWrites) return false;
    final appeared = exists && _documentOnServer == false;
    _documentOnServer = exists;
    return appeared && !_delivering;
  }
}
