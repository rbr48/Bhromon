import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The safety number two people compare to confirm each other's keys
/// (E2EE_DESIGN.md, sections 6 and 12, decision D5). Both sides compute the same
/// 60 digits, whichever side computes them.
class SafetyNumber {
  SafetyNumber._();

  /// The domain separator, so the digest is not reused for another purpose.
  static const String domain = 'bhromon-e2ee-safety-number-v1';

  /// The bytes one device contributes: its 32-byte Curve25519 identity key, then
  /// its 32-byte Ed25519 key.
  static const int identityBlockLength = 64;

  /// The 60-digit number for two identity blocks. The order of the arguments does
  /// not matter.
  static String compute(Uint8List mine, Uint8List theirs) {
    if (mine.length != identityBlockLength ||
        theirs.length != identityBlockLength) {
      throw ArgumentError('an identity block is $identityBlockLength bytes');
    }
    final mineFirst = _compareBytes(mine, theirs) <= 0;
    final first = mineFirst ? mine : theirs;
    final second = mineFirst ? theirs : mine;
    final digest =
        sha512.convert([...utf8.encode(domain), ...first, ...second]).bytes;
    final digits = StringBuffer();
    for (var group = 0; group < 12; group++) {
      var value = 0;
      for (var i = 0; i < 5; i++) {
        value = (value << 8) | digest[group * 5 + i];
      }
      digits.write((value % 100000).toString().padLeft(5, '0'));
    }
    return digits.toString();
  }

  /// The digits in 12 groups of five, for display.
  static String grouped(String digits) {
    final parts = <String>[];
    for (var i = 0; i < digits.length; i += 5) {
      parts.add(digits.substring(i, i + 5));
    }
    return parts.join(' ');
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return a[i] < b[i] ? -1 : 1;
      }
    }
    return 0;
  }
}
