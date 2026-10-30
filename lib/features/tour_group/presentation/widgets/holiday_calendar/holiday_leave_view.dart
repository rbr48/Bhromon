import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/theme/colors.dart';
import '../../../domain/services/holiday_calendar.dart';
import 'holiday_common.dart';

/// Leave planning: check what one leave day gives, or see the best single
/// leave days of the year.
class HolidayLeaveView extends StatefulWidget {
  const HolidayLeaveView({
    super.key,
    required this.calendar,
    required this.onDayTap,
  });

  final HolidayCalendar calendar;
  final ValueChanged<DateTime> onDayTap;

  @override
  State<HolidayLeaveView> createState() => _HolidayLeaveViewState();
}

class _HolidayLeaveViewState extends State<HolidayLeaveView> {
  DateTime? _checked;

  Future<void> _pickDate() async {
    final year = widget.calendar.year;
    final picked = await showDatePicker(
      context: context,
      initialDate: _checked ?? DateTime(year, 1, 1),
      firstDate: DateTime(year, 1, 1),
      lastDate: DateTime(year, 12, 31),
    );
    if (picked != null) setState(() => _checked = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final checked = _checked;
    final best = widget.calendar.bestLeaveDays();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.mintGreen,
            foregroundColor: Colors.black,
          ),
          onPressed: _pickDate,
          icon: const Icon(Icons.event_available_rounded),
          label: Text(l10n.translate('hol_leave_check')),
        ),
        if (checked != null) ...[
          const SizedBox(height: 12),
          _CheckResult(
            calendar: widget.calendar,
            day: checked,
            onOpen: () => widget.onDayTap(checked),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          l10n.translate('hol_leave_best'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        for (final option in best)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onDayTap(option.leaveDay),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kHolidayCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            holidayDateLabel(context, option.leaveDay),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            l10n.translate(
                              'hol_leave_range',
                              args: {
                                'start': holidayDateLabel(
                                    context, option.range.start),
                                'end':
                                    holidayDateLabel(context, option.range.end),
                              },
                            ),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      l10n.translate('hol_days_off',
                          args: {'count': option.streak}),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CheckResult extends StatelessWidget {
  const _CheckResult({
    required this.calendar,
    required this.day,
    required this.onOpen,
  });

  final HolidayCalendar calendar;
  final DateTime day;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final off = calendar.isOff(day);
    final String message;
    String? range;
    if (off) {
      final reason = HolidayCalendar.isWeekend(day)
          ? l10n.translate('hol_reason_weekend')
          : l10n.translate('hol_reason_holiday');
      message =
          l10n.translate('hol_leave_already_off', args: {'reason': reason});
    } else {
      final leave = calendar.leaveRangeFor(day);
      message = l10n.translate('hol_leave_gain', args: {'count': leave.days});
      range = l10n.translate('hol_leave_range', args: {
        'start': holidayDateLabel(context, leave.start),
        'end': holidayDateLabel(context, leave.end),
      });
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kHolidayCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${localizedDateFormat('EEEE').format(day)}, ${holidayDateLabel(context, day)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(color: AppColors.mintGreen)),
            if (range != null)
              Text(range,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
