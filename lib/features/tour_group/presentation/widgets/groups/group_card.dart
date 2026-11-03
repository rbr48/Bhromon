import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_avatar.dart';
import 'package:flutter/material.dart';

/// One group on the groups list (B1). Its photo and name always show. The member strip
/// is passed only for the selected card, so no other card needs a listener (D-10).
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.selected,
    required this.onTap,
    this.roleLabel,
    this.members,
  });

  final TourGroup group;
  final bool selected;
  final VoidCallback onTap;

  /// The viewer's role in this group, when known.
  final String? roleLabel;

  /// The member strip, for the selected card only.
  final Widget? members;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = group.isFamily
        ? l10n.translate('hub_section_family')
        : l10n.translate('hub_section_trips');
    // The labelled node is the one that acts, so a screen reader's tap on the name
    // opens the group.
    return Semantics(
      button: true,
      selected: selected,
      label: group.name,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.forest.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.midGreen : context.forest.divider10,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GroupAvatar(
                      isFamily: group.isFamily,
                      photoUrl: group.photoUrl,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            kind,
                            style: TextStyle(
                              color: context.forest.text54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (roleLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.forest.divider10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          roleLabel!,
                          style: TextStyle(
                            color: context.forest.text70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (selected && members != null) ...[
                  const SizedBox(height: 12),
                  members!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
