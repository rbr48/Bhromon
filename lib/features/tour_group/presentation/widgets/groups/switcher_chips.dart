import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';

/// The groups as chips, in two sections: family circles, then trips. The selected group
/// is marked, as on the groups list (decision D-5).
class SwitcherChips extends StatelessWidget {
  const SwitcherChips({
    super.key,
    required this.groups,
    required this.selectedId,
    required this.onSelected,
  });

  final List<TourGroup> groups;
  final String? selectedId;
  final ValueChanged<TourGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final families = groups.where((g) => g.isFamily).toList();
    final trips = groups.where((g) => !g.isFamily).toList();

    Widget section(String title, List<TourGroup> items) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Text(
              title,
              style: TextStyle(
                color: context.forest.text54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final group in items)
                ChoiceChip(
                  label: Text(group.name),
                  selected: group.id == selectedId,
                  selectedColor: AppColors.mintGreen,
                  labelStyle: TextStyle(
                    color: group.id == selectedId
                        ? AppColors.darkGreen
                        : context.forest.text,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => onSelected(group),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (families.isNotEmpty)
          section(l10n.translate('hub_section_family'), families),
        if (trips.isNotEmpty)
          section(l10n.translate('hub_section_trips'), trips),
      ],
    );
  }
}
