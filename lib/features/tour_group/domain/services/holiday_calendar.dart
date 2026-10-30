import '../models/holiday_models.dart';
import 'holiday_data_2027.dart';

/// A day in the Bangla calendar (Bangla Academy reformed calendar).
class BanglaDate {
  const BanglaDate({
    required this.day,
    required this.monthBn,
    required this.monthEn,
    required this.year,
  });

  final int day;
  final String monthBn;
  final String monthEn;
  final int year;
}

/// A day in the Hijri calendar.
class HijriDate {
  const HijriDate({
    required this.day,
    required this.monthBn,
    required this.monthEn,
    required this.year,
  });

  final int day;
  final String monthBn;
  final String monthEn;
  final int year;
}

/// Day counts for a stretch of days.
class PeriodStats {
  const PeriodStats({
    required this.totalDays,
    required this.weekends,
    required this.weekdayHolidays,
    required this.weekendOverlaps,
  });

  final int totalDays;
  final int weekends;

  /// Holidays on a working day. Each one costs a working day.
  final int weekdayHolidays;

  /// Holidays that fall on a weekend, so they cost nothing extra.
  final int weekendOverlaps;

  int get netWorkdays => totalDays - weekends - weekdayHolidays;

  int get workableHours => netWorkdays * HolidayCalendar.hoursPerDay;

  double get workPercent => totalDays == 0 ? 0 : netWorkdays * 100 / totalDays;
}

/// The run of days off that one leave day joins together, inclusive.
class LeaveRange {
  const LeaveRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  int get days => daysBetween(start, end) + 1;
}

/// A single leave day and the run of days off it creates.
class LeaveOption {
  const LeaveOption({required this.leaveDay, required this.range});

  final DateTime leaveDay;
  final LeaveRange range;

  int get streak => range.days;
}

/// What a trip costs in leave, and which holidays fall inside it.
class TripSummary {
  const TripSummary({
    required this.start,
    required this.end,
    required this.days,
    required this.leaveDays,
    required this.holidays,
  });

  final DateTime start;
  final DateTime end;

  /// Every day of the trip, counting weekends and holidays.
  final int days;

  /// Trip days that are working days, so each needs a leave day.
  final int leaveDays;

  /// Holidays inside the trip, in date order.
  final List<HolidayOccurrence> holidays;

  bool contains(DateTime day) {
    final d = HolidayCalendar.dateOnly(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

/// Whole days from [from] to [to]. Uses UTC so daylight saving never shifts it.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The working calendar for one year: holidays, weekends, leave planning and
/// the Bangla and Hijri dates shown beside them.
///
/// Weekends are Friday and Saturday. A moon-dependent holiday moves by
/// [lunarShift] days. Several holidays can share a date, so each date keeps
/// all of them.
class HolidayCalendar {
  HolidayCalendar({
    this.lunarShift = 0,
    this.year = defaultYear,
    List<Holiday>? holidays,
  })  : assert(lunarShift >= -1 && lunarShift <= 1),
        holidays = holidays ?? kHolidays2027 {
    occurrences = _buildOccurrences();
    _byDate = _indexByDate();
  }

  static const int defaultYear = 2027;
  static const int hoursPerDay = 8;

  /// Days the moon-dependent holidays move by: -1, 0 or +1.
  final int lunarShift;
  final int year;
  final List<Holiday> holidays;

  /// Every holiday on its date, in date order.
  late final List<HolidayOccurrence> occurrences;
  late final Map<String, List<HolidayOccurrence>> _byDate;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isWeekend(DateTime d) =>
      d.weekday == DateTime.friday || d.weekday == DateTime.saturday;

  static String keyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int daysInMonth(int month) => DateTime(year, month + 1, 0).day;

  /// Every day of the year, in order.
  List<DateTime> get days {
    final count = daysBetween(DateTime(year, 1, 1), DateTime(year + 1, 1, 1));
    return [for (var i = 0; i < count; i++) DateTime(year, 1, 1 + i)];
  }

  List<HolidayOccurrence> holidaysOn(DateTime day) =>
      _byDate[keyOf(dateOnly(day))] ?? const [];

  /// True on a weekend or a holiday.
  bool isOff(DateTime day) => isWeekend(day) || holidaysOn(day).isNotEmpty;

  PeriodStats monthStats(int month) => _tally([
        for (var d = 1; d <= daysInMonth(month); d++) DateTime(year, month, d),
      ]);

  PeriodStats yearStats() => _tally(days);

  TripSummary tripSummary(DateTime start, DateTime end) {
    final from = dateOnly(start);
    final to = dateOnly(end).isBefore(from) ? from : dateOnly(end);
    final count = daysBetween(from, to) + 1;
    var leaveDays = 0;
    final inTrip = <HolidayOccurrence>[];
    for (var i = 0; i < count; i++) {
      final day = DateTime(from.year, from.month, from.day + i);
      if (!isOff(day)) leaveDays++;
      inTrip.addAll(holidaysOn(day));
    }
    return TripSummary(
      start: from,
      end: to,
      days: count,
      leaveDays: leaveDays,
      holidays: inTrip,
    );
  }

  /// The days off that taking [leaveDay] as one leave day creates.
  LeaveRange leaveRangeFor(DateTime leaveDay) {
    final target = dateOnly(leaveDay);
    bool offIfLeave(DateTime d) => d == target || isOff(d);

    var start = target;
    while (true) {
      final prev = DateTime(start.year, start.month, start.day - 1);
      if (prev.year != year || !offIfLeave(prev)) break;
      start = prev;
    }
    var end = target;
    while (true) {
      final next = DateTime(end.year, end.month, end.day + 1);
      if (next.year != year || !offIfLeave(next)) break;
      end = next;
    }
    return LeaveRange(start: start, end: end);
  }

  /// The working days whose single leave day gives the longest break, longest
  /// first. Ties go to the earlier date.
  List<LeaveOption> bestLeaveDays({int limit = 12}) {
    final options = [
      for (final day in days)
        if (!isOff(day)) LeaveOption(leaveDay: day, range: leaveRangeFor(day)),
    ]..sort((a, b) {
        final byLength = b.streak.compareTo(a.streak);
        return byLength != 0 ? byLength : a.leaveDay.compareTo(b.leaveDay);
      });
    return options.take(limit).toList();
  }

  /// The Bangla date, or null outside the year this table covers.
  BanglaDate? banglaDate(DateTime day) {
    if (day.year != year) return null;
    final diff = daysBetween(DateTime(year, 1, 1), day);
    if (diff < 103) {
      // Bangabda 1433: Poush runs until the 14th of January, then Magh,
      // Falgun and Chaitra.
      if (diff <= 13) {
        return BanglaDate(
            day: 17 + diff, monthBn: 'পৌষ', monthEn: 'Poush', year: 1433);
      }
      var rem = diff - 14;
      if (rem < 30) {
        return BanglaDate(
            day: rem + 1, monthBn: 'মাঘ', monthEn: 'Magh', year: 1433);
      }
      rem -= 30;
      if (rem < 29) {
        return BanglaDate(
            day: rem + 1, monthBn: 'ফাল্গুন', monthEn: 'Falgun', year: 1433);
      }
      rem -= 29;
      return BanglaDate(
          day: rem + 1, monthBn: 'চৈত্র', monthEn: 'Chaitra', year: 1433);
    }
    // Bangabda 1434 starts on 14 April.
    var rem = diff - 103;
    for (final m in _banglaMonths) {
      if (rem < m.length) {
        return BanglaDate(
            day: rem + 1, monthBn: m.nameBn, monthEn: m.nameEn, year: 1434);
      }
      rem -= m.length;
    }
    return const BanglaDate(
        day: 1, monthBn: 'পৌষ', monthEn: 'Poush', year: 1434);
  }

  /// The Hijri date, with the same moon-sighting shift as the holidays.
  HijriDate hijriDate(DateTime day) {
    final shifted = DateTime(day.year, day.month, day.day + lunarShift);
    var start = _hijriStarts.first;
    for (final s in _hijriStarts) {
      if (shifted.isBefore(s.start)) break;
      start = s;
    }
    final dayNumber =
        (daysBetween(start.start, shifted) + 1).clamp(1, 30).toInt();
    return HijriDate(
      day: dayNumber,
      monthBn: start.nameBn,
      monthEn: start.nameEn,
      year: start.year,
    );
  }

  PeriodStats _tally(List<DateTime> dayList) {
    var weekends = 0;
    var weekdayHolidays = 0;
    var overlaps = 0;
    for (final day in dayList) {
      final weekend = isWeekend(day);
      if (weekend) weekends++;
      if (holidaysOn(day).isNotEmpty) {
        if (weekend) {
          overlaps++;
        } else {
          weekdayHolidays++;
        }
      }
    }
    return PeriodStats(
      totalDays: dayList.length,
      weekends: weekends,
      weekdayHolidays: weekdayHolidays,
      weekendOverlaps: overlaps,
    );
  }

  List<HolidayOccurrence> _buildOccurrences() {
    final list = [
      for (final h in holidays)
        HolidayOccurrence(date: _shiftedDate(h), holiday: h),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  DateTime _shiftedDate(Holiday h) {
    final base = DateTime.parse(h.baseDate);
    return h.isMoon
        ? DateTime(base.year, base.month, base.day + lunarShift)
        : DateTime(base.year, base.month, base.day);
  }

  Map<String, List<HolidayOccurrence>> _indexByDate() {
    final map = <String, List<HolidayOccurrence>>{};
    for (final o in occurrences) {
      (map[keyOf(o.date)] ??= []).add(o);
    }
    return map;
  }
}

class _BanglaMonth {
  const _BanglaMonth(this.nameBn, this.nameEn, this.length);

  final String nameBn;
  final String nameEn;
  final int length;
}

/// The Bangla months of 1434, from 14 April 2027. Falgun has 29 days, as
/// 2027 is not a leap year in the Bangla calendar.
const List<_BanglaMonth> _banglaMonths = [
  _BanglaMonth('বৈশাখ', 'Baishakh', 31),
  _BanglaMonth('জ্যৈষ্ঠ', 'Jyeshtha', 31),
  _BanglaMonth('আষাঢ়', 'Ashadh', 31),
  _BanglaMonth('শ্রাবণ', 'Shravan', 31),
  _BanglaMonth('ভাদ্র', 'Bhadra', 31),
  _BanglaMonth('আশ্বিন', 'Ashwin', 31),
  _BanglaMonth('কার্তিক', 'Kartik', 30),
  _BanglaMonth('অগ্রহায়ণ', 'Agrahayan', 30),
  _BanglaMonth('পৌষ', 'Poush', 30),
  _BanglaMonth('মাঘ', 'Magh', 30),
  _BanglaMonth('ফাল্গুন', 'Falgun', 29),
  _BanglaMonth('চৈত্র', 'Chaitra', 30),
];

class _HijriStart {
  const _HijriStart(this.nameBn, this.nameEn, this.year, this.start);

  final String nameBn;
  final String nameEn;
  final int year;
  final DateTime start;
}

/// When each Hijri month of 1448 and 1449 begins, on the Umm al-Qura
/// reckoning. The moon-sighting shift moves these with the holidays.
final List<_HijriStart> _hijriStarts = [
  _HijriStart('রজব', 'Rajab', 1448, DateTime(2026, 12, 11)),
  _HijriStart('শাবান', 'Shaban', 1448, DateTime(2027, 1, 10)),
  _HijriStart('রমজান', 'Ramadan', 1448, DateTime(2027, 2, 8)),
  _HijriStart('শাওয়াল', 'Shawwal', 1448, DateTime(2027, 3, 10)),
  _HijriStart('জিলকদ', 'Dhu al-Qadah', 1448, DateTime(2027, 4, 8)),
  _HijriStart('জিলহজ্ব', 'Dhu al-Hijjah', 1448, DateTime(2027, 5, 8)),
  _HijriStart('মহররম', 'Muharram', 1449, DateTime(2027, 6, 7)),
  _HijriStart('সফর', 'Safar', 1449, DateTime(2027, 7, 7)),
  _HijriStart('রবিউল আউয়াল', 'Rabi al-Awwal', 1449, DateTime(2027, 8, 5)),
  _HijriStart('রবিউস সানি', 'Rabi al-Thani', 1449, DateTime(2027, 9, 4)),
  _HijriStart('জমাদিউল আউয়াল', 'Jumada al-Awwal', 1449, DateTime(2027, 10, 3)),
  _HijriStart('জমাদিউস সানি', 'Jumada al-Thani', 1449, DateTime(2027, 11, 2)),
  _HijriStart('রজব', 'Rajab', 1449, DateTime(2027, 12, 1)),
];
