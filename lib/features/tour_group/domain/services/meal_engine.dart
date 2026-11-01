import '../models/meal_log.dart';

// Dates and totals for a mess's meal counts. Pure Dart, so it is unit-tested.

/// A day as yyyy-MM-dd.
String mealDateKey(DateTime day) {
  final year = day.year.toString().padLeft(4, '0');
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '$year-$month-$date';
}

/// The first day of the month, as a day key.
String mealMonthFirstKey(DateTime month) =>
    mealDateKey(DateTime(month.year, month.month));

/// The last day of the month, as a day key. Day zero of the next month is the last
/// day of this one.
String mealMonthLastKey(DateTime month) =>
    mealDateKey(DateTime(month.year, month.month + 1, 0));

/// How many days the month has.
int mealDaysInMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0).day;

/// Each member's meals over the logs, keyed by email. A member with no meals is left
/// out, so a bazar split gives them no share.
Map<String, int> mealTotalsByEmail(Iterable<MealLog> logs) {
  final totals = <String, int>{};
  for (final log in logs) {
    if (log.total == 0) continue;
    totals[log.email] = (totals[log.email] ?? 0) + log.total;
  }
  return totals;
}
