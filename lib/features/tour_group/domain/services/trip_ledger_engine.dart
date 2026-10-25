import 'dart:math';
import '../models/expense_models.dart';

class LedgerMemberInput {
  final String id;
  final String name;
  final int familyCount;
  final int depositPaisa;

  const LedgerMemberInput({
    required this.id,
    required this.name,
    this.familyCount = 1,
    this.depositPaisa = 0,
  });
}

class LedgerMemberRow {
  final String id;
  final String name;
  final int familyCount;
  final int depositPaisa;
  final int directPaidPaisa;
  final int contributedPaisa;
  final int sharePaisa;
  final int netPaisa;

  const LedgerMemberRow({
    required this.id,
    required this.name,
    required this.familyCount,
    required this.depositPaisa,
    required this.directPaidPaisa,
    required this.contributedPaisa,
    required this.sharePaisa,
    required this.netPaisa,
  });

  double get depositTaka => depositPaisa / 100.0;
  double get directPaidTaka => directPaidPaisa / 100.0;
  double get contributedTaka => contributedPaisa / 100.0;
  double get shareTaka => sharePaisa / 100.0;
  double get netTaka => netPaisa / 100.0;
}

class SettlementTransaction {
  final String from;
  final String to;
  final bool fromFund;
  final bool toFund;
  final int amountPaisa;

  const SettlementTransaction({
    required this.from,
    required this.to,
    this.fromFund = false,
    this.toFund = false,
    required this.amountPaisa,
  });

  double get amountTaka => amountPaisa / 100.0;
}

class CategoryTotal {
  final String category;
  final int amountPaisa;

  const CategoryTotal({required this.category, required this.amountPaisa});
  double get amountTaka => amountPaisa / 100.0;
}

class LedgerSummary {
  final int headcount;
  final int totalDepositsPaisa;
  final int totalExpensePaisa;
  final int fundPaidPaisa;
  final int fundBalancePaisa;
  final int perHeadCostPaisa;
  final List<LedgerMemberRow> rows;
  final List<SettlementTransaction> settlements;
  final List<CategoryTotal> categoryTotals;

  const LedgerSummary({
    required this.headcount,
    required this.totalDepositsPaisa,
    required this.totalExpensePaisa,
    required this.fundPaidPaisa,
    required this.fundBalancePaisa,
    required this.perHeadCostPaisa,
    required this.rows,
    required this.settlements,
    required this.categoryTotals,
  });

  double get totalDepositsTaka => totalDepositsPaisa / 100.0;
  double get totalExpenseTaka => totalExpensePaisa / 100.0;
  double get fundPaidTaka => fundPaidPaisa / 100.0;
  double get fundBalanceTaka => fundBalancePaisa / 100.0;
  double get perHeadCostTaka => perHeadCostPaisa / 100.0;
}

/// Pure Dart financial ledger engine operating in whole integer paisa.
/// Eliminates floating-point rounding errors and minimizes cash settlement transfers.
class TripLedgerEngine {
  static const String fundLabel = 'ট্যুর ফান্ড';
  static const int maxSafeAmountTaka = 10000000;

  static int toPaisa(num? taka) {
    if (taka == null || taka.isNaN || taka.isInfinite) return 0;
    final clamped =
        max(0.0, min(maxSafeAmountTaka.toDouble(), taka.toDouble()));
    return (clamped * 100).round();
  }

  static double toTaka(int paisa) => paisa / 100.0;

  /// Splits `total` integer paisa proportionally by `weights` using the largest-remainder method.
  /// Guarantees that parts sum to exactly `total` with zero lost or created paisa.
  static List<int> allocate(int total, List<int> weights) {
    if (weights.isEmpty) return [];
    final weightSum = weights.fold<int>(0, (sum, w) => sum + w);
    if (weightSum <= 0 || total == 0) return List.filled(weights.length, 0);

    final exact = weights.map((w) => (total * w) / weightSum).toList();
    final parts = exact.map((v) => v.floor()).toList();
    int leftover = total - parts.fold<int>(0, (sum, p) => sum + p);

    final fractions = List.generate(exact.length, (i) => i);
    fractions.sort((a, b) {
      final fracA = exact[a] - exact[a].floor();
      final fracB = exact[b] - exact[b].floor();
      final cmp = fracB.compareTo(fracA);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

    for (int i = 0; leftover > 0 && i < fractions.length; i++, leftover--) {
      parts[fractions[i]] += 1;
    }

    return parts;
  }

  /// Calculates settlements that balance all debts and credits with minimum transactions.
  static List<SettlementTransaction> settle(
      List<({String name, int netPaisa, bool fund})> parties) {
    final balanceSum = parties.fold<int>(0, (sum, p) => sum + p.netPaisa);
    if (balanceSum.abs() > 1) {
      throw StateError(
          'Ledger balances do not sum to zero: total net is $balanceSum paisa');
    }

    final debtors = parties
        .where((p) => p.netPaisa < 0)
        .map((p) => _PartyBalance(
            name: p.name, amountPaisa: -p.netPaisa, isFund: p.fund))
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    final creditors = parties
        .where((p) => p.netPaisa > 0)
        .map((p) => _PartyBalance(
            name: p.name, amountPaisa: p.netPaisa, isFund: p.fund))
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    final transactions = <SettlementTransaction>[];
    int d = 0;
    int c = 0;
    final maxIterations = (debtors.length + creditors.length) * 2;
    int iterations = 0;

    while (d < debtors.length &&
        c < creditors.length &&
        iterations < maxIterations) {
      iterations++;
      final amount = min(debtors[d].amountPaisa, creditors[c].amountPaisa);
      if (amount <= 0) break;

      transactions.add(
        SettlementTransaction(
          from: debtors[d].name,
          to: creditors[c].name,
          fromFund: debtors[d].isFund,
          toFund: creditors[c].isFund,
          amountPaisa: amount,
        ),
      );

      debtors[d].amountPaisa -= amount;
      creditors[c].amountPaisa -= amount;

      if (debtors[d].amountPaisa == 0) d++;
      if (creditors[c].amountPaisa == 0) c++;
    }

    return transactions;
  }

  /// Computes the complete multi-member ledger summary.
  static LedgerSummary computeLedger({
    required List<LedgerMemberInput> members,
    required List<ExpenseItem> expenses,
  }) {
    final weights = members.map((m) => max(1, m.familyCount)).toList();
    final headcount = weights.fold<int>(0, (sum, w) => sum + w);

    int totalExpensePaisa = 0;
    int fundPaidPaisa = 0;
    final directPaisaMap = <String, int>{for (var m in members) m.id: 0};

    // Category tracking
    final categoryMap = <String, int>{};

    for (final exp in expenses) {
      final paisa = exp.amountPaisa;
      totalExpensePaisa += paisa;

      final cat = exp.category.isNotEmpty ? exp.category : 'Others';
      categoryMap[cat] = (categoryMap[cat] ?? 0) + paisa;

      final payerId = exp.paidById;
      if (payerId == null || payerId.isEmpty) {
        fundPaidPaisa += paisa;
      } else {
        directPaisaMap[payerId] = (directPaisaMap[payerId] ?? 0) + paisa;
      }
    }

    final shares = allocate(totalExpensePaisa, weights);
    final rows = <LedgerMemberRow>[];

    for (int i = 0; i < members.length; i++) {
      final m = members[i];
      final direct = directPaisaMap[m.id] ?? 0;
      final contributed = m.depositPaisa + direct;
      final net = contributed - shares[i];

      rows.add(
        LedgerMemberRow(
          id: m.id,
          name: m.name,
          familyCount: weights[i],
          depositPaisa: m.depositPaisa,
          directPaidPaisa: direct,
          contributedPaisa: contributed,
          sharePaisa: shares[i],
          netPaisa: net,
        ),
      );
    }

    final totalDepositsPaisa =
        members.fold<int>(0, (sum, m) => sum + m.depositPaisa);
    final fundBalancePaisa = totalDepositsPaisa - fundPaidPaisa;
    final netSumPaisa = rows.fold<int>(0, (sum, r) => sum + r.netPaisa);

    final parties = [
      ...rows.map((r) => (name: r.name, netPaisa: r.netPaisa, fund: false)),
      (name: fundLabel, netPaisa: -netSumPaisa, fund: true),
    ];

    final settlements = settle(parties);

    final categoryTotalsList = categoryMap.entries
        .map((e) => CategoryTotal(category: e.key, amountPaisa: e.value))
        .toList()
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    return LedgerSummary(
      headcount: headcount,
      totalDepositsPaisa: totalDepositsPaisa,
      totalExpensePaisa: totalExpensePaisa,
      fundPaidPaisa: fundPaidPaisa,
      fundBalancePaisa: fundBalancePaisa,
      perHeadCostPaisa:
          headcount > 0 ? (totalExpensePaisa / headcount).round() : 0,
      rows: rows,
      settlements: settlements,
      categoryTotals: categoryTotalsList,
    );
  }
}

class _PartyBalance {
  final String name;
  int amountPaisa;
  final bool isFund;

  _PartyBalance({
    required this.name,
    required this.amountPaisa,
    this.isFund = false,
  });
}
