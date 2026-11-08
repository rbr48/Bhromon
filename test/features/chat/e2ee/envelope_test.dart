import 'dart:convert';
import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_envelope.dart';
import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> validJson() => {
      'v': 1,
      'alg': 'olm.v1',
      'from': 'device-a',
      'to': 'device-b',
      'type': 1,
      'ct': 'AQID', // base64url of [1, 2, 3]
    };

void main() {
  test('round trips through JSON', () {
    final envelope = E2eeEnvelope(
      senderDeviceId: 'device-a',
      recipientDeviceId: 'device-b',
      messageType: 0,
      ciphertext: Uint8List.fromList([1, 2, 3]),
    );
    final parsed = E2eeEnvelope.fromJson(
      jsonDecode(jsonEncode(envelope.toJson())) as Map<String, dynamic>,
    );
    expect(parsed.senderDeviceId, 'device-a');
    expect(parsed.recipientDeviceId, 'device-b');
    expect(parsed.messageType, 0);
    expect(parsed.ciphertext, orderedEquals([1, 2, 3]));
  });

  test('parses the fixed example', () {
    final envelope = E2eeEnvelope.fromJson(validJson());
    expect(envelope.messageType, 1);
    expect(envelope.ciphertext, orderedEquals([1, 2, 3]));
  });

  test('refuses an unknown version', () {
    final json = validJson()..['v'] = 2;
    expect(
      () => E2eeEnvelope.fromJson(json),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses an unknown algorithm', () {
    final json = validJson()..['alg'] = 'megolm.v1';
    expect(
      () => E2eeEnvelope.fromJson(json),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses an unknown field', () {
    final json = validJson()..['extra'] = true;
    expect(
      () => E2eeEnvelope.fromJson(json),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses a message type other than 0 or 1', () {
    for (final type in <Object>[2, -1, '1']) {
      final json = validJson()..['type'] = type;
      expect(
        () => E2eeEnvelope.fromJson(json),
        throwsA(isA<E2eeFormatException>()),
        reason: 'type $type',
      );
    }
  });

  test('refuses device ids that are not plain identifiers', () {
    for (final id in ['a b', '', 'x' * 65, 'a/b']) {
      final json = validJson()..['from'] = id;
      expect(
        () => E2eeEnvelope.fromJson(json),
        throwsA(isA<E2eeFormatException>()),
        reason: 'device id "$id"',
      );
    }
  });

  test('refuses ciphertext that is empty, not base64url, or too large', () {
    final tooLarge = base64Url.encode(
      List<int>.filled(E2eeEnvelope.maxCiphertextBytes + 1, 0),
    );
    for (final ct in ['', '!!!', tooLarge]) {
      final json = validJson()..['ct'] = ct;
      expect(
        () => E2eeEnvelope.fromJson(json),
        throwsA(isA<E2eeFormatException>()),
        reason: 'ciphertext of length ${ct.length}',
      );
    }
  });
}
