import 'package:bhromon/features/tour_group/domain/models/family_date_models.dart';
import 'package:bhromon/features/tour_group/domain/services/family_date_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The same examples as functions/src/__tests__/familyDates.test.ts, so the app and
// the reminder job agree on every date.

DateTime day(String key) => parseFamilyDay(key)!;

FamilyDate _date({
  String id = 'd',
  String title = "Asha's birthday",
  FamilyDateKind kind = FamilyDateKind.birthday,
  FamilyRecurrence recurrence = FamilyRecurrence.yearly,
  String startOn = '2000-11-03',
  String? nextOn,
  int remindDays = 7,
}) =>
    FamilyDate(
      id: id,
      title: title,
      kind: kind,
      recurrence: recurrence,
      startOn: startOn,
      nextOn: nextOn ?? startOn,
      remindDays: remindDays,
    );

void main() {
  group('day keys', () {
    test('a real day reads, and an impossible one does not', () {
      expect(parseFamilyDay('2026-11-03'), DateTime(2026, 11, 3));
      expect(parseFamilyDay('2026-02-30'), isNull);
      expect(parseFamilyDay('2026-13-01'), isNull);
      expect(parseFamilyDay('3 Nov 2026'), isNull);
      expect(parseFamilyDay(null), isNull);
    });

    test('a day is written with its zeros', () {
      expect(
          FamilyDateRules.dayKey(DateTime(2027, 1, 5, 18, 30)), '2027-01-05');
    });

    test('days are counted and added across months and leap days', () {
      expect(
          FamilyDateRules.daysBetween(day('2026-10-31'), day('2026-11-03')), 3);
      expect(FamilyDateRules.daysBetween(day('2026-11-03'), day('2026-10-31')),
          -3);
      expect(
          FamilyDateRules.addDays(day('2028-02-28'), 1), DateTime(2028, 2, 29));
      expect(
          FamilyDateRules.addDays(day('2026-12-31'), 1), DateTime(2027, 1, 1));
    });
  });

  group('occurrences', () {
    test('a yearly date keeps its month and day', () {
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2000-03-15'), FamilyRecurrence.yearly, day('2026-10-31')),
        DateTime(2027, 3, 15),
      );
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2000-03-15'), FamilyRecurrence.yearly, day('2026-03-15')),
        DateTime(2026, 3, 15),
      );
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2000-03-15'), FamilyRecurrence.yearly, day('2026-03-16')),
        DateTime(2027, 3, 15),
      );
    });

    test('a 29 February date falls on 28 February in a common year', () {
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2024-02-29'), FamilyRecurrence.yearly, day('2026-01-01')),
        DateTime(2026, 2, 28),
      );
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2024-02-29'), FamilyRecurrence.yearly, day('2028-01-01')),
        DateTime(2028, 2, 29),
      );
    });

    test('a monthly date keeps its day, or the last day of a short month', () {
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2026-01-31'), FamilyRecurrence.monthly, day('2026-02-01')),
        DateTime(2026, 2, 28),
      );
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2026-01-31'), FamilyRecurrence.monthly, day('2026-02-28')),
        DateTime(2026, 2, 28),
      );
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2026-01-31'), FamilyRecurrence.monthly, day('2026-03-01')),
        DateTime(2026, 3, 31),
      );
    });

    test('a monthly date rolls over the year end', () {
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2026-11-15'), FamilyRecurrence.monthly, day('2026-12-20')),
        DateTime(2027, 1, 15),
      );
    });

    test('a one-time date does not move', () {
      expect(
        FamilyDateRules.occurrenceOnOrAfter(
            day('2026-05-01'), FamilyRecurrence.once, day('2026-10-31')),
        DateTime(2026, 5, 1),
      );
    });
  });

  group('the schedule stored when a date is saved', () {
    test('a yearly birthday is stored on its next day, with its reminder', () {
      final s = FamilyDateRules.scheduleFor(
        startOn: day('2000-11-03'),
        recurrence: FamilyRecurrence.yearly,
        remindDays: 7,
        today: DateTime(2026, 10, 31),
      );
      expect(s.nextOn, '2026-11-03');
      expect(s.remindOn, '2026-10-27');
    });

    test('a date today is stored for today', () {
      final s = FamilyDateRules.scheduleFor(
        startOn: day('2000-11-03'),
        recurrence: FamilyRecurrence.yearly,
        remindDays: 0,
        today: DateTime(2026, 11, 3),
      );
      expect(s.nextOn, '2026-11-03');
      expect(s.remindOn, '2026-11-03');
    });

    test('a one-time date that passed keeps no reminder', () {
      final s = FamilyDateRules.scheduleFor(
        startOn: day('2026-10-01'),
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        today: DateTime(2026, 10, 31),
      );
      expect(s.nextOn, '2026-10-01');
      expect(s.remindOn, isNull);
    });

    test('a one-time date still to come reminds ahead of time', () {
      final s = FamilyDateRules.scheduleFor(
        startOn: day('2026-11-10'),
        recurrence: FamilyRecurrence.once,
        remindDays: 1,
        today: DateTime(2026, 10, 31),
      );
      expect(s.remindOn, '2026-11-09');
    });

    test('a 29 February birthday is stored on the 28th in a common year', () {
      final s = FamilyDateRules.scheduleFor(
        startOn: day('2024-02-29'),
        recurrence: FamilyRecurrence.yearly,
        remindDays: 1,
        today: DateTime(2026, 1, 10),
      );
      expect(s.nextOn, '2026-02-28');
      expect(s.remindOn, '2026-02-27');
    });
  });

  group('timing and the list sections', () {
    final today = DateTime(2026, 10, 31);

    test('a date is today, soon, later or past', () {
      expect(FamilyDateRules.timingOf(_date(startOn: '2000-10-31'), today),
          FamilyDateTiming.today);
      expect(
          FamilyDateRules.timingOf(
              _date(
                  recurrence: FamilyRecurrence.monthly, startOn: '2026-01-05'),
              today),
          FamilyDateTiming.soon);
      expect(FamilyDateRules.timingOf(_date(startOn: '2000-12-25'), today),
          FamilyDateTiming.later);
      expect(
          FamilyDateRules.timingOf(
              _date(recurrence: FamilyRecurrence.once, startOn: '2026-10-01'),
              today),
          FamilyDateTiming.past);
    });

    test('the list is worked out from today, not the stored day', () {
      // The job has not moved this birthday on, so the stored next day is stale.
      final stale = _date(startOn: '2000-10-15', nextOn: '2026-10-01');
      expect(FamilyDateRules.nextDue(stale, DateTime(2026, 10, 20)),
          DateTime(2027, 10, 15));
      expect(FamilyDateRules.timingOf(stale, DateTime(2026, 10, 20)),
          FamilyDateTiming.later);
    });

    test('sections come in order, upcoming soonest first and past newest first',
        () {
      final dates = [
        _date(id: 'later', startOn: '2000-12-25'),
        _date(
            id: 'past1',
            recurrence: FamilyRecurrence.once,
            startOn: '2026-10-01'),
        _date(id: 'today', startOn: '2000-10-31'),
        _date(
            id: 'soon',
            kind: FamilyDateKind.bill,
            recurrence: FamilyRecurrence.monthly,
            startOn: '2026-01-05'),
        _date(
            id: 'past2',
            recurrence: FamilyRecurrence.once,
            startOn: '2026-10-20'),
      ];
      final sections = FamilyDateRules.sections(dates, today);
      expect(sections.map((s) => s.timing).toList(), [
        FamilyDateTiming.today,
        FamilyDateTiming.soon,
        FamilyDateTiming.later,
        FamilyDateTiming.past,
      ]);
      expect(sections.last.items.map((d) => d.id).toList(), ['past2', 'past1']);
    });

    test('empty sections are left out', () {
      expect(FamilyDateRules.sections(const [], today), isEmpty);
      final only =
          FamilyDateRules.sections([_date(startOn: '2000-12-25')], today);
      expect(only.map((s) => s.timing).toList(), [FamilyDateTiming.later]);
    });
  });

  group('reading a stored date', () {
    test('a stored date reads back as it was written', () {
      final date = FamilyDate.fromMap('d1', {
        'title': " Asha's birthday ",
        'kind': 'birthday',
        'recurrence': 'yearly',
        'startOn': '2000-11-03',
        'nextOn': '2026-11-03',
        'remindDays': 7,
        'remindOn': '2026-10-27',
        'note': 'Cake',
        'createdByEmail': 'asha@x.com',
      });
      expect(date, isNotNull);
      expect(date!.title, "Asha's birthday");
      expect(date.kind, FamilyDateKind.birthday);
      expect(date.recurrence, FamilyRecurrence.yearly);
      expect(date.nextOn, '2026-11-03');
      expect(date.remindDays, 7);
      expect(date.remindOn, '2026-10-27');
      expect(date.note, 'Cake');
    });

    test('a damaged record is left out, not shown as today', () {
      expect(FamilyDate.fromMap('x', {'title': '', 'startOn': '2026-11-03'}),
          isNull);
      expect(
          FamilyDate.fromMap('x', {'title': 'Bill', 'startOn': '2026-02-30'}),
          isNull);
      expect(FamilyDate.fromMap('x', {'title': 'Bill'}), isNull);
    });

    test('an unknown kind is a custom date, and an unknown repeat is once', () {
      final date = FamilyDate.fromMap('x', {
        'title': 'Something',
        'kind': 'party',
        'recurrence': 'weekly',
        'startOn': '2026-11-03',
      })!;
      expect(date.kind, FamilyDateKind.custom);
      expect(date.recurrence, FamilyRecurrence.once);
    });

    test('a reminder lead outside 0 to 30 is brought into range', () {
      final late = FamilyDate.fromMap('x', {
        'title': 'Bill',
        'startOn': '2026-11-03',
        'remindDays': 90,
      })!;
      final negative = FamilyDate.fromMap('x', {
        'title': 'Bill',
        'startOn': '2026-11-03',
        'remindDays': -4,
      })!;
      expect(late.remindDays, kFamilyRemindMaxDays);
      expect(negative.remindDays, 0);
    });

    test('a date writes back the same fields the rules check', () {
      final map = _date().toMap();
      expect(map.keys.toSet(), {
        'title',
        'kind',
        'recurrence',
        'startOn',
        'nextOn',
        'remindDays',
        'remindOn',
        'note',
        'createdByEmail',
      });
    });
  });
}
