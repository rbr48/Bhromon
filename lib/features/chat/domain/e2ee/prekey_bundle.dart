import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A one-time or fallback key with its signature by the device's Ed25519 key.
class E2eeSignedKey {
  const E2eeSignedKey({
    required this.keyId,
    required this.key,
    required this.signature,
  });

  /// A short id derived from the key, so the same key always has the same id.
  static String idFor(Uint8List key) {
    return base64Url.encode(sha256.convert(key).bytes).substring(0, 22);
  }

  final String keyId;

  /// The 32-byte Curve25519 public key.
  final Uint8List key;

  /// The 64-byte Ed25519 signature of [E2eePrekeyBundle.signedMessageFor].
  final Uint8List signature;
}

/// The public keys a device publishes so that others can start a session with it
/// (E2EE_DESIGN.md, section 6). The identity key is signed by the device's Ed25519
/// key, and so is every one-time and fallback key. The bundle carries that Ed25519
/// key too, so a verifier needs nothing else.
class E2eePrekeyBundle {
  const E2eePrekeyBundle({
    required this.userId,
    required this.deviceId,
    required this.curve25519Key,
    required this.ed25519Key,
    required this.identitySignature,
    required this.oneTimeKeys,
    this.fallbackKey,
  });

  final String userId;
  final String deviceId;

  /// The 32-byte Curve25519 identity key.
  final Uint8List curve25519Key;

  /// The 32-byte Ed25519 signing key.
  final Uint8List ed25519Key;

  /// The 64-byte Ed25519 signature of [identityMessageFor] for [curve25519Key].
  /// It binds the identity key to the signing key, so one device's signing key
  /// cannot be paired with another device's identity key.
  final Uint8List identitySignature;

  final List<E2eeSignedKey> oneTimeKeys;
  final E2eeSignedKey? fallbackKey;

  /// The bytes a signature covers for a one-time or fallback [key]: the JSON object
  /// `{"key":"<base64>"}` with no spaces. Signer and verifier build the same bytes.
  static Uint8List signedMessageFor(Uint8List key) {
    return _json({'key': base64.encode(key)});
  }

  /// The bytes the identity signature covers: the JSON object
  /// `{"identity":"<base64>"}`. Its field name differs from [signedMessageFor], so a
  /// signature over one kind of key cannot be presented as the other.
  static Uint8List identityMessageFor(Uint8List curve25519Key) {
    return _json({'identity': base64.encode(curve25519Key)});
  }

  /// The identity block the safety number is computed from: the Curve25519 key,
  /// then the Ed25519 key.
  Uint8List get identityBlock =>
      Uint8List.fromList([...curve25519Key, ...ed25519Key]);
}

Uint8List _json(Map<String, String> fields) {
  return Uint8List.fromList(utf8.encode(jsonEncode(fields)));
}
