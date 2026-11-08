/// A stored or received E2EE value is malformed, or uses a version this build
/// does not know.
class E2eeFormatException implements Exception {
  const E2eeFormatException(this.message);

  final String message;

  @override
  String toString() => 'E2eeFormatException: $message';
}

/// A check on a peer's keys or on a message failed. Nothing from the message is
/// used after such a failure (E2EE_DESIGN.md, sections 2 and 6).
class E2eeSecurityException implements Exception {
  const E2eeSecurityException(this.message);

  final String message;

  @override
  String toString() => 'E2eeSecurityException: $message';
}
