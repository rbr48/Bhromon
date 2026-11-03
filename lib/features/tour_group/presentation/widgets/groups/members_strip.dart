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
    final stackWidth =
        shown.isEmpty ? 0.0 : avatarSize + (shown.length - 1) * _step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A wrap moves "See all" to a second line when the faces and the text do not fit side by side.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: stackWidth + (extra > 0 ? avatarSize + 4 : 0),
              height: avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * _step,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: context.forest.card, width: 2),
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
                      left: shown.length * _step,
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
            TextButton(
              onPressed: onSeeAll,
              child: Text(l10n.translate('group_members_see_all')),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
