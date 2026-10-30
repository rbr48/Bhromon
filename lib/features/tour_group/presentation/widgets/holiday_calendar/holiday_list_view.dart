import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../domain/models/holiday_models.dart';
import '../../../domain/services/holiday_calendar.dart';
import 'holiday_common.dart';

/// Every holiday of the year, in date order, with its Bangla and Hijri dates.
class HolidayListView extends StatelessWidget {
  const HolidayListView({super.key, required this.calendar});

  final HolidayCalendar calendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.translate('hol_gazette_note'),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final o in calendar.occurrences)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HolidayCard(occurrence: o, calendar: calendar),
          ),
      ],
    );
  }
}

class _HolidayCard extends StatelessWidget {
  const _HolidayCard({required this.occurrence, required this.calendar});

  final HolidayOccurrence occurrence;
  final HolidayCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bengali = holidayIsBengali(context);
    final holiday = occurrence.holiday;
    final date = occurrence.date;
    final color = holidayCategoryColor(holiday.category);
    final bangla = calendar.banglaDate(date);
    final hijri = calendar.hijriDate(date);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kHolidayCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  l10n.number(date.day),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  localizedDateFormat('MMM').format(date),
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holiday.name(bengali: bengali),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    HolidayChip(
                      label:
                          l10n.translate(holidayCategoryKey(holiday.category)),
                      color: color,
                    ),
                    HolidayChip(
                      label: localizedDateFormat('EEEE').format(date),
                      color: Colors.white54,
                    ),
                    if (HolidayCalendar.isWeekend(date))
                      HolidayChip(
                        label: l10n.translate('hol_weekend_overlap'),
                        color: kHolidayRed,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (bangla != null)
                  Text(
                    '${l10n.translate('hol_bangla_date')}: ${banglaDateLabel(context, bangla)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                Text(
                  '${l10n.translate('hol_hijri_date')}: ${hijriDateLabel(context, hijri)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  holiday.description(bengali: bengali),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
