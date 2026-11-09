import 'package:flutter/material.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/swipe_step.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/meal_log.dart';
import '../../domain/models/mess_bazar_model.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/meal_engine.dart';
import '../widgets/mess/mess_balance_sheet.dart';
import '../widgets/mess/mess_bazar_sheet.dart';

const _bg = Color(0xFF0F1A1C);
const _card = Color(0xFF142428);

/// A mess's meal log. For each day, every member's breakfast, lunch and dinner. A
/// member sets their own row; an owner or admin sets any row. The month's totals
/// split a bazar.
class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key, required this.tourId});

  final String tourId;

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<List<TourMember>> _members =
      _repository.watchMembers(widget.tourId);
  late Stream<List<MealLog>> _logs;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _day = DateTime.now().day;
  TourRole? _myRole;

  bool get _isAdmin => _myRole?.isAdminOrOwner ?? false;
  String get _me => _repository.currentEmail;
  String get _selectedKey =>
      mealDateKey(DateTime(_month.year, _month.month, _day));

  @override
  void initState() {
    super.initState();
    _logs = _repository.watchMealsForMonth(widget.tourId, _month);
    _repository.myRole(widget.tourId).then((role) {
      if (mounted) setState(() => _myRole = role);
    }, onError: (Object _) {});
  }

  void _moveMonth(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _day = 1;
      _logs = _repository.watchMealsForMonth(widget.tourId, _month);
    });
  }

  /// Moves the selected day by [by] within the month. The ends stop the swipe.
  void _stepDay(int by) {
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final next = _day + by;
    if (next < 1 || next > days) return;
    setState(() => _day = next);
  }

  Future<void> _save(MealLog log) async {
    try {
      await _repository.saveMeal(widget.tourId, log);
    } catch (err) {
      logError('Meal save failed: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.translate('meals_save_failed')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StreamBuilder<List<TourMember>>(
      stream: _members,
      builder: (context, memberSnap) {
        final members = [...?memberSnap.data]..sort((a, b) =>
            _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase()));
        return Scaffold(
          backgroundColor: context.forest.surfaceFor(_bg),
          appBar: AppBar(
            backgroundColor: context.forest.surfaceFor(_bg),
            iconTheme: IconThemeData(color: context.forest.text),
            title: Text(l10n.translate('meals_title'),
                style: TextStyle(color: context.forest.text)),
            actions: [
              IconButton(
                tooltip: l10n.translate('mess_bazar_duty_title'),
                icon: const Icon(Icons.storefront_rounded),
                onPressed: () => showMessBazarSheet(
                  context,
                  tourId: widget.tourId,
                  isAdmin: _isAdmin,
                  members: members,
                  initialDateKey: _selectedKey,
                ),
              ),
              IconButton(
                tooltip: 'মেস মিল ও বাজার হিসাব বিবরণী',
                icon: const Icon(Icons.receipt_long_rounded),
                onPressed: () => showMessBalanceSheet(
                  context,
                  tourId: widget.tourId,
                  month: _month,
                ),
              ),
            ],
          ),
          body: StreamBuilder<List<MealLog>>(
            stream: _logs,
            builder: (context, logSnap) {
              if (logSnap.hasError) {
                return _message(l10n.translate('meals_load_failed'));
              }
              final logs = logSnap.data;
              if (logs == null || memberSnap.data == null) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.mintGreen));
              }
              return SwipeStep(
                onStep: _stepDay,
                nextLabel: l10n.translate('meals_next_day'),
                previousLabel: l10n.translate('meals_prev_day'),
                child: _body(members, logs, l10n),
              );
            },
          ),
        );
      },
    );
  }

  Widget _body(
      List<TourMember> members, List<MealLog> logs, AppLocalizations l10n) {
    final dayKey = _selectedKey;
    final dayLogs = {
      for (final log in logs)
        if (log.dateKey == dayKey) log.email: log,
    };
    final totals = mealTotalsByEmail(logs);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _monthBar(l10n),
        const SizedBox(height: 8),
        _dayStrip(),
        const SizedBox(height: 8),
        StreamBuilder<MessBazarSchedule?>(
          stream:
              _repository.watchBazarScheduleForDay(widget.tourId, _selectedKey),
          builder: (context, snap) {
            final sched = snap.data;
            if (sched == null || sched.assignedNames.isEmpty) {
              return const SizedBox.shrink();
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showMessBazarSheet(
                  context,
                  tourId: widget.tourId,
                  isAdmin: _isAdmin,
                  members: members,
                  initialDateKey: _selectedKey,
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.forest.surfaceFor(_card),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sched.isCompleted
                          ? AppColors.mintGreen.withValues(alpha: 0.3)
                          : AppColors.gold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sched.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.storefront_rounded,
                        size: 16,
                        color: sched.isCompleted
                            ? AppColors.mintGreen
                            : AppColors.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'আজকের বাজার: ${sched.assignedNames.join(', ')}${sched.estimatedBudgetPaisa != null ? ' (৳ ${sched.estimatedBudgetPaisa! ~/ 100})' : ''}',
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: context.forest.text38),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showMessBalanceSheet(
            context,
            tourId: widget.tourId,
            month: _month,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.mintGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.mintGreen.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calculate_outlined,
                  color: AppColors.mintGreen,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'মাসিক মিল রেট ও ব্যালেন্স বিবরণী',
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'বাজার খরচ ও সদস্যভিত্তিক বকেয়া/ফেরত হিসাব দেখুন',
                        style: TextStyle(
                          color: context.forest.text54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: context.forest.text54,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _section(
          l10n.translate('meals_month_totals'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in members)
                _row(
                  _nameOf(m),
                  l10n.translate('meals_total_count', args: {
                    'count': l10n.number(totals[m.email] ?? 0),
                  }),
                ),
              if (totals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.translate('meals_none_logged'),
                      style: TextStyle(
                          color: context.forest.text54, fontSize: 12)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _section(
          l10n.translate('meals_day_log'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in members)
                _dayRow(
                  m,
                  dayLogs[m.email] ?? MealLog(dateKey: dayKey, email: m.email),
                  l10n,
                ),
              if (!_isAdmin)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.translate('meals_read_only'),
                      style: TextStyle(
                          color: context.forest.text54, fontSize: 12)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(l10n.translate('meals_split_hint'),
            style: TextStyle(color: context.forest.text54, fontSize: 12)),
      ],
    );
  }

  Widget _monthBar(AppLocalizations l10n) {
    return Row(
      children: [
        IconButton(
          tooltip: l10n.translate('meals_prev_month'),
          onPressed: () => _moveMonth(-1),
          icon: Icon(Icons.chevron_left_rounded, color: context.forest.text),
        ),
        Expanded(
          child: Text(
            localizedDateFormat('MMMM yyyy').format(_month),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.forest.text,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: l10n.translate('meals_next_month'),
          onPressed: () => _moveMonth(1),
          icon: Icon(Icons.chevron_right_rounded, color: context.forest.text),
        ),
      ],
    );
  }

  Widget _dayStrip() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: mealDaysInMonth(_month),
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = index + 1;
          final selected = day == _day;
          return ChoiceChip(
            label: Text(context.l10n.number(day)),
            selected: selected,
            onSelected: (_) => setState(() => _day = day),
            selectedColor: AppColors.mintGreen,
            backgroundColor: context.forest.surfaceFor(_card),
            labelStyle: TextStyle(
                color: selected
                    ? context.forest.surfaceFor(_bg)
                    : context.forest.text),
          );
        },
      ),
    );
  }

  Widget _dayRow(TourMember m, MealLog log, AppLocalizations l10n) {
    final editable = m.email == _me || _isAdmin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_nameOf(m),
              style: TextStyle(
                  color: context.forest.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _counter(
                  l10n,
                  l10n.translate('meals_breakfast'),
                  log.breakfast,
                  editable,
                  (v) => _save(log.copyWith(breakfast: v)),
                ),
              ),
              Expanded(
                child: _counter(
                  l10n,
                  l10n.translate('meals_lunch'),
                  log.lunch,
                  editable,
                  (v) => _save(log.copyWith(lunch: v)),
                ),
              ),
              Expanded(
                child: _counter(
                  l10n,
                  l10n.translate('meals_dinner'),
                  log.dinner,
                  editable,
                  (v) => _save(log.copyWith(dinner: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _counter(AppLocalizations l10n, String label, int value, bool editable,
      ValueChanged<int> onChanged) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(color: context.forest.text70, fontSize: 12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              color: AppColors.mintGreen,
              onPressed:
                  editable && value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            SizedBox(
              width: 22,
              child: Text(l10n.number(value),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.forest.text, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              color: AppColors.mintGreen,
              onPressed: editable && value < kMaxMealsPerSlot
                  ? () => onChanged(value + 1)
                  : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: context.forest.surfaceFor(_card),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _row(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(name, style: TextStyle(color: context.forest.text))),
          Text(value,
              style: TextStyle(
                  color: context.forest.accentText,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _nameOf(TourMember m) =>
      m.displayName.trim().isNotEmpty ? m.displayName : m.email;

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.forest.text70)),
      ),
    );
  }
}
