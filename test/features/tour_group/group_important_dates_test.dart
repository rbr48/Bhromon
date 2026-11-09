import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/family_date_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/family_date_rules.dart';

void main() {
  group('dynamic important dates kinds and presets', () {
    test('office group provides office-tailored kinds and presets', () {
      final office = TourGroup(
        id: 'office_1',
        name: 'Tech Office',
        kind: GroupKind.family,
        preset: TourGroup.officePreset,
        ownerEmail: 'boss@tech.com',
        inviteCode: 'OFFICE12',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      final kinds = kindsForGroup(office);
      expect(kinds, contains(FamilyDateKind.deadline));
      expect(kinds, contains(FamilyDateKind.meeting));
      expect(kinds, contains(FamilyDateKind.bill));
      expect(kinds, isNot(contains(FamilyDateKind.school)));

      final presets = presetTemplatesFor(office);
      expect(presets, isNotEmpty);
      expect(presets.any((p) => p.titleEn.contains('Sprint Deadline')), isTrue);
      expect(presets.any((p) => p.titleEn.contains('Payroll')), isTrue);
    });

    test('campus group provides academic-tailored kinds and presets', () {
      final campus = TourGroup(
        id: 'campus_1',
        name: 'CSE Batch 2022',
        kind: GroupKind.family,
        preset: TourGroup.campusPreset,
        ownerEmail: 'cr@campus.edu',
        inviteCode: 'CAMPUS12',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      final kinds = kindsForGroup(campus);
      expect(kinds, contains(FamilyDateKind.exam));
      expect(kinds, contains(FamilyDateKind.deadline));
      expect(kinds, isNot(contains(FamilyDateKind.rent)));

      final presets = presetTemplatesFor(campus);
      expect(presets.any((p) => p.titleEn.contains('Final Examination')), isTrue);
      expect(presets.any((p) => p.titleEn.contains('Assignment')), isTrue);
    });

    test('mess group provides mess-tailored kinds and presets', () {
      final mess = TourGroup(
        id: 'mess_1',
        name: 'Bachelor Mess',
        kind: GroupKind.family,
        preset: TourGroup.messPreset,
        ownerEmail: 'manager@mess.com',
        inviteCode: 'MESS1234',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      final kinds = kindsForGroup(mess);
      expect(kinds, contains(FamilyDateKind.rent));
      expect(kinds, contains(FamilyDateKind.bill));

      final presets = presetTemplatesFor(mess);
      expect(presets.any((p) => p.titleEn.contains('Monthly House Rent')), isTrue);
      expect(presets.any((p) => p.titleEn.contains('Meal Calculation')), isTrue);
    });

    test('past dates beyond year 2000 are parsed and correctly computed', () {
      final date1971 = parseFamilyDay('1971-03-26');
      expect(date1971, isNotNull);
      expect(date1971!.year, 1971);
      expect(date1971.month, 3);
      expect(date1971.day, 26);

      const independenceDay = FamilyDate(
        id: 'id_1971',
        title: 'Independence Day',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.yearly,
        startOn: '1971-03-26',
        nextOn: '2027-03-26',
        remindDays: 3,
      );

      final today = DateTime(2026, 11, 9);
      final next = FamilyDateRules.nextDue(independenceDay, today);
      expect(next.year, 2027);
      expect(next.month, 3);
      expect(next.day, 26);

      const pastOneTime = FamilyDate(
        id: 'past_1995',
        title: 'Old Graduation',
        kind: FamilyDateKind.event,
        recurrence: FamilyRecurrence.once,
        startOn: '1995-05-15',
        nextOn: '1995-05-15',
        remindDays: 1,
      );

      final timing = FamilyDateRules.timingOf(pastOneTime, today);
      expect(timing, FamilyDateTiming.past);
    });
  });
}
