import 'dart:typed_data';

/// The Olm operations the chat code needs (E2EE_DESIGN.md, section 4). The chat
/// logic depends only on this interface, so it can be tested without the native
/// library. The implementation is the native library, in `data/e2ee/`.
abstract interface class OlmEngine {
  /// Creates an account with fresh identity keys.
  OlmAccount createAccount();

  /// Restores an account from a pickle. [key] is 32 bytes.
  OlmAccount restoreAccount(Uint8List pickle, Uint8List key);

  /// Starts a session from the peer's Curve25519 identity key and one of its
  /// one-time keys (or its fallback key).
  OlmSession createOutboundSession({
    required OlmAccount account,
    required Uint8List theirCurve25519Key,
    required Uint8List theirOneTimeKey,
  });

  /// Creates the receiving side from a pre-key message. Also returns the
  /// plaintext of that message.
  OlmInbound createInboundSession({
    required OlmAccount account,
    required Uint8List theirCurve25519Key,
    required Uint8List prekeyMessage,
  });

  /// Restores a session from a pickle. [key] is 32 bytes.
  OlmSession restoreSession(Uint8List pickle, Uint8List key);

  /// Whether [signature] is a valid Ed25519 signature of [message] under
  /// [ed25519Key]. Returns false for a bad signature.
  bool verifySignature({
    required Uint8List ed25519Key,
    required Uint8List message,
    required Uint8List signature,
  });
}

/// One Olm account on this device: its identity keys, one-time keys and signing.
abstract interface class OlmAccount {
  /// The 32-byte Curve25519 identity key.
  Uint8List get curve25519Key;

  /// The 32-byte Ed25519 signing key.
  Uint8List get ed25519Key;

  /// Creates [count] one-time keys, from 1 to 100.
  void generateOneTimeKeys(int count);

  /// The one-time keys not yet published, 32 bytes each.
  List<Uint8List> unpublishedOneTimeKeys();

  /// Marks the unpublished one-time and fallback keys as published.
  void markKeysPublished();

  /// The unpublished fallback key, or null when there is none.
  Uint8List? unpublishedFallbackKey();

  /// Creates a new fallback key.
  void generateFallbackKey();

  /// Signs [message] with the Ed25519 key. Returns 64 bytes.
  Uint8List sign(Uint8List message);

  /// Encrypts the account under [key] (32 bytes), for storage.
  Uint8List pickle(Uint8List key);

  /// Frees the native account. The account must not be used afterwards.
  void dispose();
}

/// One Olm session with a peer device.
abstract interface class OlmSession {
  /// The session id, the same at both ends.
  String get id;

  /// Encrypts [plaintext]. Returns the Olm message type and the message bytes.
  OlmMessage encrypt(Uint8List plaintext);

  /// Decrypts a message of [messageType]. Throws [OlmEngineException] if the
  /// message is altered, replayed or not for this session.
  Uint8List decrypt(int messageType, Uint8List message);

  /// Encrypts the session under [key] (32 bytes), for storage.
  Uint8List pickle(Uint8List key);

  /// Frees the native session. The session must not be used afterwards.
  void dispose();
}

/// An Olm message: type 0 is a pre-key message, type 1 a normal message.
class OlmMessage {
  const OlmMessage({required this.messageType, required this.bytes});

  final int messageType;
  final Uint8List bytes;
}

/// The result of creating an inbound session from a pre-key message.
class OlmInbound {
  const OlmInbound({required this.session, required this.plaintext});

  final OlmSession session;
  final Uint8List plaintext;
}

/// The native library reported a failure. [operation] names the call and [code]
/// is the library's `E2EE_ERR_*` code.
class OlmEngineException implements Exception {
  const OlmEngineException(this.operation, this.code);

  final String operation;
  final int code;

  @override
  String toString() => 'OlmEngineException: $operation failed (code $code)';
}
