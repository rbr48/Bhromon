import 'package:bhromon/features/tour_group/domain/services/invite_join_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inviteJoinLink', () {
    test('encodes the code in the join link that the join page reads', () {
      expect(
        inviteJoinLink('abcd2345'),
        'https://app.bhromon.fun/#/join?code=ABCD2345',
      );
    });

    test('a link it makes reads back to the same code', () {
      expect(inviteCodeFromScan(inviteJoinLink('ABCD2345')), 'ABCD2345');
    });
  });

  group('inviteCodeFromScan', () {
    test('reads a bare code in any case, with spaces around it', () {
      expect(inviteCodeFromScan('ABCD2345'), 'ABCD2345');
      expect(inviteCodeFromScan('  abcd2345 '), 'ABCD2345');
    });

    test('reads the older six-character codes as well', () {
      expect(inviteCodeFromScan('ABC234'), 'ABC234');
    });

    test('reads a join link in each form the app uses', () {
      expect(
        inviteCodeFromScan('https://app.bhromon.fun/#/join?code=ABCD2345'),
        'ABCD2345',
      );
      expect(
        inviteCodeFromScan(
            'https://app.bhromon.fun/#/join/ABCD2345?name=Trip%20Club'),
        'ABCD2345',
      );
      expect(
        inviteCodeFromScan('https://app.bhromon.fun/join?code=abcd2345'),
        'ABCD2345',
      );
    });

    test('refuses a link on another host, another scheme or another page', () {
      expect(
        inviteCodeFromScan('https://example.com/#/join?code=ABCD2345'),
        isNull,
      );
      expect(
        inviteCodeFromScan('http://app.bhromon.fun/#/join?code=ABCD2345'),
        isNull,
      );
      expect(
        inviteCodeFromScan('https://app.bhromon.fun/#/profile?code=ABCD2345'),
        isNull,
      );
    });

    test('refuses text that is not a group code', () {
      for (final text in [
        '',
        'not a code',
        'ABC',
        '123456789',
        'AB-CD234',
        'https://app.bhromon.fun/#/join?code=',
      ]) {
        expect(inviteCodeFromScan(text), isNull, reason: text);
      }
    });
  });
}
