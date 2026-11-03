import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';

import 'member_avatar.dart';

/// The members of a group at a glance: up to [maxAvatars] faces, "+N" for the rest, the
/// number in each role, and a button to see them all (page B2, decision D-2).
class MembersStrip extends StatelessWidget {
  const MembersStrip({
    super.key,
    required this.members,
    required this.onSeeAll,
    this.maxAvatars = 8,
  });

  final List<TourMember> members;
  final VoidCallback onSeeAll;
  final int maxAvatars;

  static const double avatarSize = 40;
  static const double _step = 28;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shown = members.take(maxAvatars).toList();
    final extra = members.length - shown.length;
    final owners = members.where((m) => m.role == TourRole.owner).length;
    final admins = members.where((m) => m.role == TourRole.admin).length;
    final plain = members.where((m) => m.role == TourRole.member).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.forest.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.forest.divider10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final count = shown.length + (extra > 0 ? 1 : 0);
          final dynamicStep = count > 1
              ? ((maxW - avatarSize) / (count - 1)).clamp(12.0, _step)
              : _step;
          final actualStackWidth =
              shown.isEmpty ? 0.0 : avatarSize + (count - 1) * dynamicStep;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_alt_rounded,
                          size: 18, color: context.forest.accentText),
                      const SizedBox(width: 6),
                      Text(
                        l10n.translate('group_members_title_loading'),
                        style: TextStyle(
                          color: context.forest.text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.forest.text.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.number(members.length),
                          style: TextStyle(
                            color: context.forest.accentText,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    onPressed: onSeeAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.translate('group_members_see_all')),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: actualStackWidth.clamp(0.0, maxW),
                height: avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * dynamicStep,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: context.forest.card, width: 2),
                          ),
                          child: MemberAvatar(
                            name: shown[i].displayName,
                            photoUrl: shown[i].photoUrl,
                            size: avatarSize,
                          ),
                        ),
                      ),
                    if (extra > 0)
                      Positioned(
                        left: shown.length * dynamicStep,
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.forest.divider10,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '+${l10n.number(extra)}',
                            style: TextStyle(
                              color: context.forest.text70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  RoleCountChip(
                      label: l10n.translate('group_role_owner'), count: owners),
                  RoleCountChip(
                      label: l10n.translate('hub_role_admin'), count: admins),
                  RoleCountChip(
                      label: l10n.translate('hub_role_member'), count: plain),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A role and how many members hold it.
class RoleCountChip extends StatelessWidget {
  const RoleCountChip({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.forest.divider10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label · ${context.l10n.number(count)}',
        style: TextStyle(
          color: context.forest.text70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
