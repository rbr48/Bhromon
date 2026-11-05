import 'dart:async';

import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../data/tour_group_repository.dart';
import '../../../domain/models/tour_activity_models.dart';
import '../../../domain/models/tour_group.dart';

const _card = Color(0xFF142428);

/// Purpose-driven hero status card for a Campus / Class / Batch / Club circle.
/// Displays batch announcements, event notices, adda/snacks split shortcuts.
class CampusHomeCard extends StatefulWidget {
  const CampusHomeCard({
    super.key,
    required this.group,
    this.repository,
  });

  final TourGroup group;
  final TourGroupRepository? repository;

  @override
  State<CampusHomeCard> createState() => _CampusHomeCardState();
}

class _CampusHomeCardState extends State<CampusHomeCard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _dayTick;

  List<TourNotice> _notices = const [];
  List<TourMember> _members = const [];

  @override
  void initState() {
    super.initState();
    final id = widget.group.id;
    try {
      _subs.add(_repository
          .watchNotices(id)
          .listen((v) => _update(() => _notices = v), onError: (Object _) {}));
    } catch (_) {}
    try {
      _subs.add(_repository
          .watchMembers(id)
          .listen((v) => _update(() => _members = v), onError: (Object _) {}));
    } catch (_) {}
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
    final latestNotice = _notices.isNotEmpty ? _notices.first : null;
    final base = '/group/${widget.group.id}';
    final activeMembersCount =
        _members.where((m) => m.status == TourMemberStatus.active).length;

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
              Icon(Icons.school_rounded,
                  color: context.forest.accentText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('campus_home_title'),
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
          // Latest batch announcement banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.forest.inset26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.forest.divider10),
            ),
            child: Row(
              children: [
                Icon(Icons.forum_outlined,
                    size: 20,
                    color: latestNotice != null
                        ? context.forest.readable(const Color(0xFF52B788))
                        : context.forest.text38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latestNotice != null
                            ? latestNotice.title
                            : l10n.translate('campus_home_notices_none'),
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
                        activeMembersCount > 0
                            ? context.l10n.translate('hub_members_count',
                                args: {
                                    'count': l10n.number(activeMembersCount)
                                  })
                            : l10n.translate('fh_notices_none'),
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
                  onPressed: () => context
                      .push('$base/ledger/add?title=Adda&category=Snacks'),
                  icon: Icon(Icons.coffee_outlined,
                      size: 14,
                      color: context.forest.readable(const Color(0xFF52B788))),
                  label: Text(
                    l10n.translate('campus_home_snacks_btn'),
                    style: const TextStyle(fontSize: 11),
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
                      color: context.forest.readable(const Color(0xFF52B788))),
                  label: Text(
                    l10n.translate('campus_home_notices_btn'),
                    style: const TextStyle(fontSize: 11),
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
      borderRadius: BorderRadius.circular(10),
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
