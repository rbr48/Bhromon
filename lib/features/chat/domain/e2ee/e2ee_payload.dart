import 'dart:convert';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';

/// The encrypted content of a message (E2EE_DESIGN.md, section 4). Olm does not
/// bind the identifiers in it, so the receiver checks them against the outer
/// envelope and against the chat where the message is stored. See [checkBinding].
class E2eePayload {
  const E2eePayload({
    required this.chatId,
    required this.senderUid,
    required this.recipientUid,
    required this.messageId,
    required this.sentAtMillis,
    required this.text,
  });

  /// The payload format this build writes and reads.
  static const int version = 1;

  /// The largest text accepted, in UTF-8 bytes.
  static const int maxTextBytes = 8 * 1024;

  static const Set<String> _fields = {
    'v',
    'chat',
    'from',
    'to',
    'msg',
    'sentAt',
    'text',
  };

  final String chatId;
  final String senderUid;
  final String recipientUid;
  final String messageId;
  final int sentAtMillis;
  final String text;

  /// The JSON that is encrypted. It has a fixed field order and no spaces.
  String encode() {
    return jsonEncode({
      'v': version,
      'chat': chatId,
      'from': senderUid,
      'to': recipientUid,
      'msg': messageId,
      'sentAt': sentAtMillis,
      'text': text,
    });
  }

  /// Parses a payload. Throws [E2eeFormatException] on malformed JSON, an
  /// unknown field or version, a bad value, or text over [maxTextBytes].
  factory E2eePayload.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const E2eeFormatException('payload is not JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const E2eeFormatException('payload is not an object');
    }
    for (final field in decoded.keys) {
      if (!_fields.contains(field)) {
        throw E2eeFormatException('unknown payload field "$field"');
      }
    }
    if (decoded['v'] != version) {
      throw const E2eeFormatException('unsupported payload version');
    }
    final sentAt = decoded['sentAt'];
    if (sentAt is! int || sentAt < 0) {
      throw const E2eeFormatException('sentAt must be a non-negative integer');
    }
    final text = _stringField(decoded, 'text');
    if (utf8.encode(text).length > maxTextBytes) {
      throw const E2eeFormatException('payload text is too long');
    }
    return E2eePayload(
      chatId: _stringField(decoded, 'chat'),
      senderUid: _stringField(decoded, 'from'),
      recipientUid: _stringField(decoded, 'to'),
      messageId: _stringField(decoded, 'msg'),
      sentAtMillis: sentAt,
      text: text,
    );
  }

  /// Throws [E2eeSecurityException] unless this payload is for the expected chat,
  /// sender, recipient and message. Call it before showing the text.
  void checkBinding({
    required String expectedChatId,
    required String expectedSenderUid,
    required String expectedRecipientUid,
    required String expectedMessageId,
  }) {
    if (chatId != expectedChatId) {
      throw const E2eeSecurityException('the payload is for another chat');
    }
    if (senderUid != expectedSenderUid) {
      throw const E2eeSecurityException('the payload names another sender');
    }
    if (recipientUid != expectedRecipientUid) {
      throw const E2eeSecurityException('the payload names another recipient');
    }
    if (messageId != expectedMessageId) {
      throw const E2eeSecurityException('the payload is for another message');
    }
  }

  static String _stringField(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String || value.isEmpty) {
      throw E2eeFormatException('"$field" must be a non-empty string');
    }
    return value;
  }
}
