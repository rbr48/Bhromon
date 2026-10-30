import 'dart:convert';

import 'package:bhromon/features/tour_group/domain/services/holiday_calendar.dart';
import 'package:bhromon/features/tour_group/domain/services/holiday_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('holiday dataset', () {
    test('has the 28 holidays of 2027, all dated in 2027', () {
      final calendar = HolidayCalendar();

      expect(calendar.holidays, hasLength(28));
      expect(calendar.occurrences, hasLength(28));
      expect(calendar.occurrences.every((o) => o.date.year == 2027), isTrue);
    });
  });

  group('weekends and working days', () {
    test('Friday and Saturday are the weekend', () {
      expect(HolidayCalendar.isWeekend(DateTime(2027, 1, 1)), isTrue); // Friday
      expect(
          HolidayCalendar.isWeekend(DateTime(2027, 1, 2)), isTrue); // Saturday
      expect(
          HolidayCalendar.isWeekend(DateTime(2027, 1, 3)), isFalse); // Sunday
    });

    test('2027 has 105 weekend days, as it starts on a Friday', () {
      final stats = HolidayCalendar().yearStats();

      expect(stats.totalDays, 365);
      expect(stats.weekends, 105);
    });

    test('working days leave out weekends and weekday holidays', () {
      final stats = HolidayCalendar().yearStats();

      expect(stats.netWorkdays, 365 - stats.weekends - stats.weekdayHolidays);
      expect(stats.workableHours, stats.netWorkdays * 8);
      // Each holiday is either on a weekend or costs a working day.
      expect(stats.weekdayHolidays + stats.weekendOverlaps, 28);
    });
  });

  group('moon-sighting shift', () {
    test('+1 moves Eid-ul-Fitr main day and keeps fixed holidays', () {
      final calendar = HolidayCalendar(lunarShift: 1);

      // The Eid Eve holiday moves onto 10 March, and the main day to 11 March.
      expect(
        calendar.holidaysOn(DateTime(2027, 3, 10)).map((o) => o.holiday.nameEn),
        isNot(contains('Eid-ul-Fitr (Main Day)')),
      );
      expect(
        calendar.holidaysOn(DateTime(2027, 3, 11)).map((o) => o.holiday.nameEn),
        contains('Eid-ul-Fitr (Main Day)'),
      );
      expect(
        calendar.holidaysOn(DateTime(2027, 3, 26)).single.holiday.nameEn,
        'Independence & National Day',
      );
    });

    test('-1 moves it the other way', () {
      final calendar = HolidayCalendar(lunarShift: -1);

      expect(
        calendar.holidaysOn(DateTime(2027, 3, 9)).map((o) => o.holiday.nameEn),
        contains('Eid-ul-Fitr (Main Day)'),
      );
    });

    test('rejects shifts other than -1, 0 and +1', () {
      expect(
          () => HolidayCalendar(lunarShift: 2), throwsA(isA<AssertionError>()));
    });
  });

  group('Bangla and Hijri dates', () {
    test('1 January 2027 is 17 Poush 1433', () {
      final b = HolidayCalendar().banglaDate(DateTime(2027, 1, 1))!;

      expect(b.day, 17);
      expect(b.monthEn, 'Poush');
      expect(b.year, 1433);
    });

    test('15 March 2027 is 1 Chaitra 1433', () {
      final b = HolidayCalendar().banglaDate(DateTime(2027, 3, 15))!;

      expect(b.day, 1);
      expect(b.monthEn, 'Chaitra');
    });

    test('14 April 2027 is 1 Baishakh 1434', () {
      final b = HolidayCalendar().banglaDate(DateTime(2027, 4, 14))!;

      expect(b.day, 1);
      expect(b.monthEn, 'Baishakh');
      expect(b.year, 1434);
    });

    test('10 March 2027 is 1 Shawwal 1448 without a shift', () {
      final h = HolidayCalendar().hijriDate(DateTime(2027, 3, 10));

      expect(h.day, 1);
      expect(h.monthEn, 'Shawwal');
      expect(h.year, 1448);
    });

    test('the moon shift moves the Hijri date with the holidays', () {
      final h =
          HolidayCalendar(lunarShift: -1).hijriDate(DateTime(2027, 3, 10));

      expect(h.monthEn, 'Ramadan');
      expect(h.day, 30);
    });
  });

  group('leave planning', () {
    test('a Thursday between working days joins the weekend into a 3-day break',
        () {
      final range = HolidayCalendar().leaveRangeFor(DateTime(2027, 1, 7));

      expect(range.start, DateTime(2027, 1, 7));
      expect(range.end, DateTime(2027, 1, 9));
      expect(range.days, 3);
    });

    test('best leave days are the longest first, then by date', () {
      final best = HolidayCalendar().bestLeaveDays(limit: 12);

      expect(best, hasLength(12));
      for (var i = 1; i < best.length; i++) {
        expect(best[i - 1].streak >= best[i].streak, isTrue);
      }
      expect(best.first.streak, greaterThanOrEqualTo(3));
    });
  });

  group('trips', () {
    test('a Thursday to Sunday trip needs leave on its working days only', () {
      final trip = HolidayCalendar().tripSummary(
        DateTime(2027, 1, 7),
        DateTime(2027, 1, 10),
      );

      expect(trip.days, 4);
      expect(trip.leaveDays, 2); // Thursday and Sunday
      expect(trip.holidays, isEmpty);
      expect(trip.contains(DateTime(2027, 1, 8, 15, 30)), isTrue);
      expect(trip.contains(DateTime(2027, 1, 11)), isFalse);
    });

    test('a trip that ends before it starts is one day', () {
      final trip = HolidayCalendar().tripSummary(
        DateTime(2027, 1, 7),
        DateTime(2027, 1, 1),
      );

      expect(trip.days, 1);
    });
  });

  group('iCalendar and CSV exports', () {
    test('escapes commas, semicolons, backslashes and newlines', () {
      expect(
        HolidayExport.escapeText('a,b;c\\d\ne'),
        r'a\,b\;c\\d\ne',
      );
    });

    test('folds long lines to 75 octets without splitting a character', () {
      const line =
          'SUMMARY:শুভ জন্মাষ্টমী (Shubho Janmashtami) শুভ জন্মাষ্টমী শুভ জন্মাষ্টমী';
      final folded = HolidayExport.foldLine(line);

      for (final physical in folded.split('\r\n')) {
        expect(utf8.encode(physical).length, lessThanOrEqualTo(75));
      }
      expect(folded.replaceAll('\r\n ', ''), line);
    });

    test('the year calendar has one event per holiday and short lines', () {
      final ics = HolidayExport.yearIcs(
        HolidayCalendar(),
        stamp: DateTime.utc(2026, 10, 25),
      );

      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics.split('BEGIN:VEVENT'), hasLength(29));
      expect(ics, contains('DTSTAMP:20261025T000000Z'));
      for (final line in ics.split('\r\n')) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75));
      }
    });

    test(
        'the gazette CSV has a byte-order mark, a header and one row per holiday',
        () {
      final bytes = HolidayExport.gazetteCsvBytes(HolidayCalendar());
      final text = utf8.decode(bytes);

      expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
      expect(text, startsWith('Date,Day,'));
      final rows = text.split('\r\n').where((l) => l.isNotEmpty).toList();
      expect(rows, hasLength(29));
      expect(rows[1], startsWith('2027-01-24,Sunday,'));
    });
  });
}
