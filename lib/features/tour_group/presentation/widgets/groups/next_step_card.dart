import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:flutter/material.dart';

/// The next step on a group page, when the group has one: for a trip that has not
/// started, the days left until it does. Family circles and trips that have started show
/// nothing here (section 5.1, B2).
class NextStepCard extends StatelessWidget {
  const NextStepCard({super.key, required this.group, required this.now});

  final TourGroup group;
  final DateTime now;

  /// Whole days from [now] to the trip's start, or null when there is no next step.
  static int? daysUntilStart(TourGroup group, DateTime now) {
    if (group.isFamily) return null;
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
        group.startDate.year, group.startDate.month, group.startDate.day);
    final days = start.difference(today).inDays;
    return days > 0 ? days : null;
  }

  @override
  Widget build(BuildContext context) {
    final days = daysUntilStart(group, now);
    if (days == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mintGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, color: context.forest.accentText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.translate('group_next_trip', args: {
                'days': l10n.number(days),
              }),
              style: TextStyle(
                color: context.forest.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
