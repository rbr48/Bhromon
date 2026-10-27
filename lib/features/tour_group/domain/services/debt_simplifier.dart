import 'dart:math';

import 'trip_ledger_engine.dart';

/// Solves the Minimum Cash Flow problem to settle all debts with the fewest
/// possible bilateral transactions (Debt Simplification).
class DebtSimplifier {
  const DebtSimplifier._();

  /// Takes a list of parties with their net paisa balance and computes an optimal
  /// simplified settlement plan that minimizes the total transaction count.
  static List<SettlementTransaction> simplifyDebts(
    List<({String name, int netPaisa, bool fund, String? id})> parties,
  ) {
    if (parties.isEmpty) return const [];

    final balanceSum = parties.fold<int>(0, (sum, p) => sum + p.netPaisa);
    if (balanceSum.abs() > 1) {
      throw StateError(
          'Ledger balances do not sum to zero: total net is $balanceSum paisa');
    }

    final debtors = <_SimpleParty>[];
    final creditors = <_SimpleParty>[];

    for (final p in parties) {
      if (p.netPaisa < 0) {
        debtors.add(_SimpleParty(
          name: p.name,
          id: p.id,
          amountPaisa: -p.netPaisa,
          isFund: p.fund,
        ));
      } else if (p.netPaisa > 0) {
        creditors.add(_SimpleParty(
          name: p.name,
          id: p.id,
          amountPaisa: p.netPaisa,
          isFund: p.fund,
        ));
      }
    }

    final transactions = <SettlementTransaction>[];

    // Phase 1: Exact 1-to-1 matching (Pairs of 1 Debtor and 1 Creditor with identical amounts)
    // Eliminates 2 parties in a single transfer.
    for (int d = 0; d < debtors.length; d++) {
      if (debtors[d].amountPaisa == 0) continue;
      for (int c = 0; c < creditors.length; c++) {
        if (creditors[c].amountPaisa == 0) continue;
        if (debtors[d].amountPaisa == creditors[c].amountPaisa) {
          final amt = debtors[d].amountPaisa;
          transactions.add(
            SettlementTransaction(
              from: debtors[d].name,
              to: creditors[c].name,
              fromId: debtors[d].id,
              toId: creditors[c].id,
              fromFund: debtors[d].isFund,
              toFund: creditors[c].isFund,
              amountPaisa: amt,
            ),
          );
          debtors[d].amountPaisa = 0;
          creditors[c].amountPaisa = 0;
          break;
        }
      }
    }

    // Phase 2: Exact 2-to-1 matching (2 debtors equal 1 creditor, or 1 debtor equals 2 creditors)
    // Eliminates 3 parties in 2 transfers.
    for (int c = 0; c < creditors.length; c++) {
      if (creditors[c].amountPaisa == 0) continue;
      for (int d1 = 0; d1 < debtors.length; d1++) {
        if (debtors[d1].amountPaisa == 0) continue;
        for (int d2 = d1 + 1; d2 < debtors.length; d2++) {
          if (debtors[d2].amountPaisa == 0) continue;
          if (debtors[d1].amountPaisa + debtors[d2].amountPaisa ==
              creditors[c].amountPaisa) {
            // Settle d1 -> c
            transactions.add(
              SettlementTransaction(
                from: debtors[d1].name,
                to: creditors[c].name,
                fromId: debtors[d1].id,
                toId: creditors[c].id,
                fromFund: debtors[d1].isFund,
                toFund: creditors[c].isFund,
                amountPaisa: debtors[d1].amountPaisa,
              ),
            );
            // Settle d2 -> c
            transactions.add(
              SettlementTransaction(
                from: debtors[d2].name,
                to: creditors[c].name,
                fromId: debtors[d2].id,
                toId: creditors[c].id,
                fromFund: debtors[d2].isFund,
                toFund: creditors[c].isFund,
                amountPaisa: debtors[d2].amountPaisa,
              ),
            );
            creditors[c].amountPaisa = 0;
            debtors[d1].amountPaisa = 0;
            debtors[d2].amountPaisa = 0;
            break;
          }
        }
        if (creditors[c].amountPaisa == 0) break;
      }
    }

    // Phase 3: Settle remaining balances using sorted greedy pairing
    final remainingDebtors = debtors.where((p) => p.amountPaisa > 0).toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));
    final remainingCreditors = creditors
        .where((p) => p.amountPaisa > 0)
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    int dIdx = 0;
    int cIdx = 0;
    final maxIterations =
        (remainingDebtors.length + remainingCreditors.length) * 2;
    int iterations = 0;

    while (dIdx < remainingDebtors.length &&
        cIdx < remainingCreditors.length &&
        iterations < maxIterations) {
      iterations++;
      final amount = min(remainingDebtors[dIdx].amountPaisa,
          remainingCreditors[cIdx].amountPaisa);
      if (amount <= 0) break;

      transactions.add(
        SettlementTransaction(
          from: remainingDebtors[dIdx].name,
          to: remainingCreditors[cIdx].name,
          fromId: remainingDebtors[dIdx].id,
          toId: remainingCreditors[cIdx].id,
          fromFund: remainingDebtors[dIdx].isFund,
          toFund: remainingCreditors[cIdx].isFund,
          amountPaisa: amount,
        ),
      );

      remainingDebtors[dIdx].amountPaisa -= amount;
      remainingCreditors[cIdx].amountPaisa -= amount;

      if (remainingDebtors[dIdx].amountPaisa == 0) dIdx++;
      if (remainingCreditors[cIdx].amountPaisa == 0) cIdx++;
    }

    return transactions;
  }

  /// Convenience helper to run debt simplification directly from a [LedgerSummary].
  static List<SettlementTransaction> simplifyFromSummary(
    LedgerSummary summary, {
    String fundLabel = 'Fund',
  }) {
    final netSumPaisa = summary.rows.fold<int>(0, (sum, r) => sum + r.netPaisa);
    final parties = [
      ...summary.rows.map(
        (r) => (name: r.name, netPaisa: r.netPaisa, fund: false, id: r.id),
      ),
      (name: fundLabel, netPaisa: -netSumPaisa, fund: true, id: null),
    ];
    return simplifyDebts(parties);
  }
}

class _SimpleParty {
  final String name;
  final String? id;
  int amountPaisa;
  final bool isFund;

  _SimpleParty({
    required this.name,
    required this.id,
    required this.amountPaisa,
    required this.isFund,
  });
}
