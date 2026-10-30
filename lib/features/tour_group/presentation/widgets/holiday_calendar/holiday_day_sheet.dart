import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/services/holiday_calendar.dart';
import '../../../domain/services/holiday_export.dart';
import 'holiday_common.dart';

/// Opens the details of one day: its holidays, the Bangla and Hijri dates, and
/// what a leave day would give.
Future<void> showHolidayDaySheet(
  BuildContext context, {
  required HolidayCalendar calendar,
  required DateTime date,
  required bool inTrip,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kHolidayCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HolidayDaySheet(
      calendar: calendar,
      date: date,
      inTrip: inTrip,
    ),
  );
}

class _HolidayDaySheet extends StatelessWidget {
  const _HolidayDaySheet({
    required this.calendar,
    required this.date,
    required this.inTrip,
  });

  final HolidayCalendar calendar;
  final DateTime date;
  final bool inTrip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bengali = holidayIsBengali(context);
    final holidays = calendar.holidaysOn(date);
    final weekend = HolidayCalendar.isWeekend(date);
    final bangla = calendar.banglaDate(date);
    final hijri = calendar.hijriDate(date);
    final leave = calendar.isOff(date) ? null : calendar.leaveRangeFor(date);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${localizedDateFormat('EEEE').format(date)}, ${holidayDateLabel(context, date)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (inTrip)
                  HolidayChip(
                    label: l10n.translate('hol_in_trip'),
                    color: AppColors.mintGreen,
                  ),
                if (weekend)
                  HolidayChip(
                    label: l10n.translate('hol_status_weekend'),
                    color: Colors.white54,
                  ),
                if (!weekend && holidays.isEmpty)
                  HolidayChip(
                    label: l10n.translate('hol_status_workday'),
                    color: Colors.white54,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (holidays.isEmpty)
              Text(
                l10n.translate('hol_no_holiday'),
                style: const TextStyle(color: Colors.white60),
              ),
            for (final o in holidays)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.holiday.name(bengali: bengali),
                      style: const TextStyle(
                        color: kHolidayRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      o.holiday.description(bengali: bengali),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            if (bangla != null)
              Text(
                '${l10n.translate('hol_bangla_date')}: ${banglaDateLabel(context, bangla)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            Text(
              '${l10n.translate('hol_hijri_date')}: ${hijriDateLabel(context, hijri)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (leave != null) ...[
              const SizedBox(height: 10),
              Text(
                l10n.translate('hol_leave_gain', args: {'count': leave.days}),
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (holidays.isNotEmpty) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => shareHolidayFile(
                  bytes: Uint8List.fromList(utf8.encode(
                    HolidayExport.dayIcs(holidays, stamp: DateTime.now()),
                  )),
                  name: 'BD_Holiday_${HolidayCalendar.keyOf(date)}.ics',
                  mimeType: 'text/calendar',
                ),
                icon: const Icon(Icons.event_rounded),
                label: Text(l10n.translate('hol_export_ics')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
