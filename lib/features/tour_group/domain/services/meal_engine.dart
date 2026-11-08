import '../models/date_codec.dart';
import '../models/expense_models.dart';
import '../models/meal_log.dart';
import '../models/tour_group.dart';

// Dates, rates and balance sheet calculations for a bachelor mess / mess meal manager.
// Pure Dart, so it is 100% unit-tested and fast.

/// A day as yyyy-MM-dd.
String mealDateKey(DateTime day) {
  final year = day.year.toString().padLeft(4, '0');
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '$year-$month-$date';
}

/// The first day of the month, as a day key.
String mealMonthFirstKey(DateTime month) =>
    mealDateKey(DateTime(month.year, month.month));

/// The last day of the month, as a day key. Day zero of the next month is the last
/// day of this one.
String mealMonthLastKey(DateTime month) =>
    mealDateKey(DateTime(month.year, month.month + 1, 0));

/// How many days the month has.
int mealDaysInMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0).day;

/// Each member's meals over the logs, keyed by email. A member with no meals is left
/// out, so a bazar split gives them no share.
Map<String, int> mealTotalsByEmail(Iterable<MealLog> logs) {
  final totals = <String, int>{};
  for (final log in logs) {
    if (log.total == 0) continue;
    final email = normalizeEmail(log.email);
    totals[email] = (totals[email] ?? 0) + log.total;
  }
  return totals;
}

/// A member's monthly mess meal consumption and settlement position.
class MemberMealBalance {
  const MemberMealBalance({
    required this.email,
    required this.displayName,
    required this.mealCount,
    required this.mealCostPaisa,
    required this.bazarPaidPaisa,
    required this.depositPaidPaisa,
    this.settledPaidPaisa = 0,
    this.refundReceivedPaisa = 0,
    required this.totalContributedPaisa,
    required this.netBalancePaisa,
  });

  final String email;
  final String displayName;

  /// Total number of meals consumed by this member in the period.
  final int mealCount;

  /// Total meal cost in paisa (mealCount * mealRate).
  final int mealCostPaisa;

  /// Bazaar/groceries personally paid by this member.
  final int bazarPaidPaisa;

  /// Advance deposits paid by this member into the mess fund.
  final int depositPaidPaisa;

  /// Settle-up payments paid into the mess fund by this member to clear past dues.
  final int settledPaidPaisa;

  /// Settle-up refunds paid out to this member from the mess fund.
  final int refundReceivedPaisa;

  /// Total funds contributed by this member (`bazarPaidPaisa + depositPaidPaisa + settledPaidPaisa - refundReceivedPaisa`).
  final int totalContributedPaisa;

  /// Net balance in paisa:
  /// - `> 0`: Member is owed a refund (টাকা ফেরত পাবে).
  /// - `< 0`: Member owes money to the mess (বকেয়া দিতে হবে).
  /// - `== 0`: Account is settled.
  final int netBalancePaisa;

  bool get isDue => netBalancePaisa < 0;
  bool get isRefund => netBalancePaisa > 0;
  bool get isSettled => netBalancePaisa == 0;

  double get mealCostTaka => mealCostPaisa / 100.0;
  double get totalContributedTaka => totalContributedPaisa / 100.0;
  double get netBalanceTaka => netBalancePaisa.abs() / 100.0;
  double get settledPaidTaka => settledPaidPaisa / 100.0;
  double get refundReceivedTaka => refundReceivedPaisa / 100.0;
}

/// The entire mess's consolidated monthly balance sheet and meal rate report.
class MessMonthlyBalance {
  const MessMonthlyBalance({
    required this.month,
    required this.totalBazarPaisa,
    required this.totalMeals,
    required this.mealRatePaisa,
    required this.memberBalances,
  });

  final DateTime month;

  /// Total cost of bazaar/food expenses in paisa.
  final int totalBazarPaisa;

  /// Total meals consumed across all members.
  final int totalMeals;

  /// Meal rate in paisa per meal (`totalBazarPaisa / totalMeals`).
  final double mealRatePaisa;

  /// Individual member balances.
  final List<MemberMealBalance> memberBalances;

  double get totalBazarTaka => totalBazarPaisa / 100.0;
  double get mealRateTaka => mealRatePaisa / 100.0;

  /// Total amount owed by members who have negative balances.
  int get totalDuePaisa => memberBalances
      .where((m) => m.isDue)
      .fold(0, (sum, m) => sum + m.netBalancePaisa.abs());

  /// Total refund owed to members who have positive balances.
  int get totalRefundPaisa => memberBalances
      .where((m) => m.isRefund)
      .fold(0, (sum, m) => sum + m.netBalancePaisa);

  /// Generates a plain Bengali text summary for sharing with mess members.
  String formatReport() {
    final buffer = StringBuffer()
      ..writeln('🏠 মেস মিল ও বাজার মাসিক ব্যালেন্স শিট')
      ..writeln('মাস: ${month.year}-${month.month.toString().padLeft(2, '0')}')
      ..writeln('----------------------------------------')
      ..writeln('মোট বাজার খরচ: ৳${totalBazarTaka.toStringAsFixed(2)}')
      ..writeln('মোট খাবার সংখ্যা: $totalMeals টি')
      ..writeln('মিল রেট: ৳${mealRateTaka.toStringAsFixed(2)} / মিল')
      ..writeln('----------------------------------------')
      ..writeln('সদস্যদের হিসাব বিবরণী:');

    for (final m in memberBalances) {
      final status = m.isRefund
          ? 'ফেরত পাবে: +৳${m.netBalanceTaka.toStringAsFixed(2)}'
          : m.isDue
              ? 'বকেয়া দেবে: -৳${m.netBalanceTaka.toStringAsFixed(2)}'
              : 'পরিশোধিত';
      buffer.writeln(
          '• ${m.displayName}: মিল ${m.mealCount}টি (খরচ ৳${m.mealCostTaka.toStringAsFixed(2)}) | জমা/বাজার ৳${m.totalContributedTaka.toStringAsFixed(2)} | $status');
    }
    return buffer.toString();
  }
}

/// Computes the monthly meal rate and individual member settlement ledger.
MessMonthlyBalance calculateMessMonthlyBalance({
  required DateTime month,
  required List<TourMember> members,
  required Iterable<MealLog> logs,
  required Iterable<ExpenseItem> expenses,
  required Iterable<DepositItem> deposits,
  Iterable<TransferItem> transfers = const [],
}) {
  // 1. Filter expenses for the given month.
  final monthExpenses = expenses
      .where((e) => e.date.year == month.year && e.date.month == month.month)
      .toList();

  // Bazar expenses: category 'Groceries' or 'Food'. If no specific food categories
  // exist, include all expenses for this mess.
  var bazarExpenses = monthExpenses.where((e) {
    final cat = e.category.toLowerCase();
    return cat == 'groceries' ||
        cat == 'food' ||
        cat == 'bazar' ||
        cat == 'বাজার';
  }).toList();

  if (bazarExpenses.isEmpty && monthExpenses.isNotEmpty) {
    bazarExpenses = monthExpenses;
  }

  final totalBazarPaisa =
      bazarExpenses.fold<int>(0, (sum, e) => sum + e.amountPaisa);

  // 2. Count total meals consumed in the month.
  final mealCounts = mealTotalsByEmail(logs);
  final totalMeals =
      mealCounts.values.fold<int>(0, (sum, count) => sum + count);

  // 3. Compute meal rate.
  final double mealRatePaisa =
      totalMeals > 0 ? (totalBazarPaisa / totalMeals) : 0.0;

  // 4. Filter deposits and transfers for the given month.
  final monthDeposits = deposits
      .where((d) => d.date.year == month.year && d.date.month == month.month)
      .toList();

  final monthTransfers = transfers
      .where((t) => t.date.year == month.year && t.date.month == month.month)
      .toList();

  // 5. Build member balances.
  final memberBalances = <MemberMealBalance>[];
  for (final m in members) {
    final email = normalizeEmail(m.email);
    final count = mealCounts[email] ?? 0;
    final mealCost = (count * mealRatePaisa).round();

    // Bazar paid directly by this member
    final bazarPaid = bazarExpenses
        .where((e) => normalizeEmail(e.paidById ?? '') == email)
        .fold<int>(0, (sum, e) => sum + e.amountPaisa);

    // Deposits paid into the mess fund by this member
    final depositPaid = monthDeposits
        .where((d) => normalizeEmail(d.memberId) == email)
        .fold<int>(0, (sum, d) => sum + d.amountPaisa);

    // Transfers: Settle-up payments paid into fund by this member
    final settledPaid = monthTransfers
        .where((t) =>
            !t.fromFund && t.toFund && normalizeEmail(t.fromId ?? '') == email)
        .fold<int>(0, (sum, t) => sum + t.amountPaisa);

    // Transfers: Refunds received by this member from fund
    final refundReceived = monthTransfers
        .where((t) => t.fromFund && normalizeEmail(t.toId ?? '') == email)
        .fold<int>(0, (sum, t) => sum + t.amountPaisa);

    final totalContributed =
        bazarPaid + depositPaid + settledPaid - refundReceived;
    final netBalance = totalContributed - mealCost;

    memberBalances.add(MemberMealBalance(
      email: email,
      displayName: m.displayName.isEmpty ? email : m.displayName,
      mealCount: count,
      mealCostPaisa: mealCost,
      bazarPaidPaisa: bazarPaid,
      depositPaidPaisa: depositPaid,
      settledPaidPaisa: settledPaid,
      refundReceivedPaisa: refundReceived,
      totalContributedPaisa: totalContributed,
      netBalancePaisa: netBalance,
    ));
  }

  // Sort: members with dues first, then refunds, then settled
  memberBalances.sort((a, b) {
    if (a.isDue && !b.isDue) return -1;
    if (!a.isDue && b.isDue) return 1;
    return a.netBalancePaisa.compareTo(b.netBalancePaisa);
  });

  return MessMonthlyBalance(
    month: month,
    totalBazarPaisa: totalBazarPaisa,
    totalMeals: totalMeals,
    mealRatePaisa: mealRatePaisa,
    memberBalances: memberBalances,
  );
}
