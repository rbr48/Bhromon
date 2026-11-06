import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';

import 'member_avatar.dart';

/// The members of a group at a glance: avatars shown side by side in a swipeable row,
/// tapping an avatar views their details/photo, with "+N" for the rest, the number in each
/// role, and a top corner button to see them all (page B2, decision D-2).
class MembersStrip extends StatelessWidget {
  const MembersStrip({
    super.key,
    required this.members,
    required this.onSeeAll,
    this.onMemberTap,
    this.maxAvatars = 8,
  });

  final List<TourMember> members;
  final VoidCallback onSeeAll;
  final void Function(TourMember member)? onMemberTap;
  final int maxAvatars;

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
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final rowHeight = (50.0 + 26.0 * textScale).clamp(76.0, 110.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top header row: Title + count badge on left, top-corner icon to open list on right
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_alt_rounded,
                            size: 18, color: context.forest.accentText),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l10n.translate('group_members_title_loading'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.forest.text,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
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
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: onSeeAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                l10n.translate('group_members_see_all'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.forest.accentText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                              color: context.forest.accentText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Avatars row: displayed side by side, swipeable if many members
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l10n.translate('group_members_none'),
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 13),
                  ),
                )
              else
                SizedBox(
                  height: rowHeight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        for (final member in shown)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _buildMemberItem(context, member, l10n),
                          ),
                        if (extra > 0) _buildExtraItem(context, extra, l10n),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),

              // Role summary pills
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (owners > 0)
                    RoleCountChip(
                        label: l10n.translate('group_role_owner'),
                        count: owners),
                  if (admins > 0)
                    RoleCountChip(
                        label: l10n.translate('hub_role_admin'), count: admins),
                  if (plain > 0 || (owners == 0 && admins == 0))
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

  Widget _buildMemberItem(
    BuildContext context,
    TourMember member,
    AppLocalizations l10n,
  ) {
    final isOwner = member.role == TourRole.owner;
    final isAdmin = member.role == TourRole.admin;
    final firstName = member.displayName.trim().split(' ').first;
    return Semantics(
      button: true,
      label: member.displayName,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onMemberTap != null ? onMemberTap!(member) : onSeeAll(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isOwner
                            ? AppColors.gold
                            : isAdmin
                                ? AppColors.mintGreen
                                : context.forest.divider10,
                        width: isOwner || isAdmin ? 2 : 1.5,
                      ),
                    ),
                    child: MemberAvatar(
                      name: member.displayName,
                      photoUrl: member.photoUrl,
                      size: 42,
                    ),
                  ),
                  if (isOwner)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else if (isAdmin)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.midGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 52,
                child: Text(
                  firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.forest.text70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExtraItem(
    BuildContext context,
    int extra,
    AppLocalizations l10n,
  ) {
    return Semantics(
      button: true,
      label: l10n.translate('group_members_see_all'),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSeeAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.forest.divider10,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.forest.divider10,
                    width: 1.5,
                  ),
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
              const SizedBox(height: 4),
              SizedBox(
                width: 52,
                child: Text(
                  l10n.translate('group_members_see_all'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.forest.text54,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
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
