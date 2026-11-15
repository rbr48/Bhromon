// When the messages listener of a one-to-one chat is opened again after it failed. Firestore
// closes a listener that errors, so without a retry the chat stops updating until it is left
// and opened again. Pure Dart, so the timing is tested without Firestore.

/// The longest wait between two tries.
const Duration kChatStreamRetryCap = Duration(seconds: 30);

/// The wait before try number [attempt] (0 for the first retry): 1, 2, 4, 8 and 16 seconds, and
/// then [kChatStreamRetryCap] for every later one.
Duration chatStreamRetryDelay(int attempt) {
  if (attempt < 0) return const Duration(seconds: 1);
  if (attempt >= 5) return kChatStreamRetryCap;
  return Duration(seconds: 1 << attempt);
}

/// Whether a failed messages listener is opened again. A chat that does not exist yet refuses
/// its messages by the rules, and it is opened once the chat appears, so there is nothing to
/// retry until then.
bool shouldRetryChatStream({
  required bool failed,
  required bool chatExists,
  required bool retryPending,
}) {
  return failed && chatExists && !retryPending;
}
