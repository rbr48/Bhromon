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

const _card = AppColors.tealPanel;

/// Purpose-driven hero status card for a Housing Society / Apartment Building.
/// Displays open service requests, maintenance status, building notices, and one-tap actions.
class SocietyHomeCard extends StatefulWidget {
  const SocietyHomeCard({
    super.key,
    required this.group,
    this.repository,
  });

  final TourGroup group;
  final TourGroupRepository? repository;

  @override
  State<SocietyHomeCard> createState() => _SocietyHomeCardState();
}

class _SocietyHomeCardState extends State<SocietyHomeCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _dayTick;

  List<ServiceRequest> _requests = const [];
  List<TourNotice> _notices = const [];
  List<FamilyTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    final id = widget.group.id;
    _subs.addAll([
      _repository
          .watchServiceRequests(id)
          .listen((v) => _update(() => _requests = v), onError: (Object _) {}),
      _repository
          .watchNotices(id)
          .listen((v) => _update(() => _notices = v), onError: (Object _) {}),
      _repository
          .watchFamilyTasks(id)
          .listen((v) => _update(() => _tasks = v), onError: (Object _) {}),
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

    final activeRequests = _requests
        .where((r) => r.status != ServiceRequestStatus.resolved)
        .toList();
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
              Icon(Icons.apartment_rounded,
                  color: context.forest.accentText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('society_home_title'),
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
          // Service request status banner
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
                  activeRequests.isNotEmpty
                      ? Icons.build_circle_outlined
                      : Icons.verified_outlined,
                  size: 20,
                  color: activeRequests.isNotEmpty
                      ? AppColors.gold
                      : context.forest.readable(AppColors.freshGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeRequests.isNotEmpty
                            ? l10n.translate('society_home_requests_open',
                                args: {
                                    'count': l10n.number(activeRequests.length)
                                  })
                            : l10n.translate('society_home_requests_all_good'),
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (activeRequests.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          activeRequests.first.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Latest building notice row
          if (latestNotice != null)
            _row(
              icon: Icons.campaign_outlined,
              text: l10n.translate('fh_notice_latest',
                  args: {'title': latestNotice.title}),
              onTap: () => context.push('$base/notices'),
            ),
          // Upkeep tasks row if any open
          if (_tasks.where((t) => !t.done).isNotEmpty)
            _row(
              icon: Icons.checklist_rounded,
              text: l10n.translate('fh_tasks', args: {
                'buy': l10n.number(_tasks
                    .where((t) => t.kind == FamilyTaskKind.shopping && !t.done)
                    .length),
                'todo': l10n.number(_tasks
                    .where((t) => t.kind == FamilyTaskKind.todo && !t.done)
                    .length),
              }),
              onTap: () => context.push('$base/family-tasks'),
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
                  onPressed: () => context.push('$base/requests'),
                  icon: Icon(Icons.add_task_rounded,
                      size: 14,
                      color: context.forest.readable(AppColors.freshGreen)),
                  label: Text(
                    l10n.translate('society_home_report_btn'),
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
                  onPressed: () => context.push('$base/notices'),
                  icon: Icon(Icons.campaign_outlined,
                      size: 14,
                      color: context.forest.readable(AppColors.freshGreen)),
                  label: Text(
                    l10n.translate('society_home_notices_btn'),
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
