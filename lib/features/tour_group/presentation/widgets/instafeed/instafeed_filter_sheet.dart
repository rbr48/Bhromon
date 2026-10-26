import 'package:flutter/material.dart';

import '../../../../../core/theme/colors.dart';
import '../../../domain/models/tour_group.dart';
import '../../../../../core/localization/app_localizations.dart';

/// The media filters the feed offers, in display order. The ids are the values
/// the feed filters on.
List<({String id, String label})> instafeedMediaFilters(BuildContext context) =>
    [
      (id: 'all', label: context.l10n.translate('ig_filter_all')),
      (id: 'photos', label: context.l10n.translate('ig_filter_photos')),
      (id: 'reels', label: context.l10n.translate('ig_filter_reels')),
      (id: 'saved', label: context.l10n.translate('ig_filter_saved')),
      (id: 'archived', label: context.l10n.translate('ig_filter_archived')),
    ];

/// One pill in the feed header that shows the active media and day filters.
/// Tapping it opens [InstafeedFilterSheet].
class InstafeedFilterBar extends StatelessWidget {
  const InstafeedFilterBar({
    super.key,
    required this.summary,
    required this.onTap,
  });

  /// The active filters, for example "সবগুলো (All) · সব দিন".
  final String summary;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: context.l10n
              .translate('ig_filter_summary', args: {'summary': summary}),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.mintGreen.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune_rounded,
                        size: 16, color: AppColors.mintGreen),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        summary,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded,
                        size: 18, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The filter choices: one row of media filters, and the tour days when the
/// tour has any. Each choice is reported at once; the caller updates the feed.
class InstafeedFilterSheet extends StatelessWidget {
  const InstafeedFilterSheet({
    super.key,
    required this.selectedMedia,
    required this.onMediaSelected,
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final String selectedMedia;
  final ValueChanged<String> onMediaSelected;

  final List<TourDayInfo> days;

  /// The selected day's id, or `all` for every day.
  final String selectedDay;
  final ValueChanged<String> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.translate('ig_filter_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in instafeedMediaFilters(context))
                  _choice(
                    label: option.label,
                    selected: option.id == selectedMedia,
                    onTap: () => onMediaSelected(option.id),
                  ),
              ],
            ),
            if (days.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                context.l10n.translate('ig_day'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _choice(
                    label: context.l10n.translate('ig_all_days'),
                    selected: selectedDay == 'all',
                    onTap: () => onDaySelected('all'),
                  ),
                  for (final day in days)
                    _choice(
                      label: day.label,
                      selected: selectedDay == day.id,
                      onTap: () => onDaySelected(day.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.mintGreen,
      backgroundColor: const Color(0xFF2A2A2A),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white70,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) => onTap(),
    );
  }
}
