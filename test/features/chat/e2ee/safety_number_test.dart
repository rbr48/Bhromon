import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/safety_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final blockA = Uint8List.fromList(List<int>.generate(64, (i) => i));
  final blockB = Uint8List.fromList(List<int>.generate(64, (i) => 64 + i));
  final zeros = Uint8List(64);
  final ones = Uint8List.fromList(List<int>.filled(64, 0xff));

  // The expected values come from an independent computation of the same
  // definition (SHA-512 over the domain and the two blocks in byte order), not
  // from this code.
  test('matches the independent vector for the first pair', () {
    expect(
      SafetyNumber.compute(blockA, blockB),
      '398014071101536995961497238038074340831344547551831206230131',
    );
  });

  test('matches the independent vector for the second pair', () {
    expect(
      SafetyNumber.compute(zeros, ones),
      '248045194181218434356831544560635310318228057820260084493143',
    );
  });

  test('is the same whichever side computes it', () {
    expect(SafetyNumber.compute(blockB, blockA),
        SafetyNumber.compute(blockA, blockB));
    expect(
        SafetyNumber.compute(ones, zeros), SafetyNumber.compute(zeros, ones));
  });

  test('is 60 digits', () {
    expect(SafetyNumber.compute(blockA, blockB), matches(RegExp(r'^\d{60}$')));
  });

  test('changes when one identity key changes', () {
    final changed = Uint8List.fromList(blockB)..[0] ^= 1;
    expect(
      SafetyNumber.compute(blockA, changed),
      isNot(SafetyNumber.compute(blockA, blockB)),
    );
  });

  test('groups the digits in fives for display', () {
    expect(SafetyNumber.grouped('0123456789'), '01234 56789');
  });

  test('refuses an identity block that is not 64 bytes', () {
    expect(
      () => SafetyNumber.compute(Uint8List(32), blockB),
      throwsArgumentError,
    );
  });
}
