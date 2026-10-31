import 'dart:math' show min;

import '../models/family_date_models.dart';

/// Day arithmetic and reminder rules for family dates. The reminder job applies
/// the same rules on the server (`functions/src/lib/familyDates.ts`), and both
/// test the same examples, so the list and the reminders agree.
///
/// Every calculation uses calendar days only: no times, no time zones, and no
/// daylight saving.

/// Where a date falls from today, for the list's sections.
enum FamilyDateTiming { today, soon, later, past }

/// The day a date is stored to come due next, and when its reminder falls.
class FamilyDateSchedule {
  const FamilyDateSchedule({required this.nextOn, required this.remindOn});

  /// `YYYY-MM-DD`.
  final String nextOn;

  /// `YYYY-MM-DD`, or null when no reminder is due (a one-time date that passed).
  final String? remindOn;
}

class FamilyDateRules {
  FamilyDateRules._();

  /// How far ahead a date still counts as "soon" in the list.
  static const int soonDays = 30;

  /// The calendar day of [d], without its time.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The calendar day of [d] as `YYYY-MM-DD`.
  static String dayKey(DateTime d) {
    final day = dateOnly(d);
    return '${_pad(day.year, 4)}-${_pad(day.month, 2)}-${_pad(day.day, 2)}';
  }

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  /// The day `YYYY-MM-DD` as a date, or null when it is not a real day.
  static DateTime? parseDayKey(String? raw) => parseFamilyDay(raw);

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// [d] moved by [days] calendar days.
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// Whole calendar days from [from] to [to], positive when [to] is later.
  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  /// The first occurrence on or after [from].
  ///
  /// A monthly date keeps its day of the month, and a yearly date its month and
  /// day. A day the month does not have (the 31st in April, 29 February in a
  /// common year) falls on that month's last day. A one-time date is always
  /// [start], whether or not it has passed.
  static DateTime occurrenceOnOrAfter(
    DateTime start,
    FamilyRecurrence recurrence,
    DateTime from,
  ) {
    final first = dateOnly(start);
    if (recurrence == FamilyRecurrence.once) return first;
    final day = dateOnly(from);
    for (var step = 0; step < 2; step++) {
      final DateTime candidate;
      if (recurrence == FamilyRecurrence.monthly) {
        final total = day.year * 12 + (day.month - 1) + step;
        final year = total ~/ 12;
        final month = total % 12 + 1;
        candidate =
            DateTime(year, month, min(first.day, daysInMonth(year, month)));
      } else {
        final year = day.year + step;
        candidate = DateTime(
            year, first.month, min(first.day, daysInMonth(year, first.month)));
      }
      if (!candidate.isBefore(day)) return candidate;
    }
    return first; // Unreachable for a valid start: the second step always lands.
  }

  /// The next day and reminder day to store when a date is saved.
  ///
  /// A recurring date is stored on its next occurrence from [today]. A one-time
  /// date that has already passed keeps no reminder.
  static FamilyDateSchedule scheduleFor({
    required DateTime startOn,
    required FamilyRecurrence recurrence,
    required int remindDays,
    required DateTime today,
  }) {
    final now = dateOnly(today);
    final next = occurrenceOnOrAfter(startOn, recurrence, now);
    final remindOn = recurrence == FamilyRecurrence.once && next.isBefore(now)
        ? null
        : dayKey(addDays(next, -remindDays));
    return FamilyDateSchedule(nextOn: dayKey(next), remindOn: remindOn);
  }

  /// The day a date next comes due, from [today]. It is worked out from the
  /// start, so the list is right even on a day the reminder job has not run yet.
  static DateTime nextDue(FamilyDate date, DateTime today) {
    final start = parseDayKey(date.startOn) ?? dateOnly(today);
    return occurrenceOnOrAfter(start, date.recurrence, dateOnly(today));
  }

  /// Where [date] falls from [today].
  static FamilyDateTiming timingOf(FamilyDate date, DateTime today) {
    final days = daysBetween(dateOnly(today), nextDue(date, today));
    if (days < 0) return FamilyDateTiming.past;
    if (days == 0) return FamilyDateTiming.today;
    if (days <= soonDays) return FamilyDateTiming.soon;
    return FamilyDateTiming.later;
  }

  /// The list's sections in order, leaving out empty ones. Upcoming dates come
  /// soonest first, and past one-time dates newest first.
  static List<({FamilyDateTiming timing, List<FamilyDate> items})> sections(
    List<FamilyDate> dates,
    DateTime today,
  ) {
    final byTiming = <FamilyDateTiming, List<FamilyDate>>{};
    for (final date in dates) {
      byTiming.putIfAbsent(timingOf(date, today), () => []).add(date);
    }
    int soonestFirst(FamilyDate a, FamilyDate b) =>
        nextDue(a, today).compareTo(nextDue(b, today));
    for (final items in byTiming.values) {
      items.sort(soonestFirst);
    }
    byTiming[FamilyDateTiming.past]
        ?.sort((a, b) => soonestFirst(b, a)); // Newest past first.
    return [
      for (final timing in FamilyDateTiming.values)
        if (byTiming[timing] case final items? when items.isNotEmpty)
          (timing: timing, items: items),
    ];
  }
}
