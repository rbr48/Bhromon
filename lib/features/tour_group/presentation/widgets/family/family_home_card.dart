import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/family_date_models.dart';
import '../../../domain/models/family_task_models.dart';
import '../../../domain/models/safety_alert_models.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/models/tour_group.dart';
import '../../../domain/services/family_date_rules.dart';
import '../../../domain/services/family_home_summary.dart';

const _card = Color(0xFF142428);

/// The family's summary at the top of its hub: the next dates, what is still open
/// on the shared list, notices that need an answer, and who has checked in today.
/// Each row opens the screen it summarises.
class FamilyHomeCard extends StatefulWidget {
  const FamilyHomeCard({super.key, required this.tourId});

  final String tourId;

  @override
  State<FamilyHomeCard> createState() => _FamilyHomeCardState();
}

class _FamilyHomeCardState extends State<FamilyHomeCard> {
  final TourGroupRepository _repository = TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _dayTick;

  List<FamilyDate> _dates = const [];
  List<FamilyTask> _tasks = const [];
  List<TourNotice> _notices = const [];
  List<BatteryTelemetry> _telemetry = const [];
  List<TourMember> _members = const [];

  @override
  void initState() {
    super.initState();
    final id = widget.tourId;
    _subs.addAll([
      _repository
          .watchFamilyDates(id)
          .listen((v) => _update(() => _dates = v), onError: (Object _) {}),
      _repository
          .watchFamilyTasks(id)
          .listen((v) => _update(() => _tasks = v), onError: (Object _) {}),
      _repository
          .watchNotices(id)
          .listen((v) => _update(() => _notices = v), onError: (Object _) {}),
      _repository
          .watchBatteryTelemetry(id)
          .listen((v) => _update(() => _telemetry = v), onError: (Object _) {}),
      _repository
          .watchMembers(id)
          .listen((v) => _update(() => _members = v), onError: (Object _) {}),
    ]);
    // Re-check the day every ten minutes, so "today" changes at midnight.
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
    final summary = summarizeFamilyHome(
      dates: _dates,
      tasks: _tasks,
      notices: _notices,
      telemetry: _telemetry,
      members: [
        for (final m in _members)
          if (m.status == TourMemberStatus.active) m,
      ],
      me: _repository.currentEmail,
      now: now,
    );
    final base = '/group/${widget.tourId}';

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_rounded,
                  color: AppColors.mintGreen, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.translate('fh_title'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              Text(localizedDateFormat('EEE, d MMM').format(now),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          _row(
            icon: Icons.event_rounded,
            text: summary.nextDates.isEmpty
                ? l10n.translate('fh_dates_none')
                : _nextDateText(l10n, summary.nextDates.first, now),
            onTap: () => context.push('$base/family-dates'),
          ),
          _row(
            icon: Icons.checklist_rounded,
            text: summary.toBuy + summary.toDo == 0
                ? l10n.translate('fh_tasks_none')
                : l10n.translate('fh_tasks', args: {
                    'buy': l10n.number(summary.toBuy),
                    'todo': l10n.number(summary.toDo),
                  }),
            onTap: () => context.push('$base/family-tasks'),
          ),
          _row(
            icon: Icons.push_pin_outlined,
            text: summary.needMyReply > 0
                ? l10n.translate('fh_reply_needed',
                    args: {'count': l10n.number(summary.needMyReply)})
                : summary.latestNotice != null
                    ? l10n.translate('fh_notice_latest',
                        args: {'title': summary.latestNotice!.title})
                    : l10n.translate('fh_notices_none'),
            onTap: () => context.push('$base/notices'),
          ),
          _row(
            icon: Icons.shield_outlined,
            text: summary.checkedInToday == 0
                ? l10n.translate('fh_checkins_none')
                : l10n.translate('fh_checkins', args: {
                    'done': l10n.number(summary.checkedInToday),
                    'total': l10n.number(summary.activeMembers),
                  }),
            onTap: () => context.push('$base/safety'),
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
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white60, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  String _nextDateText(AppLocalizations l10n, FamilyDate date, DateTime now) {
    final today = FamilyDateRules.dateOnly(now);
    final due = FamilyDateRules.nextDue(date, today);
    final days = FamilyDateRules.daysBetween(today, due);
    final when = days == 0
        ? l10n.translate('fd_when_today')
        : days == 1
            ? l10n.translate('fd_when_tomorrow')
            : l10n.translate('fd_when_in_days',
                args: {'days': l10n.number(days)});
    return l10n
        .translate('fh_dates_next', args: {'title': date.title, 'when': when});
  }
}
