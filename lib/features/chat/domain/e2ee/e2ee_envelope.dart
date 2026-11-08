import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';

/// The outer wrapper of an end-to-end encrypted message (E2EE_DESIGN.md, sections
/// 4 and 7). It is stored as the `envelope` field of a message in an encrypted
/// chat, in place of the text.
class E2eeEnvelope {
  const E2eeEnvelope({
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.messageType,
    required this.ciphertext,
  });

  /// The envelope format this build writes and reads.
  static const int version = 1;

  /// The algorithm: Olm, session version 1 (decision D10).
  static const String algorithm = 'olm.v1';

  /// The largest ciphertext accepted, in bytes.
  static const int maxCiphertextBytes = 16 * 1024;

  static final RegExp _deviceId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static const Set<String> _fields = {'v', 'alg', 'from', 'to', 'type', 'ct'};

  final String senderDeviceId;
  final String recipientDeviceId;

  /// 0 for a pre-key message, which starts a session; 1 for a normal message.
  final int messageType;

  /// The raw Olm message bytes. They are base64url-encoded in JSON.
  final Uint8List ciphertext;

  Map<String, Object> toJson() => {
        'v': version,
        'alg': algorithm,
        'from': senderDeviceId,
        'to': recipientDeviceId,
        'type': messageType,
        'ct': base64Url.encode(ciphertext),
      };

  /// Parses an envelope. Throws [E2eeFormatException] on any unknown field,
  /// unknown version or algorithm, malformed value, or size out of range.
  factory E2eeEnvelope.fromJson(Map<String, dynamic> json) {
    for (final field in json.keys) {
      if (!_fields.contains(field)) {
        throw E2eeFormatException('unknown envelope field "$field"');
      }
    }
    if (json['v'] != version) {
      throw const E2eeFormatException('unsupported envelope version');
    }
    if (json['alg'] != algorithm) {
      throw const E2eeFormatException('unsupported envelope algorithm');
    }
    final from = _deviceIdField(json, 'from');
    final to = _deviceIdField(json, 'to');
    final type = json['type'];
    if (type is! int || (type != 0 && type != 1)) {
      throw const E2eeFormatException('message type must be 0 or 1');
    }
    final ct = json['ct'];
    if (ct is! String) {
      throw const E2eeFormatException('ciphertext must be a string');
    }
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(ct);
    } on FormatException {
      throw const E2eeFormatException('ciphertext is not base64url');
    }
    if (bytes.isEmpty || bytes.length > maxCiphertextBytes) {
      throw const E2eeFormatException('ciphertext size is out of range');
    }
    return E2eeEnvelope(
      senderDeviceId: from,
      recipientDeviceId: to,
      messageType: type,
      ciphertext: bytes,
    );
  }

  static String _deviceIdField(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String || !_deviceId.hasMatch(value)) {
      throw E2eeFormatException('"$field" is not a device id');
    }
    return value;
  }
}
