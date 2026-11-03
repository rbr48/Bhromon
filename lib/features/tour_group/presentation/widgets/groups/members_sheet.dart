import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';

import 'member_avatar.dart';

/// Opens the members sheet: every active member, owners and admins first. Admins see
/// each member's email and can open that member's manage sheet; other members see
/// roles only (decision D-4). [onAddMember] is shown to admins only.
Future<void> showMembersSheet(
  BuildContext context, {
  required Stream<List<TourMember>> members,
  required bool viewerIsAdmin,
  required void Function(TourMember member) onMemberTap,
  VoidCallback? onAddMember,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.forest.card,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.8,
        child: StreamBuilder<List<TourMember>>(
          stream: members,
          builder: (context, snapshot) {
            final l10n = context.l10n;
            final list = snapshot.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          list == null
                              ? l10n.translate('group_members_title_loading')
                              : l10n.translate('group_members_title', args: {
                                  'count': l10n.number(list.length),
                                }),
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.translate('group_close'),
                        icon: Icon(Icons.close_rounded,
                            color: context.forest.text70),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: list == null
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.midGreen),
                        )
                      : list.isEmpty
                          ? Center(
                              child: Text(
                                l10n.translate('group_members_none'),
                                style: TextStyle(color: context.forest.text70),
                              ),
                            )
                          : ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (_, __) => Divider(
                                  height: 1, color: context.forest.divider10),
                              itemBuilder: (context, index) {
                                final member = list[index];
                                final roleText = member.role == TourRole.owner
                                    ? l10n.translate('group_role_owner')
                                    : member.role.isAdminOrOwner
                                        ? l10n.translate('hub_role_admin')
                                        : l10n.translate('hub_role_member');
                                return ListTile(
                                  onTap: () => onMemberTap(member),
                                  leading: MemberAvatar(
                                    name: member.displayName,
                                    photoUrl: member.photoUrl,
                                    size: 44,
                                  ),
                                  title: Text(member.displayName,
                                      style: TextStyle(
                                          color: context.forest.text,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    viewerIsAdmin ? member.email : roleText,
                                    style: TextStyle(
                                        color: context.forest.text54,
                                        fontSize: 12),
                                  ),
                                  trailing: Text(
                                    roleText,
                                    style: TextStyle(
                                        color: context.forest.text70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                );
                              },
                            ),
                ),
                if (viewerIsAdmin && onAddMember != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.mintGreen,
                          foregroundColor: AppColors.darkGreen,
                        ),
                        onPressed: onAddMember,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(l10n.translate('hub_add_member_title')),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
