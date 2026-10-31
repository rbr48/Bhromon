import '../models/expense_models.dart';
import '../models/tour_group.dart';
import 'trip_ledger_engine.dart';

/// The expense categories a trip's fund offers, in display order. Older expenses
/// with other names keep them and show as typed.
const List<String> kExpenseCategories = [
  'Food',
  'Transport',
  'Hotel',
  'Tickets',
  'Guide',
  'Activities',
  'Shopping',
  'Medical',
  'Tips',
  'Others',
];

/// The categories a family circle's ledger offers: the household's bills and
/// everyday spending, not a trip's hotels and guides.
const List<String> kFamilyExpenseCategories = [
  'Groceries',
  'Utilities',
  'Rent',
  'School',
  'Medical',
  'Transport',
  'Dining',
  'Shopping',
  'Gifts',
  'Others',
];

/// The categories offered for a circle: family or trip.
List<String> expenseCategoriesFor({required bool family}) =>
    family ? kFamilyExpenseCategories : kExpenseCategories;

/// The category a chat `/split` books its expense under. Dinner in the kitchen
/// channel is food; anything else is "Others", which the owner can change.
String splitCategoryFor({required bool family, required String channelId}) {
  if (channelId != 'food') return 'Others';
  return family ? 'Groceries' : 'Food';
}

/// A currency an expense may be paid in.
class FundCurrency {
  const FundCurrency(this.code, this.symbol);

  final String code;
  final String symbol;
}

/// BDT first, then the currencies Bangladeshi groups most often spend abroad.
const List<FundCurrency> kFundCurrencies = [
  FundCurrency('BDT', '৳'),
  FundCurrency('INR', '₹'),
  FundCurrency('NPR', 'रु'),
  FundCurrency('BTN', 'Nu'),
  FundCurrency('USD', r'$'),
  FundCurrency('THB', '฿'),
  FundCurrency('MYR', 'RM'),
  FundCurrency('SGD', r'S$'),
  FundCurrency('AED', 'د.إ'),
  FundCurrency('SAR', '﷼'),
  FundCurrency('EUR', '€'),
  FundCurrency('GBP', '£'),
];

/// BDT paisa for [originalMinor] units of a currency (cents, paise…) at
/// [rate] taka per unit. Null for a rate that is not positive.
int? convertToPaisa(int originalMinor, double rate) {
  if (rate <= 0 || rate.isNaN || rate.isInfinite) return null;
  return (originalMinor * rate).round();
}

/// One category's budget against what was spent.
class BudgetLine {
  const BudgetLine({
    required this.category,
    required this.budgetPaisa,
    required this.spentPaisa,
  });

  final String category;
  final int budgetPaisa;
  final int spentPaisa;

  int get leftPaisa => budgetPaisa - spentPaisa;
  bool get isOver => budgetPaisa > 0 && spentPaisa > budgetPaisa;

  /// Spent as a share of budget; 0 with no budget.
  double get ratio => budgetPaisa <= 0 ? 0 : spentPaisa / budgetPaisa;
}

/// What a member was asked to pay into the fund, and what they have paid.
class CollectionRow {
  const CollectionRow({
    required this.id,
    required this.name,
    required this.targetPaisa,
    required this.paidPaisa,
  });

  final String id;
  final String name;
  final int targetPaisa;
  final int paidPaisa;

  int get duePaisa => targetPaisa > paidPaisa ? targetPaisa - paidPaisa : 0;
  bool get isPaid => targetPaisa > 0 && duePaisa == 0;
}

/// Spending on one day.
class DaySpend {
  const DaySpend(this.day, this.paisa);

  final DateTime day;
  final int paisa;
}

/// The fund at a glance: budget against spending, the daily burn and where
/// it is heading, spending by day, destination and category, and who still
/// owes their share of the collection.
class FundReport {
  const FundReport({
    required this.lines,
    required this.budgetPaisa,
    required this.spentPaisa,
    required this.byDay,
    required this.byStop,
    required this.topExpenses,
    required this.collection,
    required this.daysElapsed,
    required this.totalDays,
  });

  /// Budgeted categories first, then any other category spent on.
  final List<BudgetLine> lines;
  final int budgetPaisa;
  final int spentPaisa;
  final List<DaySpend> byDay;

  /// Spending by itinerary stop id; null collects spending at no stop.
  final Map<String?, int> byStop;
  final List<ExpenseItem> topExpenses;
  final List<CollectionRow> collection;

  /// Tour days so far (at least 1 once the tour starts) and in all.
  final int daysElapsed;
  final int totalDays;

  int get leftPaisa => budgetPaisa - spentPaisa;
  bool get isOverBudget => budgetPaisa > 0 && spentPaisa > budgetPaisa;

  /// Average spent per tour day so far, or 0 before the tour starts.
  int get perDayPaisa => daysElapsed == 0 ? 0 : spentPaisa ~/ daysElapsed;

  /// The trip's total if spending goes on at today's daily rate. Before the
  /// tour starts, or after it ends, it is what has been spent.
  int get projectedPaisa => daysElapsed == 0 || daysElapsed >= totalDays
      ? spentPaisa
      : perDayPaisa * totalDays;

  int get collectedPaisa => collection.fold(0, (n, r) => n + r.paidPaisa);
  int get collectionTargetPaisa =>
      collection.fold(0, (n, r) => n + r.targetPaisa);
  int get collectionDuePaisa => collection.fold(0, (n, r) => n + r.duePaisa);

  static FundReport build({
    required TourGroup group,
    required List<LedgerMemberInput> members,
    required List<ExpenseItem> expenses,
    List<DepositItem> deposits = const [],
    List<TransferItem> transfers = const [],
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final budget = group.fundBudget;
    final categories = expenseCategoriesFor(family: group.isFamily);

    final spentByCat = <String, int>{};
    final byDayMap = <DateTime, int>{};
    final byStop = <String?, int>{};
    var spent = 0;
    for (final e in expenses) {
      spent += e.amountPaisa;
      final cat = e.category.isEmpty ? 'Others' : e.category;
      spentByCat[cat] = (spentByCat[cat] ?? 0) + e.amountPaisa;
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      byDayMap[day] = (byDayMap[day] ?? 0) + e.amountPaisa;
      // Expenses saved before stops existed go by the day they were spent.
      final stop = e.stopId ?? group.stopOn(e.date)?.id;
      byStop[stop] = (byStop[stop] ?? 0) + e.amountPaisa;
    }

    final lines = <BudgetLine>[
      for (final c in categories)
        if ((budget.categoryPaisa[c] ?? 0) > 0 || (spentByCat[c] ?? 0) > 0)
          BudgetLine(
            category: c,
            budgetPaisa: budget.categoryPaisa[c] ?? 0,
            spentPaisa: spentByCat[c] ?? 0,
          ),
      for (final c in {...budget.categoryPaisa.keys, ...spentByCat.keys})
        if (!categories.contains(c))
          BudgetLine(
            category: c,
            budgetPaisa: budget.categoryPaisa[c] ?? 0,
            spentPaisa: spentByCat[c] ?? 0,
          ),
    ]..sort((a, b) {
        final aBudget = a.budgetPaisa > 0 ? 0 : 1;
        final bBudget = b.budgetPaisa > 0 ? 0 : 1;
        if (aBudget != bBudget) return aBudget.compareTo(bBudget);
        return b.spentPaisa.compareTo(a.spentPaisa);
      });

    final byDay = [
      for (final e in byDayMap.entries) DaySpend(e.key, e.value),
    ]..sort((a, b) => a.day.compareTo(b.day));

    final top = [...expenses]
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    // Paid in: deposits, plus settle-up payments into the fund.
    final paid = <String, int>{};
    for (final d in deposits) {
      final k = d.memberId.toLowerCase();
      paid[k] = (paid[k] ?? 0) + d.amountPaisa;
    }
    for (final t in transfers) {
      if (t.toId == null && t.fromId != null) {
        final k = t.fromId!.toLowerCase();
        paid[k] = (paid[k] ?? 0) + t.amountPaisa;
      }
    }
    final List<CollectionRow> collection;
    if (budget.perHeadTargetPaisa <= 0) {
      collection = const <CollectionRow>[];
    } else {
      collection = [
        for (final m in members)
          CollectionRow(
            id: m.id,
            name: m.name,
            targetPaisa: budget.perHeadTargetPaisa * m.familyCount.clamp(1, 20),
            paidPaisa: paid[m.id.toLowerCase()] ?? 0,
          ),
      ]..sort((a, b) => b.duePaisa.compareTo(a.duePaisa));
    }

    final start = DateTime(
        group.startDate.year, group.startDate.month, group.startDate.day);
    final day = DateTime(today.year, today.month, today.day);
    final elapsed = day.isBefore(start)
        ? 0
        : (day.difference(start).inDays + 1).clamp(1, group.totalDays);

    return FundReport(
      lines: lines,
      budgetPaisa: budget.totalPaisa,
      spentPaisa: spent,
      byDay: byDay,
      byStop: byStop,
      topExpenses: top.take(5).toList(),
      collection: collection,
      daysElapsed: elapsed,
      totalDays: group.totalDays,
    );
  }
}
