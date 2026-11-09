import 'dart:convert';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/group_back_button.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/localized_date.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/study_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/services/holiday_calendar.dart';
import '../../domain/services/holiday_export.dart';
import '../../domain/services/study_room_rules.dart';
import '../widgets/holiday_calendar/holiday_common.dart';
import '../widgets/holiday_calendar/holiday_day_sheet.dart';
import '../widgets/holiday_calendar/holiday_leave_view.dart';
import '../widgets/holiday_calendar/holiday_list_view.dart';
import '../widgets/holiday_calendar/holiday_month_view.dart';
import 'study_session_screen.dart';

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
  late final Stream<TourGroup?> _groupStream = widget.tourId.isNotEmpty
      ? _repository.watchGroup(widget.tourId)
      : Stream.value(null);

  HolidayView _view = HolidayView.month;
  int _lunarShift = 0;
  late int _month;
  DateTime? _selected;
  Stream<List<ReadingSession>>? _sessionStream;

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
        // A family circle has no trip, so there is no trip card for it.
        final trip = group == null || group.isFamily
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
            if (group != null && group.isStudy) ...[
              const SizedBox(height: 12),
              _studySessionCard(context),
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
    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          backgroundColor: context.forest.surfaceFor(const Color(0xFF0D1A12)),
          elevation: 0,
          title: Text(
            context.l10n.translate('hol_title'),
            style: TextStyle(
              color: context.forest.text,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        body: body,
      ),
    );
  }

  /// The group's reading sessions. One stream per open of the screen, read only by a study group.
  Stream<List<ReadingSession>> _sessionsOf(String tourId) =>
      _sessionStream ??= _repository.watchReadingSessions(tourId);

  /// The study group's sessions whose study room has not closed, soonest first. Each opens its session page.
  Widget _studySessionCard(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    return StreamBuilder<List<ReadingSession>>(
      stream: _sessionsOf(widget.tourId),
      builder: (context, snap) {
        final sessions = calendarSessions(snap.data ?? const [], now: now);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kHolidayCard,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.mintGreen.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('study_calendar_title'),
                style: const TextStyle(
                  color: AppColors.mintGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (sessions.isEmpty)
                Text(
                  l10n.translate('study_calendar_empty'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              for (final session in sessions)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StudySessionScreen(
                        tourId: widget.tourId,
                        session: session,
                        repository: _repository,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          localizedDateFormat('d MMM y, h:mm a')
                              .format(session.startsAt),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
          style: TextStyle(color: context.forest.text60, fontSize: 12),
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
                style: TextStyle(color: context.forest.text60, fontSize: 11)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        swatch(kHolidayRed, l10n.translate('hol_legend_holiday')),
        swatch(context.forest.text38, l10n.translate('hol_legend_weekend')),
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
