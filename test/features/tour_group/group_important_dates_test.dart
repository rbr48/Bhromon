import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
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
      expect(
          presets.any((p) => p.titleEn.contains('Final Examination')), isTrue);
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
      expect(
          presets.any((p) => p.titleEn.contains('Monthly House Rent')), isTrue);
      expect(
          presets.any((p) => p.titleEn.contains('Meal Calculation')), isTrue);
    });

    test('friends circle provides friend-tailored kinds, presets, and titles',
        () {
      final friends = TourGroup(
        id: 'friends_1',
        name: 'Dost Squad',
        kind: GroupKind.family,
        preset: TourGroup.friendsPreset,
        ownerEmail: 'dost@bhromon.fun',
        inviteCode: 'FRIEND12',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      final kinds = kindsForGroup(friends);
      expect(kinds, contains(FamilyDateKind.event));
      expect(kinds, contains(FamilyDateKind.birthday));
      expect(kinds, contains(FamilyDateKind.meeting));
      expect(kinds, contains(FamilyDateKind.bill));
      expect(kinds, isNot(contains(FamilyDateKind.rent)));
      expect(kinds, isNot(contains(FamilyDateKind.medicine)));
      expect(kinds, isNot(contains(FamilyDateKind.school)));

      final presets = presetTemplatesFor(friends);
      expect(
          presets.any((p) =>
              p.titleEn.contains('Adda') || p.titleEn.contains('Hangout')),
          isTrue);
      expect(presets.any((p) => p.titleEn.contains('Friendship Day')), isTrue);
      expect(presets.any((p) => p.titleEn.contains('Batch Reunion')), isTrue);

      final l10nBn = AppLocalizations(const Locale('bn'));
      final l10nEn = AppLocalizations(const Locale('en'));

      // Check Bengali titles and modal headers
      expect(groupDateScreenTitle(friends, l10nBn), 'আড্ডা ও বিশেষ তারিখ');
      expect(groupDateModalHeader(friends, l10nBn, isAdd: true, canEdit: true),
          'নতুন আড্ডা বা বিশেষ তারিখ');
      expect(groupDateModalHeader(friends, l10nBn, isAdd: false, canEdit: true),
          'তারিখ ও আয়োজন সম্পাদন');

      // Check English titles and modal headers
      expect(groupDateScreenTitle(friends, l10nEn), 'Friends Dates & Hangouts');
      expect(groupDateModalHeader(friends, l10nEn, isAdd: true, canEdit: true),
          'Add hangout or friends date');
    });

    test('group with preset null but friends in name infers friends preset',
        () {
      final friendsByName = TourGroup(
        id: 'f_null_preset',
        name: 'Notre Dame College Friends',
        kind: GroupKind.family,
        preset: null,
        ownerEmail: 'ndc@bhromon.fun',
        inviteCode: 'NDC12345',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      expect(friendsByName.effectivePreset, TourGroup.friendsPreset);
      expect(friendsByName.preset, isNull);

      final l10nBn = AppLocalizations(const Locale('bn'));
      expect(
          groupDateScreenTitle(friendsByName, l10nBn), 'আড্ডা ও বিশেষ তারিখ');
      expect(
          groupDateModalHeader(friendsByName, l10nBn,
              isAdd: true, canEdit: true),
          'নতুন আড্ডা বা বিশেষ তারিখ');
    });

    test('household group vs other presets show correct headers', () {
      final household = TourGroup(
        id: 'home_1',
        name: 'Rahman Family',
        kind: GroupKind.family,
        preset: null, // Pure household
        ownerEmail: 'dad@home.com',
        inviteCode: 'HOME1234',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      final school = TourGroup(
        id: 'school_1',
        name: 'Class 10 Section A',
        kind: GroupKind.family,
        preset: TourGroup.schoolPreset,
        ownerEmail: 'teacher@school.com',
        inviteCode: 'SCHL1234',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        createdAt: DateTime(2026, 1, 1),
      );

      final l10nBn = AppLocalizations(const Locale('bn'));

      // Household still says পারিবারিক তারিখ
      expect(groupDateScreenTitle(household, l10nBn), 'পারিবারিক তারিখ');
      expect(
          groupDateModalHeader(household, l10nBn, isAdd: true, canEdit: true),
          'নতুন পারিবারিক তারিখ');

      // School says স্কুল ও ক্লাসের সময়সূচি
      expect(groupDateScreenTitle(school, l10nBn), 'স্কুল ও ক্লাসের সময়সূচি');
      expect(groupDateModalHeader(school, l10nBn, isAdd: true, canEdit: true),
          'নতুন স্কুল বা পরীক্ষার তারিখ');
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
