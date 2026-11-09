import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/family_date_models.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/models/meal_log.dart';
import 'package:bhromon/features/tour_group/domain/models/mess_bazar_model.dart';
import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/service_request_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_today_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/family/family_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/campus_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/community_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/mess_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/office_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/preset_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/samity_home_card.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/hub/society_home_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTourGroupRepository extends TourGroupRepository {
  @override
  String get currentEmail => 'test@bhromon.fun';

  // The study group's Today card on the home reads these. Empty here, so the card says that nothing is due.
  @override
  Stream<List<StudySubject>> watchStudySubjects(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<StudyBook>> watchStudyBooks(String tourId) =>
      Stream.value(const []);

  @override
  Future<List<StudyDeadline>> loadStudyDeadlines(String tourId) async =>
      const [];

  @override
  Stream<List<FamilyDate>> watchFamilyDates(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<FamilyTask>> watchFamilyTasks(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<TourNotice>> watchNotices(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<BatteryTelemetry>> watchBatteryTelemetry(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<MealLog>> watchMealsForMonth(String tourId, DateTime month) =>
      Stream.value(const []);

  @override
  Stream<List<ServiceRequest>> watchServiceRequests(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<SamityPayment>> watchSamityPayments(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<SamityPayout>> watchSamityPayouts(String tourId) =>
      Stream.value(const []);

// The mess card reads today's bazar duty and the caller's role when it opens. Without these overrides the
  // real repository reaches Firestore, which the test does not set up.
  @override
  Stream<MessBazarSchedule?> watchBazarScheduleForDay(
          String tourId, String dateKey) =>
      Stream.value(null);

  @override
  Future<TourRole?> myRole(String tourId) async => null;
}

TourGroup _makeGroup({String? preset, SamityConfig? samity}) => TourGroup(
      id: 'g_test',
      name: 'Test Group',
      ownerEmail: 'owner@test.com',
      inviteCode: 'TEST1234',
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 5),
      createdAt: DateTime(2026, 2, 1),
      kind: GroupKind.family,
      preset: preset,
      samity: samity ?? const SamityConfig(),
    );

void main() {
  final fakeRepo = _FakeTourGroupRepository();

  group('PresetHomeCard dispatcher', () {
    testWidgets('renders FamilyHomeCard for household', (tester) async {
      final group = _makeGroup();
      expect(group.isHousehold, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresetHomeCard(group: group, repository: fakeRepo),
          ),
        ),
      );

      expect(find.byType(FamilyHomeCard), findsOneWidget);
    });

    testWidgets('renders MessHomeCard for mess preset', (tester) async {
      final group = _makeGroup(preset: TourGroup.messPreset);
      expect(group.isMess, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresetHomeCard(group: group, repository: fakeRepo),
          ),
        ),
      );

      expect(find.byType(MessHomeCard), findsOneWidget);
    });

    testWidgets('renders SocietyHomeCard for society preset', (tester) async {
      final group = _makeGroup(preset: TourGroup.societyPreset);
      expect(group.isSociety, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresetHomeCard(group: group, repository: fakeRepo),
          ),
        ),
      );

      expect(find.byType(SocietyHomeCard), findsOneWidget);
    });

    testWidgets('renders SamityHomeCard for samity preset', (tester) async {
      final group = _makeGroup(preset: TourGroup.samityPreset);
      expect(group.isSamity, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresetHomeCard(group: group, repository: fakeRepo),
          ),
        ),
      );

      expect(find.byType(SamityHomeCard), findsOneWidget);
    });

    testWidgets('renders OfficeHomeCard for office preset', (tester) async {
      final group = _makeGroup(preset: TourGroup.officePreset);
      expect(group.isOffice, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresetHomeCard(group: group, repository: fakeRepo),
          ),
        ),
      );

      expect(find.byType(OfficeHomeCard), findsOneWidget);
    });

    testWidgets('renders CampusHomeCard for campus preset', (tester) async {
      final group = _makeGroup(preset: TourGroup.campusPreset);
      expect(group.isCampus, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresetHomeCard(group: group, repository: fakeRepo),
          ),
        ),
      );

      expect(find.byType(CampusHomeCard), findsOneWidget);
    });

    testWidgets(
        'renders CommunityHomeCard for friends, school, sports, study, committee',
        (tester) async {
      for (final preset in [
        TourGroup.friendsPreset,
        TourGroup.schoolPreset,
        TourGroup.sportsPreset,
        TourGroup.studyPreset,
        TourGroup.committeePreset,
      ]) {
        final group = _makeGroup(preset: preset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PresetHomeCard(group: group, repository: fakeRepo),
            ),
          ),
        );

        expect(find.byType(CommunityHomeCard), findsOneWidget);
      }
    });
  });

  group('Hub Preset Localization Keys', () {
    final en = TourTranslationKeys.localizedValues['en']!;
    final bn = TourTranslationKeys.localizedValues['bn']!;

    const requiredKeys = [
      'mess_home_title',
      'mess_home_today_meals',
      'mess_home_no_meals',
      'mess_home_my_meals',
      'mess_home_my_meals_none',
      'mess_home_bazar_tasks',
      'mess_home_bazar_empty',
      'mess_home_log_meals_btn',
      'mess_home_bazar_btn',
      'society_home_title',
      'society_home_requests_open',
      'society_home_requests_all_good',
      'society_home_report_btn',
      'society_home_notices_btn',
      'samity_home_title',
      'samity_home_cycle_info',
      'samity_home_payout_to',
      'samity_home_paid',
      'samity_home_due',
      'samity_home_setup_needed',
      'samity_home_view_btn',
      'samity_home_fund_btn',
      'office_home_title',
      'office_home_notices_none',
      'office_home_lunch_btn',
      'office_home_notices_btn',
      'campus_home_title',
      'campus_home_notices_none',
      'campus_home_snacks_btn',
      'campus_home_notices_btn',
      'school_home_title',
      'friends_home_title',
      'friends_home_hangout_btn',
      'friends_home_plans_btn',
      'sports_home_title',
      'study_home_title',
      'committee_home_title',
      'community_home_tasks_btn',
      'community_home_notices_btn',
    ];

    test('all required keys are present and non-empty in English and Bengali',
        () {
      for (final key in requiredKeys) {
        expect(en[key], isNotNull, reason: 'Missing EN key: $key');
        expect(en[key]!.trim(), isNotEmpty, reason: 'Empty EN key: $key');
        expect(bn[key], isNotNull, reason: 'Missing BN key: $key');
        expect(bn[key]!.trim(), isNotEmpty, reason: 'Empty BN key: $key');
      }
    });
  });
}
