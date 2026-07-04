import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/utils/phone_formatter.dart';

void main() {
  group('PhoneFormatter Tests', () {
    test('Format: local number with leading zero', () {
      expect(PhoneFormatter.format('01712345678'), equals('+8801712345678'));
      expect(
          PhoneFormatter.format(' 017-1234 5678 '), equals('+8801712345678'));
    });

    test('Format: local number without leading zero', () {
      expect(PhoneFormatter.format('1712345678'), equals('+8801712345678'));
    });

    test('Format: international number without plus', () {
      expect(PhoneFormatter.format('8801712345678'), equals('+8801712345678'));
    });

    test('Format: international number with plus', () {
      expect(PhoneFormatter.format('+8801712345678'), equals('+8801712345678'));
    });

    test('Format: international number with +88 but missing zero', () {
      expect(PhoneFormatter.format('+881712345678'), equals('+8801712345678'));
    });

    test('Format: international number with 88 but missing zero and plus', () {
      expect(PhoneFormatter.format('881712345678'), equals('+8801712345678'));
    });

    test('Format: other international number remains unchanged', () {
      expect(PhoneFormatter.format('+14155552671'), equals('+14155552671'));
      expect(PhoneFormatter.format('+447911123456'), equals('+447911123456'));
    });

    test('Format: empty input returns empty', () {
      expect(PhoneFormatter.format(''), equals(''));
    });
  });
}
