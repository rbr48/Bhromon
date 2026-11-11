import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_avatar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_type.dart';
import 'package:flutter/material.dart';

/// One group on the groups list (B1). When collapsed, only the photo, name and badges
/// show. When tapped, it smoothly expands inline to show the group actions, member strip,
/// next step, SOS siren, and tools grid without navigating to a new page.
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.selected,
    required this.onTap,
    this.roleLabel,
    this.members,
    this.isExpanded = false,
    this.expandedContent,
  });

  final TourGroup group;
  final bool selected;
  final VoidCallback onTap;

  /// The viewer's role in this group, when known.
  final String? roleLabel;

  /// The member strip, for the selected card only.
  final Widget? members;

  /// Whether the card is expanded inline showing full group details.
  final bool isExpanded;

  /// The expanded details body (quick actions, members strip, next step, SOS, tools grid).
  final Widget? expandedContent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The type's own name: a housing society says so, not "Family circles".
    final kind = l10n.translate(groupTypeKey(group));
    final isHighlighted = isExpanded;
    return Semantics(
      button: true,
      selected: selected,
      expanded: isExpanded,
      label: group.name,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: context.forest.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isHighlighted ? AppColors.midGreen : context.forest.divider10,
              width: isHighlighted ? 2 : 1,
            ),
            boxShadow: isExpanded
                ? [
                    BoxShadow(
                      color: AppColors.midGreen.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      GroupAvatar(
                        typeIcon: groupTypeIcon(group),
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
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                Text(
                                  kind,
                                  style: TextStyle(
                                    color: context.forest.text54,
                                    fontSize: 12,
                                  ),
                                ),
                                if (selected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.mintGreen
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      l10n.translate('group_active_badge'),
                                      style: const TextStyle(
                                        color: AppColors.mintGreen,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (roleLabel != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.forest.divider10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            roleLabel!,
                            style: TextStyle(
                              color: context.forest.text70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 26,
                          color: isHighlighted
                              ? AppColors.mintGreen
                              : context.forest.text54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: isExpanded && expandedContent != null
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(height: 1, color: context.forest.divider10),
                            const SizedBox(height: 14),
                            expandedContent!,
                          ],
                        ),
                      )
                    : (selected && members != null
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: members!,
                          )
                        : const SizedBox.shrink()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
