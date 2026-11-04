import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bhromon/core/localization/localized_date.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/meal_log.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/meal_engine.dart';

/// Opens the Mess Monthly Meal Rate & Balance Sheet in an adaptive modal sheet.
Future<void> showMessBalanceSheet(
  BuildContext context, {
  required String tourId,
  DateTime? month,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => MessBalanceSheet(tourId: tourId, initialMonth: month),
  );
}

/// Interactive sheet showing the mess meal rate and individual member settlement ledger.
class MessBalanceSheet extends StatefulWidget {
  const MessBalanceSheet({
    super.key,
    required this.tourId,
    this.initialMonth,
  });

  final String tourId;
  final DateTime? initialMonth;

  @override
  State<MessBalanceSheet> createState() => _MessBalanceSheetState();
}

class _MessBalanceSheetState extends State<MessBalanceSheet> {
  final TourGroupRepository _repo = TourGroupRepository();

  late DateTime _month;
  List<TourMember> _members = const [];
  List<MealLog> _logs = const [];
  List<ExpenseItem> _expenses = const [];
  List<DepositItem> _deposits = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = widget.initialMonth ?? DateTime.now();
    _month = DateTime(now.year, now.month);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final membersFuture = _repo.watchMembers(widget.tourId).first;
      final logsFuture = _repo.watchMealsForMonth(widget.tourId, _month).first;
      final expensesFuture = _repo.watchExpenses(widget.tourId).first;
      final depositsFuture = _repo.watchDeposits(widget.tourId).first;

      final results = await Future.wait([
        membersFuture,
        logsFuture,
        expensesFuture,
        depositsFuture,
      ]);

      if (mounted) {
        setState(() {
          _members = results[0] as List<TourMember>;
          _logs = results[1] as List<MealLog>;
          _expenses = results[2] as List<ExpenseItem>;
          _deposits = results[3] as List<DepositItem>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _loadData();
  }

  void _copyReport(MessMonthlyBalance balance) {
    Clipboard.setData(ClipboardData(text: balance.formatReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('মেস ব্যালেন্স শিট ক্লিপবোর্ডে কপি করা হয়েছে!'),
        backgroundColor: AppColors.darkGreen,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareReport(MessMonthlyBalance balance) {
    SharePlus.instance.share(
      ShareParams(
        text: balance.formatReport(),
        subject: 'মেস ব্যালেন্স শিট (${_month.year}-${_month.month})',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDesktop = media.size.width >= 600;

    final balance = calculateMessMonthlyBalance(
      month: _month,
      members: _members,
      logs: _logs,
      expenses: _expenses,
      deposits: _deposits,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          height: media.size.height * 0.88,
          decoration: BoxDecoration(
            color: context.forest.surfaceFor(const Color(0xFF14241B)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border:
                isDesktop ? Border.all(color: context.forest.divider10) : null,
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.mintGreen,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        children: [
                          _buildMonthSelector(context),
                          const SizedBox(height: 14),
                          _buildSummaryCard(context, balance),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'সদস্যদের হিসাব বিবরণী (${balance.memberBalances.length})',
                                style: TextStyle(
                                  color: context.forest.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              if (balance.totalDuePaisa > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'মোট বকেয়া: ৳${(balance.totalDuePaisa / 100).toStringAsFixed(0)}',
                                    style: TextStyle(
                                      color: context.forest
                                          .readable(Colors.redAccent),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (balance.memberBalances.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Text(
                                  'কোনো সদস্যের রেকর্ড পাওয়া যায়নি',
                                  style:
                                      TextStyle(color: context.forest.text54),
                                ),
                              ),
                            )
                          else
                            for (final mb in balance.memberBalances)
                              _buildMemberCard(context, mb),
                          const SizedBox(height: 16),
                          _buildActionButtons(context, balance),
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.forest.divider10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.mintGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.restaurant_rounded,
              color: AppColors.mintGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'মেস মিল ও বাজার হিসাব বিবরণী',
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'স্বয়ংক্রিয় মিল রেট ও ব্যালেন্স শিট',
                  style: TextStyle(
                    color: context.forest.text54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: context.forest.text54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF1B3024)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.forest.divider10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left_rounded, color: context.forest.text),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            localizedDateFormat('MMMM yyyy').format(_month),
            style: TextStyle(
              color: context.forest.text,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right_rounded, color: context.forest.text),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, MessMonthlyBalance balance) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF162B20)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'মোট বাজার খরচ',
                  style: TextStyle(color: context.forest.text54, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  '৳${balance.totalBazarTaka.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: context.forest.readable(AppColors.gold),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: context.forest.divider10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'মোট খাওয়া মিল',
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${balance.totalMeals} টি',
                    style: TextStyle(
                      color: context.forest.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 36, color: context.forest.divider10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'মিল রেট',
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '৳${balance.mealRateTaka.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(BuildContext context, MemberMealBalance mb) {
    final statusColor = mb.isRefund
        ? AppColors.mintGreen
        : mb.isDue
            ? Colors.redAccent
            : context.forest.text54;

    final statusText = mb.isRefund
        ? '+৳${mb.netBalanceTaka.toStringAsFixed(0)} পাবে'
        : mb.isDue
            ? '-৳${mb.netBalanceTaka.toStringAsFixed(0)} দেবে'
            : 'পরিশোধিত';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(const Color(0xFF1B3024)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mb.isDue
              ? Colors.redAccent.withValues(alpha: 0.3)
              : context.forest.divider10,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.mintGreen.withValues(alpha: 0.15),
            foregroundColor: AppColors.mintGreen,
            child: Text(
              mb.displayName.isNotEmpty
                  ? mb.displayName.characters.first.toUpperCase()
                  : '?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mb.displayName,
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'মিল: ${mb.mealCount}টি (৳${mb.mealCostTaka.toStringAsFixed(0)}) · জমা: ৳${mb.totalContributedTaka.toStringAsFixed(0)}',
                  style: TextStyle(color: context.forest.text70, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: context.forest.readable(statusColor),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, MessMonthlyBalance balance) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _copyReport(balance),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('কপি করুন'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.forest.text,
              side: BorderSide(color: context.forest.text24),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _shareReport(balance),
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('শেয়ার করুন'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: AppColors.darkGreen,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
