import 'dart:convert';
import 'dart:typed_data';

import '../models/holiday_models.dart';
import 'holiday_calendar.dart';

/// Builds the calendar exports: iCalendar (.ics) files and the gazette CSV.
class HolidayExport {
  HolidayExport._();

  static const List<String> _csvHeaders = [
    'Date',
    'Day',
    'Occasion_BN',
    'Occasion_EN',
    'Bangla_Date',
    'Hijri_Date',
    'Category',
    'Religion',
    'Weekend_Overlap',
  ];

  static const List<String> _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// The whole year as one calendar, with one event per holiday.
  static String yearIcs(HolidayCalendar calendar, {required DateTime stamp}) =>
      _calendar(
        calendar.occurrences,
        stamp,
        name: 'Bangladesh Holidays ${calendar.year}',
      );

  /// The holidays on one day, as a calendar.
  static String dayIcs(List<HolidayOccurrence> items,
          {required DateTime stamp}) =>
      _calendar(items, stamp, name: 'Bangladesh Holiday');

  /// Escapes text for an iCalendar value (RFC 5545 section 3.3.11).
  static String escapeText(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  /// Folds a content line so no line is longer than 75 octets. A continuation
  /// line starts with a space. Characters are never split.
  static String foldLine(String line) {
    final out = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCodes([rune]);
      final size = utf8.encode(ch).length;
      if (octets + size > 75) {
        out.write('\r\n ');
        octets = 1;
      }
      out.write(ch);
      octets += size;
    }
    return out.toString();
  }

  /// The gazette list as a CSV file, with a byte-order mark so Excel reads the
  /// Bengali text.
  static Uint8List gazetteCsvBytes(HolidayCalendar calendar) {
    final rows = <String>[
      _csvHeaders.join(','),
      for (final o in calendar.occurrences) _csvRow(calendar, o),
    ];
    return Uint8List.fromList(utf8.encode('﻿${rows.join('\r\n')}\r\n'));
  }

  static String _csvRow(HolidayCalendar calendar, HolidayOccurrence o) {
    final h = o.holiday;
    final bangla = calendar.banglaDate(o.date);
    final hijri = calendar.hijriDate(o.date);
    return [
      _ymd(o.date, dashes: true),
      _weekdayNames[o.date.weekday - 1],
      h.nameBn,
      h.nameEn,
      bangla == null ? '' : '${bangla.day} ${bangla.monthEn} ${bangla.year}',
      '${hijri.day} ${hijri.monthEn} ${hijri.year}',
      h.category.name,
      h.religion,
      HolidayCalendar.isWeekend(o.date) ? 'YES' : 'NO',
    ].map(_csvCell).join(',');
  }

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    if (text.contains(',') || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  static String _calendar(
    List<HolidayOccurrence> items,
    DateTime stamp, {
    required String name,
  }) {
    final dtstamp = _utcStamp(stamp);
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Bhromon//Bangladesh Holidays//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${escapeText(name)}',
      for (final o in items) ..._event(o, dtstamp),
      'END:VCALENDAR',
    ];
    return '${lines.map(foldLine).join('\r\n')}\r\n';
  }

  static List<String> _event(HolidayOccurrence o, String dtstamp) {
    final h = o.holiday;
    final day = _ymd(o.date);
    final nextDay = _ymd(DateTime(o.date.year, o.date.month, o.date.day + 1));
    return [
      'BEGIN:VEVENT',
      'UID:bd-holiday-$day-${_slug(h.nameEn)}@bhromon.fun',
      'DTSTAMP:$dtstamp',
      'DTSTART;VALUE=DATE:$day',
      'DTEND;VALUE=DATE:$nextDay',
      'SUMMARY:${escapeText('${h.nameBn} (${h.nameEn})')}',
      'DESCRIPTION:${escapeText('${h.descBn} | ${h.descEn}')}',
      'CATEGORIES:${h.category.name}',
      'END:VEVENT',
    ];
  }

  static String _slug(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  static String _ymd(DateTime d, {bool dashes = false}) {
    final sep = dashes ? '-' : '';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}$sep$m$sep$day';
  }

  static String _utcStamp(DateTime d) {
    final u = d.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }
}
