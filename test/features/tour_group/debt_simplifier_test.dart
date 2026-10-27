import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/services/debt_simplifier.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_ledger_engine.dart';

void main() {
  group('DebtSimplifier', () {
    test('returns empty transactions when parties are empty or all balanced',
        () {
      expect(DebtSimplifier.simplifyDebts([]), isEmpty);
      expect(
        DebtSimplifier.simplifyDebts([
          (name: 'A', netPaisa: 0, fund: false, id: 'a'),
          (name: 'B', netPaisa: 0, fund: false, id: 'b'),
        ]),
        isEmpty,
      );
    });

    test('throws StateError when net balances do not sum to zero', () {
      expect(
        () => DebtSimplifier.simplifyDebts([
          (name: 'A', netPaisa: -500, fund: false, id: 'a'),
          (name: 'B', netPaisa: 300, fund: false, id: 'b'),
        ]),
        throwsStateError,
      );
    });

    test('Phase 1: settles exact 1-to-1 debt in a single transaction', () {
      final parties = [
        (name: 'A', netPaisa: -50000, fund: false, id: 'a'),
        (name: 'B', netPaisa: 50000, fund: false, id: 'b'),
      ];

      final txs = DebtSimplifier.simplifyDebts(parties);
      expect(txs.length, equals(1));
      expect(txs.first.from, equals('A'));
      expect(txs.first.to, equals('B'));
      expect(txs.first.amountPaisa, equals(50000));
      expect(txs.first.fromFund, isFalse);
      expect(txs.first.toFund, isFalse);
    });

    test('Phase 2: settles exact 2-to-1 debt in 2 transactions', () {
      final parties = [
        (name: 'A', netPaisa: -20000, fund: false, id: 'a'),
        (name: 'B', netPaisa: -30000, fund: false, id: 'b'),
        (name: 'C', netPaisa: 50000, fund: false, id: 'c'),
      ];

      final txs = DebtSimplifier.simplifyDebts(parties);
      expect(txs.length, equals(2));
      expect(txs.every((t) => t.to == 'C'), isTrue);
      final totalPaid = txs.fold<int>(0, (sum, t) => sum + t.amountPaisa);
      expect(totalPaid, equals(50000));
    });

    test(
        'Phase 3 / Complex: settles multi-party debt network with zero net remainder',
        () {
      final parties = [
        (name: 'Arif', netPaisa: -120000, fund: false, id: 'arif@test.com'),
        (name: 'Bipul', netPaisa: -80000, fund: false, id: 'bipul@test.com'),
        (
          name: 'Chandan',
          netPaisa: -40000,
          fund: false,
          id: 'chandan@test.com'
        ),
        (name: 'Fund', netPaisa: 100000, fund: true, id: null),
        (name: 'Dipto', netPaisa: 140000, fund: false, id: 'dipto@test.com'),
      ];

      final txs = DebtSimplifier.simplifyDebts(parties);

      // Verify net balance of each party after applying transactions is 0
      final netCheck = <String, int>{
        'Arif': -120000,
        'Bipul': -80000,
        'Chandan': -40000,
        'Fund': 100000,
        'Dipto': 140000,
      };

      for (final tx in txs) {
        netCheck[tx.from] = netCheck[tx.from]! + tx.amountPaisa;
        netCheck[tx.to] = netCheck[tx.to]! - tx.amountPaisa;
      }

      for (final entry in netCheck.entries) {
        expect(entry.value, equals(0),
            reason: '${entry.key} did not balance out to 0');
      }

      // Max possible transactions in full mesh would be 3 * 2 = 6, simplified must be fewer
      expect(txs.length, lessThanOrEqualTo(4));
    });

    test('simplifyFromSummary correctly extracts member and fund balances', () {
      const summary = LedgerSummary(
        headcount: 2,
        totalDepositsPaisa: 100000,
        totalExpensePaisa: 80000,
        fundPaidPaisa: 80000,
        fundBalancePaisa: 20000,
        perHeadCostPaisa: 40000,
        rows: [
          LedgerMemberRow(
            id: 'm1',
            name: 'Member 1',
            familyCount: 1,
            depositPaisa: 60000,
            directPaidPaisa: 0,
            contributedPaisa: 60000,
            sharePaisa: 40000,
            netPaisa: 20000,
          ),
          LedgerMemberRow(
            id: 'm2',
            name: 'Member 2',
            familyCount: 1,
            depositPaisa: 40000,
            directPaidPaisa: 0,
            contributedPaisa: 40000,
            sharePaisa: 80000,
            netPaisa: -40000,
          ),
        ],
        settlements: [],
        categoryTotals: [],
      );

      final txs =
          DebtSimplifier.simplifyFromSummary(summary, fundLabel: 'Tour Fund');
      expect(txs.isNotEmpty, isTrue);

      final total = txs.fold<int>(0, (sum, t) => sum + t.amountPaisa);
      expect(total, equals(40000));
    });
  });
}
