import 'package:bhromon/features/tour_group/domain/services/emergency_numbers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeEmergencyPhone', () {
    test('drops spaces, dashes and brackets, and keeps the digits', () {
      expect(normalizeEmergencyPhone('0171 234-5678'), '01712345678');
      expect(normalizeEmergencyPhone('(017) 1234 5678'), '01712345678');
    });

    test('keeps a leading plus sign for an international number', () {
      expect(normalizeEmergencyPhone('+880 1712-345678'), '+8801712345678');
    });

    test('reads Bengali digits as ASCII digits', () {
      // ০১৭১২৩৪৫৬৭৮ written with Bengali digit code points.
      const bengali = '০১৭১২৩৪৫৬৭৮';
      expect(normalizeEmergencyPhone(bengali), '01712345678');
    });

    test('refuses text, too few digits, too many digits, and a bare plus', () {
      expect(normalizeEmergencyPhone('call me 0171'), isNull);
      expect(normalizeEmergencyPhone('abc'), isNull);
      expect(normalizeEmergencyPhone('12345'), isNull);
      expect(normalizeEmergencyPhone('1234567890123456'), isNull);
      expect(normalizeEmergencyPhone('+'), isNull);
      expect(normalizeEmergencyPhone(''), isNull);
    });
  });

  group('emergencySmsUri', () {
    test('lists every number and encodes the message', () {
      final uri =
          emergencySmsUri(['+8801712345678', '01812345678'], 'I need help');
      expect(uri.scheme, 'sms');
      expect(uri.toString(),
          'sms:+8801712345678,01812345678?body=I%20need%20help');
    });
  });

  group('parseEmergencyContacts', () {
    test('keeps valid numbers, names them, and skips the rest', () {
      final contacts = parseEmergencyContacts([
        {'name': 'Abba', 'phone': '01712 345678'},
        {'name': 'Broken', 'phone': 'not a number'},
        'not a map',
        {'phone': '+8801812345678'},
      ]);
      expect(contacts.map((c) => c.phone), ['01712345678', '+8801812345678']);
      expect(contacts.first.name, 'Abba');
      expect(contacts.last.name, '+8801812345678',
          reason: 'no name falls back to the number');
    });

    test('keeps at most the limit, and tolerates a missing list', () {
      final many = [
        for (var i = 0; i < 15; i++) {'name': 'N$i', 'phone': '017100000$i'},
      ];
      expect(parseEmergencyContacts(many), hasLength(kMaxEmergencyContacts));
      expect(parseEmergencyContacts(null), isEmpty);
      expect(parseEmergencyContacts('x'), isEmpty);
    });
  });
}
