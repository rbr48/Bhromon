import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:bhromon/features/tour_group/domain/services/samity_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = 'a@x.com';
const _b = 'b@x.com';
const _c = 'c@x.com';

/// Three members paying 1,000 taka a cycle, the first cycle due on 10 January 2026.
SamityConfig _config({int contribution = 1000}) => SamityConfig(
      contributionTaka: contribution,
      startMonth: '2026-01',
      dueDay: 10,
      payoutOrder: const [_a, _b, _c],
    );

SamityLedger _ledger({
  required DateTime today,
  List<SamityPayment> payments = const [],
  List<SamityPayout> payouts = const [],
  SamityConfig? config,
}) =>
    SamityLedger(
      config: config ?? _config(),
      payments: payments,
      payouts: payouts,
      today: today,
    );

void main() {
  group('samity schedule', () {
    test(
        'one cycle per member, in payout order, due on the due day of each month',
        () {
      final cycles = samitySchedule(_config());

      expect(cycles.map((c) => c.recipientEmail), [_a, _b, _c]);
      expect(cycles.map((c) => c.dueOn), [
        DateTime(2026, 1, 10),
        DateTime(2026, 2, 10),
        DateTime(2026, 3, 10),
      ]);
      expect(cycles.map((c) => c.number), [1, 2, 3]);
      expect(cycles.every((c) => c.potTaka == 3000), isTrue);
      expect(cycles.first.opensOn, DateTime(2026, 1));
    });

    test('a samity that is not set up has no cycles', () {
      expect(samitySchedule(const SamityConfig()), isEmpty);
      expect(
        samitySchedule(
            const SamityConfig(contributionTaka: 100, startMonth: '2026-01')),
        isEmpty,
      );
    });

    test('a schedule runs over the year end', () {
      final cycles = samitySchedule(const SamityConfig(
        contributionTaka: 100,
        startMonth: '2026-11',
        dueDay: 1,
        payoutOrder: [_a, _b, _c],
      ));

      expect(cycles.last.dueOn, DateTime(2027, 1, 1));
    });
  });

  group('cycle status', () {
    test(
        'a cycle is upcoming until its month, due through its due day, then overdue',
        () {
      // Cycle 2 opens on 1 February and is due on the 10th.
      final cycle = samitySchedule(_config())[1];

      expect(_ledger(today: DateTime(2026, 1, 31)).statusOf(cycle),
          SamityCycleStatus.upcoming);
      expect(_ledger(today: DateTime(2026, 2, 1)).statusOf(cycle),
          SamityCycleStatus.due);
      expect(_ledger(today: DateTime(2026, 2, 10)).statusOf(cycle),
          SamityCycleStatus.due);
      expect(_ledger(today: DateTime(2026, 2, 11)).statusOf(cycle),
          SamityCycleStatus.overdue);
    });

    test(
        'a cycle is collected once the pot is paid in, and paid out once handed over',
        () {
      final cycle = samitySchedule(_config())[0];
      final partial = [
        const SamityPayment(cycle: 0, email: _a, amountTaka: 1000),
        const SamityPayment(cycle: 0, email: _b, amountTaka: 500),
      ];
      final full = [
        ...partial,
        const SamityPayment(cycle: 0, email: _c, amountTaka: 1500),
      ];
      const handedOver = SamityPayout(
        cycle: 0,
        recipientEmail: _a,
        amountTaka: 3000,
      );

      expect(
          _ledger(today: DateTime(2026, 1, 20), payments: partial)
              .statusOf(cycle),
          SamityCycleStatus.overdue);
      expect(
          _ledger(today: DateTime(2026, 1, 20), payments: full).statusOf(cycle),
          SamityCycleStatus.collected);
      expect(
        _ledger(
          today: DateTime(2026, 1, 20),
          payments: full,
          payouts: [handedOver],
        ).statusOf(cycle),
        SamityCycleStatus.paidOut,
      );
    });

    test('money collected for a cycle adds everyone who paid into it', () {
      final ledger = _ledger(
        today: DateTime(2026, 1, 20),
        payments: [
          const SamityPayment(cycle: 0, email: _a, amountTaka: 1000),
          const SamityPayment(cycle: 0, email: _b, amountTaka: 500),
          const SamityPayment(cycle: 1, email: _b, amountTaka: 1000),
        ],
      );

      expect(ledger.collectedFor(0), 1500);
      expect(ledger.collectedFor(1), 1000);
      expect(ledger.collectedFor(2), 0);
    });
  });

  group('the current cycle and the next payout', () {
    test(
        'the latest cycle that has opened; the first before any has; the last after all',
        () {
      final config = _config();

      expect(
          _ledger(today: DateTime(2025, 12, 1), config: config)
              .currentCycle
              ?.number,
          1);
      expect(
          _ledger(today: DateTime(2026, 1, 15), config: config)
              .currentCycle
              ?.number,
          1);
      expect(
          _ledger(today: DateTime(2026, 2, 1), config: config)
              .currentCycle
              ?.number,
          2);
      expect(
          _ledger(today: DateTime(2026, 2, 28), config: config)
              .currentCycle
              ?.number,
          2);
      expect(
          _ledger(today: DateTime(2027, 6, 1), config: config)
              .currentCycle
              ?.number,
          3);
      expect(
        _ledger(today: DateTime(2026, 1, 15), config: const SamityConfig())
            .currentCycle,
        isNull,
      );
    });

    test('the next payout is the first cycle whose handover is not recorded',
        () {
      const firstPaid =
          SamityPayout(cycle: 0, recipientEmail: _a, amountTaka: 3000);
      final everyPaid = [
        for (final c in samitySchedule(_config()))
          SamityPayout(
            cycle: c.index,
            recipientEmail: c.recipientEmail,
            amountTaka: 3000,
          ),
      ];

      expect(
        _ledger(today: DateTime(2026, 3, 1), payouts: [firstPaid])
            .nextPayout
            ?.number,
        2,
      );
      expect(
        _ledger(today: DateTime(2026, 3, 1), payouts: everyPaid).nextPayout,
        isNull,
      );
    });
  });

  group('what members owe', () {
    test(
        'a cycle is owed once its due day has passed, short of the contribution',
        () {
      // On 15 February cycles 1 and 2 have fallen due; cycle 3 has not.
      final ledger = _ledger(
        today: DateTime(2026, 2, 15),
        payments: [
          const SamityPayment(cycle: 0, email: _a, amountTaka: 1000),
          const SamityPayment(cycle: 1, email: _a, amountTaka: 400),
        ],
      );

      expect(ledger.owedBy(_a), 600);
      expect(ledger.owedBy(_b), 2000);
      expect(ledger.owedBy(_c), 2000);
    });

    test('a payment for a later cycle does not cover an earlier one', () {
      final ledger = _ledger(
        today: DateTime(2026, 2, 15),
        payments: [const SamityPayment(cycle: 1, email: _b, amountTaka: 1000)],
      );

      expect(ledger.owedBy(_b), 1000);
      expect(ledger.paidAcross(_b), 1000);
    });

    test('standings list every member in the rotation, the most owed first',
        () {
      final ledger = _ledger(
        today: DateTime(2026, 2, 15),
        payments: [const SamityPayment(cycle: 0, email: _a, amountTaka: 1000)],
      );
      final standings = ledger.standings();

      expect(standings.map((s) => s.email), [_b, _c, _a]);
      expect(standings.map((s) => s.owedTaka), [2000, 2000, 1000]);
      expect(standings.firstWhere((s) => s.email == _a).paidTaka, 1000);
      expect(standings.every((s) => !s.isUpToDate), isTrue);
    });

    test('a member with every due cycle paid is up to date', () {
      final ledger = _ledger(
        today: DateTime(2026, 2, 15),
        payments: [
          const SamityPayment(cycle: 0, email: _a, amountTaka: 1000),
          const SamityPayment(cycle: 1, email: _a, amountTaka: 1000),
        ],
      );

      expect(ledger.owedBy(_a), 0);
      expect(
        ledger.standings().firstWhere((s) => s.email == _a).isUpToDate,
        isTrue,
      );
    });

    test('a samity that is not set up owes nothing and lists no one', () {
      final ledger =
          _ledger(today: DateTime(2026, 2, 15), config: const SamityConfig());

      expect(ledger.schedule, isEmpty);
      expect(ledger.standings(), isEmpty);
      expect(ledger.owedBy(_a), 0);
    });
  });
}
