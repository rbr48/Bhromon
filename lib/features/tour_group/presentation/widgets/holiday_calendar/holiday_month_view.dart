import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/services/holiday_calendar.dart';
import 'holiday_common.dart';

/// One month as a Sunday-first grid. Holidays are tinted, weekends are muted,
/// trip days have a green edge and the selected day is filled.
class HolidayMonthView extends StatelessWidget {
  const HolidayMonthView({
    super.key,
    required this.calendar,
    required this.month,
    required this.trip,
    required this.selected,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  final HolidayCalendar calendar;
  final int month;
  final TripSummary? trip;
  final DateTime? selected;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = calendar.daysInMonth(month);
    final offset = DateTime(calendar.year, month, 1).weekday % 7;
    final cellCount = ((offset + count + 6) ~/ 7) * 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.translate('hol_prev_month'),
              onPressed: month > 1 ? () => onMonthChanged(month - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            ),
            Expanded(
              child: Text(
                localizedDateFormat('MMMM yyyy')
                    .format(DateTime(calendar.year, month)),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.translate('hol_next_month'),
              onPressed: month < 12 ? () => onMonthChanged(month + 1) : null,
              icon:
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ),
          ],
        ),
        Row(
          children: [
            for (final key in kHolidayWeekdayKeys)
              Expanded(
                child: Text(
                  l10n.translate(key),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: key == 'hol_wd_fri' || key == 'hol_wd_sat'
                        ? kHolidayRed.withValues(alpha: 0.8)
                        : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < cellCount; i++)
              _cell(context, i - offset + 1, count),
          ],
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, int day, int count) {
    if (day < 1 || day > count) return const SizedBox.shrink();
    final date = DateTime(calendar.year, month, day);
    final isSelected =
        selected != null && HolidayCalendar.dateOnly(selected!) == date;
    return _HolidayDayCell(
      date: date,
      isWeekend: HolidayCalendar.isWeekend(date),
      isHoliday: calendar.holidaysOn(date).isNotEmpty,
      inTrip: trip?.contains(date) ?? false,
      isSelected: isSelected,
      onTap: () => onDayTap(date),
    );
  }
}

class _HolidayDayCell extends StatelessWidget {
  const _HolidayDayCell({
    required this.date,
    required this.isWeekend,
    required this.isHoliday,
    required this.inTrip,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isWeekend;
  final bool isHoliday;
  final bool inTrip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? Colors.black
        : isHoliday
            ? kHolidayRed
            : isWeekend
                ? Colors.white38
                : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.mintGreen
              : isHoliday
                  ? kHolidayRed.withValues(alpha: 0.16)
                  : null,
          borderRadius: BorderRadius.circular(8),
          border: inTrip
              ? Border.all(color: AppColors.mintGreen, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10n.number(date.day),
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight:
                    isHoliday || isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (isHoliday)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : kHolidayRed,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// All twelve months at a glance. Tapping a month opens it in the month view.
class HolidayYearView extends StatelessWidget {
  const HolidayYearView({
    super.key,
    required this.calendar,
    required this.trip,
    required this.onMonthTap,
  });

  final HolidayCalendar calendar;
  final TripSummary? trip;
  final ValueChanged<int> onMonthTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: [
        for (var month = 1; month <= 12; month++)
          _MiniMonth(
            calendar: calendar,
            month: month,
            trip: trip,
            onTap: () => onMonthTap(month),
          ),
      ],
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.calendar,
    required this.month,
    required this.trip,
    required this.onTap,
  });

  final HolidayCalendar calendar;
  final int month;
  final TripSummary? trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = calendar.daysInMonth(month);
    final offset = DateTime(calendar.year, month, 1).weekday % 7;
    final cellCount = ((offset + count + 6) ~/ 7) * 7;
    final stats = calendar.monthStats(month);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kHolidayCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizedDateFormat('MMMM')
                  .format(DateTime(calendar.year, month)),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${context.l10n.number(stats.netWorkdays)} / ${context.l10n.number(stats.totalDays)}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: GridView.count(
                crossAxisCount: 7,
                mainAxisSpacing: 1,
                crossAxisSpacing: 1,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < cellCount; i++)
                    _miniCell(context, i - offset + 1, count),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniCell(BuildContext context, int day, int count) {
    if (day < 1 || day > count) return const SizedBox.shrink();
    final date = DateTime(calendar.year, month, day);
    final isHoliday = calendar.holidaysOn(date).isNotEmpty;
    final inTrip = trip?.contains(date) ?? false;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isHoliday ? kHolidayRed.withValues(alpha: 0.25) : null,
        borderRadius: BorderRadius.circular(3),
        border: inTrip ? Border.all(color: AppColors.mintGreen) : null,
      ),
      child: Text(
        context.l10n.number(day),
        style: TextStyle(
          color: isHoliday
              ? kHolidayRed
              : HolidayCalendar.isWeekend(date)
                  ? Colors.white38
                  : Colors.white70,
          fontSize: 8.5,
          fontWeight: isHoliday ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
