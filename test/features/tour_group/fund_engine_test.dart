import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';

const _members = [
  LedgerMemberInput(id: 'a@x.com', name: 'Asha', familyCount: 3),
  LedgerMemberInput(id: 'b@x.com', name: 'Babu'),
  LedgerMemberInput(id: 'c@x.com', name: 'Chitra'),
];

ExpenseItem _exp(
  String id,
  int taka, {
  String? paidBy,
  SplitMode mode = SplitMode.family,
  Map<String, int>? shares,
  List<String>? participants,
  String category = 'Food',
  DateTime? date,
  String? stopId,
}) =>
    ExpenseItem(
      id: id,
      tourId: 't',
      title: id,
      amountPaisa: taka * 100,
      paidById: paidBy,
      paidByName: paidBy,
      category: category,
      date: date ?? DateTime(2026, 12, 20),
      splitMode: mode,
      splitShares: shares,
      participantIds: participants,
      stopId: stopId,
    );

LedgerMemberRow _row(LedgerSummary s, String id) =>
    s.rows.singleWhere((r) => r.id == id);

void main() {
  group('split modes', () {
    test('by family is the default: a family of three pays three parts', () {
      final s = TripLedgerEngine.computeLedger(
          members: _members, expenses: [_exp('dinner', 500)]);
      expect(_row(s, 'a@x.com').sharePaisa, 30000);
      expect(_row(s, 'b@x.com').sharePaisa, 10000);
    });

    test('equal gives every member one part', () {
      final s = TripLedgerEngine.computeLedger(
          members: _members,
          expenses: [_exp('boat', 300, mode: SplitMode.equal)]);
      for (final r in s.rows) {
        expect(r.sharePaisa, 10000, reason: r.name);
      }
    });

    test('exact amounts are charged as given, only to those named', () {
      final s = TripLedgerEngine.computeLedger(members: _members, expenses: [
        _exp('tickets', 1000,
            mode: SplitMode.exact,
            shares: {'a@x.com': 70000, 'b@x.com': 30000}),
      ]);
      expect(_row(s, 'a@x.com').sharePaisa, 70000);
      expect(_row(s, 'b@x.com').sharePaisa, 30000);
      expect(_row(s, 'c@x.com').sharePaisa, 0);
    });

    test('custom shares divide by parts, to the paisa', () {
      final s = TripLedgerEngine.computeLedger(members: _members, expenses: [
        _exp('hotel', 1000,
            mode: SplitMode.shares, shares: {'a@x.com': 2, 'c@x.com': 1}),
      ]);
      expect(_row(s, 'a@x.com').sharePaisa, 66667);
      expect(_row(s, 'c@x.com').sharePaisa, 33333);
      expect(s.rows.fold<int>(0, (n, r) => n + r.sharePaisa), 100000);
    });

    test(
        "someone who left loses their exact amount to the rest, so books balance",
        () {
      final s = TripLedgerEngine.computeLedger(members: _members, expenses: [
        _exp('jeep', 900,
            mode: SplitMode.exact,
            shares: {'a@x.com': 30000, 'gone@x.com': 30000, 'b@x.com': 30000}),
      ]);
      expect(
          _row(s, 'a@x.com').sharePaisa + _row(s, 'b@x.com').sharePaisa, 90000);
    });
  });

  group('settling up', () {
    test('marking every suggested payment as paid clears every balance', () {
      final expenses = [
        _exp('hotel', 6000, paidBy: 'a@x.com'),
        _exp('bus', 2500, paidBy: 'b@x.com'),
        _exp('lunch', 900),
      ];
      final deposits = [
        DepositItem(
            id: 'd1',
            tourId: 't',
            memberId: 'c@x.com',
            memberName: 'Chitra',
            amountPaisa: 200000,
            date: DateTime(2026, 12, 1)),
      ];
      final before = TripLedgerEngine.computeLedger(
          members: _members, expenses: expenses, deposits: deposits);
      expect(before.settlements, isNotEmpty);

      final transfers = [
        for (final (i, st) in before.settlements.indexed)
          TransferItem(
            id: 't$i',
            tourId: 't',
            fromId: st.fromId,
            fromName: st.from,
            toId: st.toId,
            toName: st.to,
            amountPaisa: st.amountPaisa,
            date: DateTime(2026, 12, 27),
          ),
      ];
      final after = TripLedgerEngine.computeLedger(
          members: _members,
          expenses: expenses,
          deposits: deposits,
          transfers: transfers);
      for (final r in after.rows) {
        expect(r.netPaisa, 0, reason: r.name);
      }
      expect(after.fundBalancePaisa, 0);
      expect(after.settlements, isEmpty);
    });

    test('a refund from the fund lowers the fund and the member', () {
      final s = TripLedgerEngine.computeLedger(
        members: _members,
        expenses: const [],
        deposits: [
          DepositItem(
              id: 'd',
              tourId: 't',
              memberId: 'b@x.com',
              memberName: 'Babu',
              amountPaisa: 50000,
              date: DateTime(2026)),
        ],
        transfers: [
          TransferItem(
              id: 'r',
              tourId: 't',
              fromName: TripLedgerEngine.fundLabel,
              toId: 'b@x.com',
              toName: 'Babu',
              amountPaisa: 20000,
              date: DateTime(2026)),
        ],
      );
      expect(s.fundBalancePaisa, 30000);
      expect(_row(s, 'b@x.com').netPaisa, 30000);
      expect(_row(s, 'b@x.com').transfersInPaisa, 20000);
    });
  });

  group('fund report', () {
    final tour = TourGroup(
      id: 't',
      name: 'Trip',
      ownerEmail: 'a@x.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 12, 20),
      endDate: DateTime(2026, 12, 25),
      createdAt: DateTime(2026),
      stops: [
        TourStop(
            id: 'cox',
            name: "Cox's Bazar",
            arrive: DateTime(2026, 12, 20),
            leave: DateTime(2026, 12, 22)),
        TourStop(
            id: 'ban',
            name: 'Bandarban',
            arrive: DateTime(2026, 12, 23),
            leave: DateTime(2026, 12, 25)),
      ],
      fundBudget: const FundBudget(
        categoryPaisa: {'Food': 100000, 'Hotel': 300000},
        perHeadTargetPaisa: 50000,
      ),
    );

    test('budget lines, burn rate and projection', () {
      final r = FundReport.build(
        group: tour,
        members: _members,
        expenses: [
          _exp('d1', 800, date: DateTime(2026, 12, 20)),
          _exp('d2', 400, date: DateTime(2026, 12, 21)),
          _exp('h', 2000, category: 'Hotel', date: DateTime(2026, 12, 21)),
          _exp('jeep', 300,
              category: 'Transport', date: DateTime(2026, 12, 23)),
        ],
        now: DateTime(2026, 12, 21, 20),
      );
      final food = r.lines.singleWhere((l) => l.category == 'Food');
      expect(food.isOver, isTrue);
      expect(food.leftPaisa, -20000);
      expect(r.lines.first.budgetPaisa, greaterThan(0));
      expect(r.lines.last.category, 'Transport');
      expect(r.budgetPaisa, 400000);
      expect(r.spentPaisa, 350000);
      expect(r.daysElapsed, 2);
      expect(r.perDayPaisa, 175000);
      expect(r.projectedPaisa, 175000 * 6);
      expect(r.byDay.map((d) => d.day.day), [20, 21, 23]);
      // Spending is put at the stop for its day.
      expect(r.byStop['cox'], 320000);
      expect(r.byStop['ban'], 30000);
      expect(r.topExpenses.first.id, 'h');
    });

    test('the collection asks each family for its size, and counts payments in',
        () {
      final r = FundReport.build(
        group: tour,
        members: _members,
        expenses: const [],
        deposits: [
          DepositItem(
              id: 'd',
              tourId: 't',
              memberId: 'a@x.com',
              memberName: 'Asha',
              amountPaisa: 100000,
              date: DateTime(2026)),
        ],
        transfers: [
          TransferItem(
              id: 'p',
              tourId: 't',
              fromId: 'b@x.com',
              fromName: 'Babu',
              toName: 'Fund',
              amountPaisa: 50000,
              date: DateTime(2026)),
        ],
        now: DateTime(2026, 12, 1),
      );
      final asha = r.collection.singleWhere((c) => c.id == 'a@x.com');
      expect(asha.targetPaisa, 150000);
      expect(asha.duePaisa, 50000);
      expect(r.collection.singleWhere((c) => c.id == 'b@x.com').isPaid, isTrue);
      expect(r.collectionTargetPaisa, 250000);
      expect(r.collectionDuePaisa, 100000);
      // Before the tour starts nothing is projected.
      expect(r.daysElapsed, 0);
      expect(r.projectedPaisa, 0);
    });

    test('a foreign amount converts at the rate given', () {
      // ₹1,250.50 at ৳1.43 a rupee.
      expect(convertToPaisa(125050, 1.43), 178822);
      expect(convertToPaisa(100, 0), isNull);
    });

    test('an expense keeps its split, stop and currency through a save', () {
      final e = ExpenseItem.fromMap(
          'e',
          _exp('x', 10,
                  mode: SplitMode.exact,
                  shares: {'A@x.com': 1000},
                  stopId: 'cox')
              .toMap()
            ..addAll(
                {'currency': 'INR', 'originalMinor': 700, 'fxRate': 1.43}));
      expect(e.splitMode, SplitMode.exact);
      expect(e.splitShares, {'a@x.com': 1000});
      expect(e.stopId, 'cox');
      expect(e.isForeign, isTrue);
      expect(e.fxRate, 1.43);
      final old =
          ExpenseItem.fromMap('o', {'title': 'Tea', 'amountPaisa': 100});
      expect(old.splitMode, SplitMode.family);
      expect(old.isForeign, isFalse);
    });
  });
}
