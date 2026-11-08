import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BurnRateAlert tests', () {
    final now = DateTime(2026, 11, 10);
    final group = TourGroup(
      id: 'tour_test',
      name: 'Sylhet Tour',
      destination: 'Sylhet',
      ownerEmail: 'a@b.com',
      inviteCode: 'ABCDEF12',
      startDate: DateTime(2026, 11, 8),
      endDate: DateTime(2026, 11, 12),
      createdAt: DateTime(2026, 11, 1),
      fundBudget: const FundBudget(
        categoryPaisa: {
          'Food': 500000, // Tk 5,000
          'Transport': 300000, // Tk 3,000
          'Hotel': 200000, // Tk 2,000 -> Total = 10,00000 (Tk 10,000)
        },
      ),
    );

    const members = [
      LedgerMemberInput(id: 'a@b.com', name: 'Alice'),
      LedgerMemberInput(id: 'b@c.com', name: 'Bob'),
    ];

    test(
        'FundReport returns normal alert when spent < 80% and projection <= budget',
        () {
      final expenses = <ExpenseItem>[
        ExpenseItem(
          id: '1',
          tourId: 'tour_test',
          title: 'Lunch',
          amountPaisa: 300000, // Tk 3,000 (30%)
          category: 'Food',
          paidById: 'a@b.com',
          date: DateTime(2026, 11, 9),
        ),
      ];

      final report = FundReport.build(
        group: group,
        members: members,
        expenses: expenses,
        now: now,
      );

      expect(report.alertLevel, equals(BurnRateAlert.normal));
      expect(report.lines.firstWhere((l) => l.category == 'Food').alertLevel,
          equals(BurnRateAlert.normal));
    });

    test(
        'BudgetLine and FundReport return caution when spent >= 80% and < 100%',
        () {
      final expenses = <ExpenseItem>[
        ExpenseItem(
          id: '1',
          tourId: 'tour_test',
          title: 'Food expense',
          amountPaisa: 420000, // Tk 4,200 out of Tk 5,000 (84%)
          category: 'Food',
          paidById: 'a@b.com',
          date: DateTime(2026, 11, 9),
        ),
        ExpenseItem(
          id: '2',
          tourId: 'tour_test',
          title: 'Transport',
          amountPaisa: 400000, // Tk 4,000 out of 3,000 (133%)
          category: 'Transport',
          paidById: 'b@c.com',
          date: DateTime(2026, 11, 9),
        ),
      ];

      final report = FundReport.build(
        group: group,
        members: members,
        expenses: expenses,
        now: now,
      );

      // Total spent = 820,000 / 1,000,000 = 82% (caution)
      expect(report.alertLevel, equals(BurnRateAlert.caution));
      expect(report.lines.firstWhere((l) => l.category == 'Food').alertLevel,
          equals(BurnRateAlert.caution));
      // Transport spent 400,000 / 300,000 = 133% (critical)
      expect(
          report.lines.firstWhere((l) => l.category == 'Transport').alertLevel,
          equals(BurnRateAlert.critical));
    });

    test('FundReport returns critical when spent >= 100%', () {
      final expenses = <ExpenseItem>[
        ExpenseItem(
          id: '1',
          tourId: 'tour_test',
          title: 'Big Hotel',
          amountPaisa: 1050000, // Tk 10,500
          category: 'Hotel',
          paidById: 'a@b.com',
          date: DateTime(2026, 11, 9),
        ),
      ];

      final report = FundReport.build(
        group: group,
        members: members,
        expenses: expenses,
        now: now,
      );

      expect(report.alertLevel, equals(BurnRateAlert.critical));
      expect(report.isOverBudget, isTrue);
    });

    test(
        'FundReport triggers caution if daily burn projection exceeds total budget',
        () {
      // 5 days total, 2 days elapsed, spent 600,000 (60% spent so far, but projected = 300k * 5 = 1.5M > 1M)
      final expenses = <ExpenseItem>[
        ExpenseItem(
          id: '1',
          tourId: 'tour_test',
          title: 'Early heavy spend',
          amountPaisa: 600000,
          category: 'Food',
          paidById: 'a@b.com',
          date: DateTime(2026, 11, 8),
        ),
      ];

      final report = FundReport.build(
        group: group,
        members: members,
        expenses: expenses,
        now: DateTime(2026, 11, 9), // day 2
      );

      expect(report.spentPaisa, equals(600000));
      expect(report.projectedPaisa, equals(1500000));
      expect(report.alertLevel, equals(BurnRateAlert.caution));
    });
  });
}
