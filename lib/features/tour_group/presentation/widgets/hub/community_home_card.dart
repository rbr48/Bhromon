import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/family_task_models.dart';
import '../../../domain/models/service_request_models.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/models/tour_group.dart';
import '../study/study_today_card.dart';

const _card = AppColors.tealPanel;

/// Purpose-driven hero status card for School, Sports, Study, and Neighbourhood Committee presets.
class CommunityHomeCard extends StatefulWidget {
  const CommunityHomeCard({
    super.key,
    required this.group,
    this.repository,
  });

  final TourGroup group;
  final TourGroupRepository? repository;

  @override
  State<CommunityHomeCard> createState() => _CommunityHomeCardState();
}

class _CommunityHomeCardState extends State<CommunityHomeCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _dayTick;

  List<TourNotice> _notices = const [];
  List<FamilyTask> _tasks = const [];
  List<ServiceRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    final id = widget.group.id;
    _subs.addAll([
      _repository
          .watchNotices(id)
          .listen((v) => _update(() => _notices = v), onError: (Object _) {}),
      _repository
          .watchFamilyTasks(id)
          .listen((v) => _update(() => _tasks = v), onError: (Object _) {}),
      if (widget.group.isCommittee)
        _repository.watchServiceRequests(id).listen(
            (v) => _update(() => _requests = v),
            onError: (Object _) {}),
    ]);
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
    final g = widget.group;
    final base = '/group/${g.id}';

    final String title;
    final IconData icon;
    final String action1Label;
    final IconData action1Icon;
    final String action1Route;
    final String action2Label;
    final IconData action2Icon;
    final String action2Route;

    if (g.isSchool) {
      title = l10n.translate('school_home_title');
      icon = Icons.school_outlined;
      action1Label = l10n.translate('office_home_notices_btn');
      action1Icon = Icons.campaign_outlined;
      action1Route = '$base/notices';
      action2Label = l10n.translate('community_home_tasks_btn');
      action2Icon = Icons.checklist_rounded;
      action2Route = '$base/family-tasks';
    } else if (g.isSports) {
      title = l10n.translate('sports_home_title');
      icon = Icons.sports_soccer_rounded;
      action1Label = l10n.translate('office_home_notices_btn');
      action1Icon = Icons.campaign_outlined;
      action1Route = '$base/notices';
      action2Label = l10n.translate('samity_home_fund_btn');
      action2Icon = Icons.account_balance_wallet_outlined;
      action2Route = '$base/ledger';
    } else if (g.isStudy) {
      title = l10n.translate('study_home_title');
      icon = Icons.menu_book_rounded;
      action1Label = l10n.translate('study_home_reading_btn');
      action1Icon = Icons.event_note_rounded;
      action1Route = '$base/study-reading';
      action2Label = l10n.translate('study_home_books_btn');
      action2Icon = Icons.library_books_rounded;
      action2Route = '$base/study-books';
    } else if (g.isFriends) {
      title = l10n.translate('friends_home_title');
      icon = Icons.people_alt_rounded;
      action1Label = l10n.translate('friends_home_hangout_btn');
      action1Icon = Icons.account_balance_wallet_outlined;
      action1Route = '$base/ledger';
      action2Label = l10n.translate('friends_home_plans_btn');
      action2Icon = Icons.checklist_rounded;
      action2Route = '$base/family-tasks';
    } else {
      // isCommittee
      title = l10n.translate('committee_home_title');
      icon = Icons.location_city_rounded;
      action1Label = l10n.translate('society_home_report_btn');
      action1Icon = Icons.add_task_rounded;
      action1Route = '$base/requests';
      action2Label = l10n.translate('society_home_notices_btn');
      action2Icon = Icons.campaign_outlined;
      action2Route = '$base/notices';
    }

    final latestNotice = _notices.isNotEmpty ? _notices.first : null;
    final openRequestsCount = _requests
        .where((r) => r.status != ServiceRequestStatus.resolved)
        .length;
    final openTasksCount = _tasks.where((t) => !t.done).length;

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
              Icon(icon, color: context.forest.accentText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
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
          // Metric Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.forest.inset26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Row(
              children: [
                Icon(
                  g.isCommittee && openRequestsCount > 0
                      ? Icons.build_circle_outlined
                      : Icons.campaign_rounded,
                  size: 20,
                  color: g.isCommittee && openRequestsCount > 0
                      ? AppColors.gold
                      : latestNotice != null
                          ? context.forest.readable(AppColors.freshGreen)
                          : context.forest.text38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.isCommittee && openRequestsCount > 0
                            ? l10n.translate('society_home_requests_open',
                                args: {'count': l10n.number(openRequestsCount)})
                            : latestNotice != null
                                ? latestNotice.title
                                : l10n.translate('office_home_notices_none'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        openTasksCount > 0
                            ? l10n.translate('fh_tasks', args: {
                                'buy': l10n.number(_tasks
                                    .where((t) =>
                                        t.kind == FamilyTaskKind.shopping &&
                                        !t.done)
                                    .length),
                                'todo': l10n.number(_tasks
                                    .where((t) =>
                                        t.kind == FamilyTaskKind.todo &&
                                        !t.done)
                                    .length),
                              })
                            : l10n.translate('fh_tasks_none'),
                        style: TextStyle(
                          color: context.forest.text60,
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
          // Notice row if present
          if (latestNotice != null)
            _row(
              icon: Icons.article_outlined,
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
                  onPressed: () => context.push(action1Route),
                  icon: Icon(action1Icon,
                      size: 14,
                      color: context.forest.readable(AppColors.freshGreen)),
                  label: Text(
                    action1Label,
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
                  onPressed: () => context.push(action2Route),
                  icon: Icon(action2Icon,
                      size: 14,
                      color: context.forest.readable(AppColors.freshGreen)),
                  label: Text(
                    action2Label,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          if (g.isStudy) ...[
            const SizedBox(height: 10),
            StudyGroupTodayCard(tourId: g.id, repository: widget.repository),
          ],
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
