import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';

void main() {
  group('TripLedgerEngine', () {
    test('toPaisa converts BDT to integer paisa correctly', () {
      expect(TripLedgerEngine.toPaisa(100), equals(10000));
      expect(TripLedgerEngine.toPaisa(12.34), equals(1234));
      expect(TripLedgerEngine.toPaisa(0), equals(0));
      expect(TripLedgerEngine.toPaisa(null), equals(0));
    });

    test('allocate splits total paisa with zero lost or created paisa', () {
      // 100 paisa across 3 members with equal weight (1, 1, 1) -> 34, 33, 33
      final parts = TripLedgerEngine.allocate(100, [1, 1, 1]);
      expect(parts.length, equals(3));
      expect(parts.reduce((a, b) => a + b), equals(100));
      expect(parts, equals([34, 33, 33]));
    });

    test('allocate with weighted family count', () {
      // 1000 paisa split between family of 2 and family of 3
      final parts = TripLedgerEngine.allocate(1000, [2, 3]);
      expect(parts.reduce((a, b) => a + b), equals(1000));
      expect(parts, equals([400, 600]));
    });

    test('computeLedger accurately calculates fund balance and settlements', () {
      final members = [
        const LedgerMemberInput(id: 'm1', name: 'Shohag', familyCount: 1, depositPaisa: 500000), // 5000 Tk
        const LedgerMemberInput(id: 'm2', name: 'Tanvir', familyCount: 1, depositPaisa: 500000), // 5000 Tk
        const LedgerMemberInput(id: 'm3', name: 'Nur Bhai', familyCount: 2, depositPaisa: 1000000), // 10000 Tk
      ];

      final expenses = [
        // 8000 Tk paid from fund
        ExpenseItem(
          id: 'e1',
          tourId: 'tour1',
          title: 'Hotel Booking',
          amountPaisa: 800000,
          category: 'Hotel',
          date: DateTime.now(),
        ),
        // 2000 Tk paid directly by Shohag out of pocket
        ExpenseItem(
          id: 'e2',
          tourId: 'tour1',
          title: 'Dinner at Beach',
          amountPaisa: 200000,
          paidById: 'm1',
          paidByName: 'Shohag',
          category: 'Food',
          date: DateTime.now(),
        ),
      ];

      final summary = TripLedgerEngine.computeLedger(members: members, expenses: expenses);

      // Headcount: 1 + 1 + 2 = 4
      expect(summary.headcount, equals(4));
      // Total expense: 8000 + 2000 = 10000 Tk (1,000,000 paisa)
      expect(summary.totalExpensePaisa, equals(1000000));
      // Per head cost: 10000 / 4 = 2500 Tk (250,000 paisa)
      expect(summary.perHeadCostPaisa, equals(250000));
      // Fund paid: 8000 Tk. Total deposit: 20000 Tk. Fund balance: 12000 Tk
      expect(summary.fundBalancePaisa, equals(1200000));

      // Settlements must resolve completely
      expect(summary.settlements, isNotEmpty);
      for (final s in summary.settlements) {
        expect(s.amountPaisa, greaterThan(0));
      }
    });
  });
}
