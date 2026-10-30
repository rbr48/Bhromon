import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/holiday_calendar.dart';
import '../../domain/services/holiday_export.dart';
import '../widgets/holiday_calendar/holiday_common.dart';
import '../widgets/holiday_calendar/holiday_day_sheet.dart';
import '../widgets/holiday_calendar/holiday_leave_view.dart';
import '../widgets/holiday_calendar/holiday_list_view.dart';
import '../widgets/holiday_calendar/holiday_month_view.dart';

enum HolidayView { month, year, list, leave }

/// The 2027 holiday and workday calendar, with the tour's dates overlaid so
/// the leave a trip needs is visible at a glance.
class HolidayCalendarScreen extends StatefulWidget {
  const HolidayCalendarScreen({
    super.key,
    required this.tourId,
    this.embedded = false,
  });

  final String tourId;
  final bool embedded;

  @override
  State<HolidayCalendarScreen> createState() => _HolidayCalendarScreenState();
}

class _HolidayCalendarScreenState extends State<HolidayCalendarScreen> {
  final TourGroupRepository _repository = TourGroupRepository();
  late final Stream<TourGroup?> _groupStream =
      _repository.watchGroup(widget.tourId);

  HolidayView _view = HolidayView.month;
  int _lunarShift = 0;
  late int _month;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.year == HolidayCalendar.defaultYear ? now.month : 1;
  }

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<TourGroup?>(
      stream: _groupStream,
      builder: (context, snap) {
        final group = snap.data;
        final calendar = HolidayCalendar(lunarShift: _lunarShift);
        final trip = group == null
            ? null
            : calendar.tripSummary(group.startDate, group.endDate);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildViewSwitch(context),
            const SizedBox(height: 12),
            _buildShiftSwitch(context),
            const SizedBox(height: 12),
            _buildKpis(context, calendar),
            if (trip != null) ...[
              const SizedBox(height: 12),
              _buildTripCard(context, calendar, trip),
            ],
            const SizedBox(height: 12),
            _buildLegend(context),
            const SizedBox(height: 10),
            _buildExports(context, calendar),
            const SizedBox(height: 16),
            _buildView(context, calendar, trip),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A12),
        elevation: 0,
        title: Text(
          context.l10n.translate('hol_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildViewSwitch(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<HolidayView>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: HolidayView.month,
          label: Text(l10n.translate('hol_view_month')),
        ),
        ButtonSegment(
          value: HolidayView.year,
          label: Text(l10n.translate('hol_view_year')),
        ),
        ButtonSegment(
          value: HolidayView.list,
          label: Text(l10n.translate('hol_view_list')),
        ),
        ButtonSegment(
          value: HolidayView.leave,
          label: Text(l10n.translate('hol_view_leave')),
        ),
      ],
      selected: {_view},
      onSelectionChanged: (s) => setState(() => _view = s.first),
    );
  }

  Widget _buildShiftSwitch(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('hol_shift_label'),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: -1,
              label: Text(l10n.translate('hol_shift_minus')),
            ),
            ButtonSegment(
              value: 0,
              label: Text(l10n.translate('hol_shift_zero')),
            ),
            ButtonSegment(
              value: 1,
              label: Text(l10n.translate('hol_shift_plus')),
            ),
          ],
          selected: {_lunarShift},
          onSelectionChanged: (s) => setState(() => _lunarShift = s.first),
        ),
      ],
    );
  }

  Widget _buildKpis(BuildContext context, HolidayCalendar calendar) {
    final l10n = context.l10n;
    final stats = calendar.yearStats();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _kpi(
            l10n.number(stats.netWorkdays), l10n.translate('hol_kpi_workdays')),
        _kpi(
          l10n.number(stats.workableHours),
          l10n.translate('hol_kpi_hours'),
        ),
        _kpi(
          l10n.number(calendar.occurrences.length),
          l10n.translate('hol_kpi_holidays'),
        ),
        _kpi(
          l10n.number(stats.weekendOverlaps),
          l10n.translate('hol_kpi_weekend_overlap'),
        ),
      ],
    );
  }

  Widget _kpi(String value, String label) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kHolidayCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(
    BuildContext context,
    HolidayCalendar calendar,
    TripSummary trip,
  ) {
    final l10n = context.l10n;
    final outsideYear =
        trip.start.year != calendar.year && trip.end.year != calendar.year;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kHolidayCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('hol_trip_title'),
            style: const TextStyle(
              color: AppColors.mintGreen,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${holidayDateLabel(context, trip.start)} – ${holidayDateLabel(context, trip.end)}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.translate('hol_trip_summary', args: {
              'days': trip.days,
              'count': trip.leaveDays,
              'n': trip.holidays.length,
            }),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (trip.holidays.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              l10n.translate('hol_trip_holidays', args: {
                'names': trip.holidays
                    .map((o) =>
                        o.holiday.name(bengali: holidayIsBengali(context)))
                    .join(', '),
              }),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (outsideYear) ...[
            const SizedBox(height: 4),
            Text(
              l10n.translate('hol_trip_outside_year'),
              style: const TextStyle(color: kHolidayAmber, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final l10n = context.l10n;
    Widget swatch(Color color, String label, {bool outline = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: outline ? null : color,
                borderRadius: BorderRadius.circular(3),
                border: outline ? Border.all(color: color, width: 1.5) : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        swatch(kHolidayRed, l10n.translate('hol_legend_holiday')),
        swatch(Colors.white38, l10n.translate('hol_legend_weekend')),
        swatch(AppColors.mintGreen, l10n.translate('hol_legend_trip'),
            outline: true),
      ],
    );
  }

  Widget _buildExports(BuildContext context, HolidayCalendar calendar) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => shareHolidayFile(
              bytes: Uint8List.fromList(utf8.encode(
                HolidayExport.yearIcs(calendar, stamp: DateTime.now()),
              )),
              name: 'Bangladesh_Holidays_${calendar.year}.ics',
              mimeType: 'text/calendar',
            ),
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(l10n.translate('hol_export_ics')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => shareHolidayFile(
              bytes: HolidayExport.gazetteCsvBytes(calendar),
              name: 'Bangladesh_Holidays_${calendar.year}.csv',
              mimeType: 'text/csv',
            ),
            icon: const Icon(Icons.table_chart_rounded, size: 18),
            label: Text(l10n.translate('hol_export_csv')),
          ),
        ),
      ],
    );
  }

  Widget _buildView(
    BuildContext context,
    HolidayCalendar calendar,
    TripSummary? trip,
  ) {
    void openDay(DateTime date) {
      setState(() => _selected = date);
      showHolidayDaySheet(
        context,
        calendar: calendar,
        date: date,
        inTrip: trip?.contains(date) ?? false,
      );
    }

    switch (_view) {
      case HolidayView.month:
        return HolidayMonthView(
          calendar: calendar,
          month: _month,
          trip: trip,
          selected: _selected,
          onMonthChanged: (m) => setState(() {
            _month = m;
            _selected = null;
          }),
          onDayTap: openDay,
        );
      case HolidayView.year:
        return HolidayYearView(
          calendar: calendar,
          trip: trip,
          onMonthTap: (m) => setState(() {
            _month = m;
            _view = HolidayView.month;
          }),
        );
      case HolidayView.list:
        return HolidayListView(calendar: calendar);
      case HolidayView.leave:
        return HolidayLeaveView(calendar: calendar, onDayTap: openDay);
    }
  }
}
