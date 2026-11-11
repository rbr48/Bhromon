import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/family_task_models.dart';
import '../../../domain/models/meal_log.dart';
import '../../../domain/models/mess_bazar_model.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/meal_engine.dart';
import '../mess/mess_bazar_sheet.dart';

const _card = AppColors.tealPanel;

/// Purpose-driven hero status card for a Mess / Shared Home.
/// Displays today's meal counts, the member's own meal status, bazar tasks, and quick actions.
class MessHomeCard extends StatefulWidget {
  const MessHomeCard({
    super.key,
    required this.group,
    this.repository,
  });

  final TourGroup group;
  final TourGroupRepository? repository;

  @override
  State<MessHomeCard> createState() => _MessHomeCardState();
}

class _MessHomeCardState extends State<MessHomeCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _dayTick;

  List<MealLog> _meals = const [];
  List<FamilyTask> _tasks = const [];
  List<TourNotice> _notices = const [];
  List<TourMember> _members = const [];
  MessBazarSchedule? _todayBazar;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    final id = widget.group.id;
    final now = DateTime.now();
    final todayKey = mealDateKey(now);
    _subs.addAll([
      _repository
          .watchMealsForMonth(id, now)
          .listen((v) => _update(() => _meals = v), onError: (Object _) {}),
      _repository
          .watchFamilyTasks(id)
          .listen((v) => _update(() => _tasks = v), onError: (Object _) {}),
      _repository
          .watchNotices(id)
          .listen((v) => _update(() => _notices = v), onError: (Object _) {}),
      _repository
          .watchMembers(id)
          .listen((v) => _update(() => _members = v), onError: (Object _) {}),
      _repository.watchBazarScheduleForDay(id, todayKey).listen(
          (v) => _update(() => _todayBazar = v),
          onError: (Object _) {}),
    ]);
    _repository.myRole(id).then((r) {
      if (mounted) setState(() => _isAdmin = r?.isAdminOrOwner ?? false);
    }, onError: (Object _) {});
    _dayTick = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _dayTick?.cancel();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final todayKey = mealDateKey(now);
    final myEmail = _repository.currentEmail.toLowerCase().trim();

    final todayLogs = _meals.where((m) => m.dateKey == todayKey).toList();
    var bTotal = 0;
    var lTotal = 0;
    var dTotal = 0;
    MealLog? myLog;

    for (final log in todayLogs) {
      bTotal += log.breakfast;
      lTotal += log.lunch;
      dTotal += log.dinner;
      if (log.email.toLowerCase().trim() == myEmail) {
        myLog = log;
      }
    }

    final toBuy = _tasks
        .where((t) => t.kind == FamilyTaskKind.shopping && !t.done)
        .length;
    final latestNotice = _notices.isNotEmpty ? _notices.first : null;
    final base = '/group/${widget.group.id}';

    return Container(
      decoration: BoxDecoration(
        color: context.forest.surfaceFor(_card),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_rounded,
                  color: context.forest.accentText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('mess_home_title'),
                  style: TextStyle(
                    color: context.forest.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                localizedDateFormat('EEE, d MMM').format(now),
                style: TextStyle(color: context.forest.text54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Today's meal metrics pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.forest.inset26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (bTotal + lTotal + dTotal > 0)
                            ? l10n.translate('mess_home_today_meals', args: {
                                'breakfast': l10n.number(bTotal),
                                'lunch': l10n.number(lTotal),
                                'dinner': l10n.number(dTotal),
                              })
                            : l10n.translate('mess_home_no_meals'),
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        myLog != null
                            ? l10n.translate('mess_home_my_meals', args: {
                                'breakfast': l10n.number(myLog.breakfast),
                                'lunch': l10n.number(myLog.lunch),
                                'dinner': l10n.number(myLog.dinner),
                              })
                            : l10n.translate('mess_home_my_meals_none'),
                        style: TextStyle(
                          color: myLog != null
                              ? context.forest.accentText
                              : AppColors.gold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Bazar duty row
          _row(
            icon: Icons.storefront_rounded,
            text: (_todayBazar != null && _todayBazar!.assignedNames.isNotEmpty)
                ? l10n.translate('mess_bazar_today_duty',
                    args: {'names': _todayBazar!.assignedNames.join(', ')})
                : l10n.translate('mess_bazar_no_duty'),
            onTap: () => showMessBazarSheet(
              context,
              tourId: widget.group.id,
              isAdmin: _isAdmin,
              members: _members,
              initialDateKey: todayKey,
            ),
          ),
          // Bazar tasks row
          _row(
            icon: Icons.shopping_basket_outlined,
            text: toBuy > 0
                ? l10n.translate('mess_home_bazar_tasks',
                    args: {'count': l10n.number(toBuy)})
                : l10n.translate('mess_home_bazar_empty'),
            onTap: () => context.push('$base/family-tasks'),
          ),
          // Notice row if present
          if (latestNotice != null)
            _row(
              icon: Icons.campaign_outlined,
              text: l10n.translate('fh_notice_latest',
                  args: {'title': latestNotice.title}),
              onTap: () => context.push('$base/notices'),
            ),
          const SizedBox(height: 8),
          // Quick actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: AppColors.mintGreen.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => context.push('$base/meals'),
                  icon: Icon(Icons.edit_calendar_rounded,
                      size: 14,
                      color: context.forest.readable(AppColors.freshGreen)),
                  label: Text(
                    l10n.translate('mess_home_log_meals_btn'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: AppColors.mintGreen.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => showMessBazarSheet(
                    context,
                    tourId: widget.group.id,
                    isAdmin: _isAdmin,
                    members: _members,
                    initialDateKey: todayKey,
                  ),
                  icon: Icon(Icons.storefront_rounded,
                      size: 14,
                      color: context.forest.readable(AppColors.freshGreen)),
                  label: Text(
                    l10n.translate('mess_bazar_routine_btn'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: context.forest.text60, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.forest.text70, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.forest.text38, size: 16),
          ],
        ),
      ),
    );
  }
}
