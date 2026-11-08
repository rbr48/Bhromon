import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';
import 'package:bhromon/features/chat/domain/e2ee/prekey_message.dart';
import 'package:flutter_test/flutter_test.dart';

// The parser reads only the one-time key of a pre-key message. The native engine
// checks it against real messages (olm_native_test.dart).

/// One protobuf field of bytes: its tag, its length and its value.
List<int> field(int number, List<int> value) {
  return [(number << 3) | 2, value.length, ...value];
}

Uint8List message(List<int> fields, {int version = 3}) {
  return Uint8List.fromList([version, ...fields]);
}

final List<int> oneTimeKey = List.generate(32, (i) => i + 1);
final List<int> baseKey = List.generate(32, (i) => 100 + i);
final List<int> identityKey = List.generate(32, (i) => 200 + i);

void main() {
  test('reads the one-time key, the first field of the message', () {
    final bytes = message([
      ...field(1, oneTimeKey),
      ...field(2, baseKey),
      ...field(3, identityKey),
      ...field(4, [9, 9, 9]),
    ]);
    expect(oneTimeKeyOfPreKeyMessage(bytes), oneTimeKey);
  });

  test('finds the one-time key when it is not the first field', () {
    final bytes = message([
      ...field(2, baseKey),
      ...field(1, oneTimeKey),
      ...field(3, identityKey),
    ]);
    expect(oneTimeKeyOfPreKeyMessage(bytes), oneTimeKey);
  });

  test('refuses a message that is not a pre-key message', () {
    final bytes = message([...field(1, oneTimeKey)], version: 4);
    expect(
      () => oneTimeKeyOfPreKeyMessage(bytes),
      throwsA(isA<E2eeFormatException>()),
    );
    expect(
      () => oneTimeKeyOfPreKeyMessage(Uint8List(0)),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses a field that is not bytes', () {
    final bytes = Uint8List.fromList([3, (1 << 3) | 0, 5]);
    expect(
      () => oneTimeKeyOfPreKeyMessage(bytes),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses a field that runs past the end of the message', () {
    final bytes = Uint8List.fromList([3, (1 << 3) | 2, 40, 1, 2, 3]);
    expect(
      () => oneTimeKeyOfPreKeyMessage(bytes),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses a one-time key that is not 32 bytes', () {
    final bytes = message([...field(1, List.filled(31, 7))]);
    expect(
      () => oneTimeKeyOfPreKeyMessage(bytes),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses a message with no one-time key', () {
    final bytes = message([...field(2, baseKey), ...field(3, identityKey)]);
    expect(
      () => oneTimeKeyOfPreKeyMessage(bytes),
      throwsA(isA<E2eeFormatException>()),
    );
  });

  test('refuses a length that does not end', () {
    final bytes = Uint8List.fromList([3, (1 << 3) | 2, 0x80]);
    expect(
      () => oneTimeKeyOfPreKeyMessage(bytes),
      throwsA(isA<E2eeFormatException>()),
    );
  });
}
