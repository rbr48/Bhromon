import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('samity settings', () {
    test('an empty samity is not set up and stores nothing', () {
      const config = SamityConfig();

      expect(config.isSetUp, isFalse);
      expect(config.hasSettings, isFalse);
      expect(config.cycleCount, 0);
      expect(config.potTaka, 0);
    });

    test('the pot is each contribution times the members in the rotation', () {
      const config = SamityConfig(
        contributionTaka: 1000,
        startMonth: '2026-01',
        dueDay: 5,
        payoutOrder: ['a@x.com', 'b@x.com', 'c@x.com'],
      );

      expect(config.isSetUp, isTrue);
      expect(config.cycleCount, 3);
      expect(config.potTaka, 3000);
      expect(config.firstMonth, DateTime(2026, 1));
    });

    test('a month is stored as yyyy-MM, and anything else names no month', () {
      expect(parseSamityMonth('2026-11'), DateTime(2026, 11));
      expect(parseSamityMonth('2026-13'), isNull);
      expect(parseSamityMonth('2026-1'), isNull);
      expect(parseSamityMonth('November'), isNull);
      expect(parseSamityMonth(null), isNull);
      expect(samityMonthKey(DateTime(2027, 3, 15)), '2027-03');
    });

    test(
        'a stored samity reads back, with emails lower-cased and blanks dropped',
        () {
      final group = TourGroup.fromMap('s1', {
        'name': 'Mohalla samity',
        'ownerEmail': 'boss@example.com',
        'inviteCode': 'ABCDEFGH',
        'kind': 'family',
        'preset': 'samity',
        'samity': {
          'contributionTaka': 500,
          'startMonth': '2026-02',
          'dueDay': 10,
          'payoutOrder': [' Rahim@Example.com ', '', 'karim@example.com'],
        },
      });

      expect(group.isSamity, isTrue);
      expect(group.samity.contributionTaka, 500);
      expect(group.samity.startMonth, '2026-02');
      expect(group.samity.dueDay, 10);
      expect(
          group.samity.payoutOrder, ['rahim@example.com', 'karim@example.com']);
    });

    test('damaged values fall back to their defaults', () {
      final config = SamityConfig.fromMap({
        'contributionTaka': kSamityMaxContributionTaka + 5,
        'startMonth': 'soon',
        'dueDay': 31,
        'payoutOrder': 'not a list',
      });

      expect(config.contributionTaka, kSamityMaxContributionTaka);
      expect(config.startMonth, isNull);
      expect(config.dueDay, 1);
      expect(config.payoutOrder, isEmpty);
    });

    test('a negative or text amount reads as not set', () {
      expect(
          SamityConfig.fromMap({'contributionTaka': -5}).contributionTaka, 0);
      expect(SamityConfig.fromMap({'contributionTaka': '500'}).contributionTaka,
          0);
      expect(SamityConfig.fromMap(null).isSetUp, isFalse);
    });

    test('the map written to the tour reads back to the same settings', () {
      const config = SamityConfig(
        contributionTaka: 750,
        startMonth: '2026-06',
        dueDay: 28,
        payoutOrder: ['a@x.com', 'b@x.com'],
      );
      final back = SamityConfig.fromMap(config.toMap());

      expect(back.contributionTaka, 750);
      expect(back.startMonth, '2026-06');
      expect(back.dueDay, 28);
      expect(back.payoutOrder, ['a@x.com', 'b@x.com']);
    });

    test('a payment is keyed by its cycle and member, and read back', () {
      const payment =
          SamityPayment(cycle: 3, email: 'a@x.com', amountTaka: 500);

      expect(SamityPayment.paymentId(3, 'a@x.com'), '003__a@x.com');
      expect(payment.id, '003__a@x.com');
      expect(payment.toFields('a@x.com'), {
        'cycleKey': '003',
        'email': 'a@x.com',
        'amountTaka': 500,
        'recordedByEmail': 'a@x.com',
      });

      final back = SamityPayment.fromMap({
        'cycleKey': '003',
        'email': 'a@x.com',
        'amountTaka': 500,
        'recordedByEmail': 'boss@x.com',
      });
      expect(back?.cycle, 3);
      expect(back?.recordedByEmail, 'boss@x.com');
    });

    test('a damaged payment is skipped', () {
      expect(
        SamityPayment.fromMap(
            {'cycleKey': '3', 'email': 'a@x.com', 'amountTaka': 500}),
        isNull,
      );
      expect(
        SamityPayment.fromMap(
            {'cycleKey': '003', 'email': 'a@x.com', 'amountTaka': 0}),
        isNull,
      );
      expect(
        SamityPayment.fromMap(
            {'cycleKey': '003', 'email': '', 'amountTaka': 5}),
        isNull,
      );
    });

    test('a payout is keyed by its cycle, and a damaged one is skipped', () {
      const payout = SamityPayout(
        cycle: 0,
        recipientEmail: 'a@x.com',
        amountTaka: 3000,
        recordedByEmail: 'boss@x.com',
      );

      expect(payout.cycleKey, '000');
      expect(payout.toFields('boss@x.com'), {
        'cycleKey': '000',
        'recipientEmail': 'a@x.com',
        'amountTaka': 3000,
        'recordedByEmail': 'boss@x.com',
      });

      final back = SamityPayout.fromMap({
        'cycleKey': '000',
        'recipientEmail': 'a@x.com',
        'amountTaka': 3000,
      });
      expect(back?.cycle, 0);
      expect(back?.recordedByEmail, '');
      expect(
        SamityPayout.fromMap({
          'cycleKey': '000',
          'recipientEmail': 'a@x.com',
          'amountTaka': 0,
        }),
        isNull,
      );
    });
  });
}
