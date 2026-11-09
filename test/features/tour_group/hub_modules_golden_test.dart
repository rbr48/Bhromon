// Golden for the hub's group tools: the tiles each group type shows, in order, for every
// combination of Moments, games, chat, seats and tide. Capture it on the base code with
//   flutter test test/features/tour_group/hub_modules_golden_test.dart --dart-define=CAPTURE_HUB_MODULES=true
// and check it with the same command without the define.
import 'dart:convert';
import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/family_date_models.dart';
import 'package:bhromon/features/tour_group/domain/models/family_task_models.dart';
import 'package:bhromon/features/tour_group/domain/models/meal_log.dart';
import 'package:bhromon/features/tour_group/domain/models/mess_bazar_model.dart';
import 'package:bhromon/features/tour_group/domain/models/safety_alert_models.dart';
import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/service_request_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _goldenPath = 'test/features/tour_group/goldens/hub_modules_golden.json';
const _capture = bool.fromEnvironment('CAPTURE_HUB_MODULES');
const _noticesTitle = 'Notice board';

class _Repo extends TourGroupRepository {
  _Repo(this.groups);

  final List<TourGroup> groups;

  @override
  String get currentEmail => 'tester@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  // The family card reads these. Empty lists keep the test to the group tools.
  @override
  Stream<List<TourNotice>> watchNotices(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<FamilyDate>> watchFamilyDates(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<FamilyTask>> watchFamilyTasks(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<BatteryTelemetry>> watchBatteryTelemetry(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<MealLog>> watchMealsForMonth(String tourId, DateTime month) =>
      Stream.value(const []);
  @override
  Stream<MessBazarSchedule?> watchBazarScheduleForDay(String tourId, String dateKey) => Stream.value(null);


  @override
  Stream<List<ServiceRequest>> watchServiceRequests(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<SamityPayment>> watchSamityPayments(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<SamityPayout>> watchSamityPayouts(String tourId) =>
      Stream.value(const []);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) => Stream.value([
        TourMember(
          tourId: tourId,
          email: currentEmail,
          displayName: 'Organizer',
          role: TourRole.owner,
          status: TourMemberStatus.active,
          joinedAt: DateTime(2026, 10, 1),
          familyCount: 2,
        ),
      ]);
}

TourGroup _group(
  String id,
  Map<String, bool> flags, {
  bool family = false,
  String? preset,
  TourType type = TourType.beach,
}) {
  return TourGroup(
    id: id,
    name: 'Group $id',
    ownerEmail: 'tester@bhromon.fun',
    inviteCode: 'ABCDEFGH',
    startDate: DateTime(2026, 11, 1),
    endDate: DateTime(2026, 11, 4),
    createdAt: DateTime(2026, 10, 1),
    kind: family ? GroupKind.family : GroupKind.tour,
    preset: preset,
    tourType: type,
    momentsEnabled: flags['moments']!,
    modules: TourModules(
      games: flags['games']!,
      chat: flags['chat']!,
      seatsRooms: flags['seats']!,
      tideSafety: flags['tide']!,
    ),
  );
}

/// Every base group type. Each one is rendered with every flag combination.
final _bases = <String, TourGroup Function(Map<String, bool>)>{
  'household': (f) => _group('household', f, family: true),
  'family-study': (f) =>
      _group('family-study', f, family: true, preset: TourGroup.studyPreset),
  'office': (f) =>
      _group('office', f, family: true, preset: TourGroup.officePreset),
  'campus': (f) =>
      _group('campus', f, family: true, preset: TourGroup.campusPreset),
  'mess': (f) => _group('mess', f, family: true, preset: TourGroup.messPreset),
  'society': (f) =>
      _group('society', f, family: true, preset: TourGroup.societyPreset),
  'samity': (f) =>
      _group('samity', f, family: true, preset: TourGroup.samityPreset),
  'committee': (f) =>
      _group('committee', f, family: true, preset: TourGroup.committeePreset),
  'school': (f) =>
      _group('school', f, family: true, preset: TourGroup.schoolPreset),
  'sports': (f) =>
      _group('sports', f, family: true, preset: TourGroup.sportsPreset),
  'friends': (f) =>
      _group('friends', f, family: true, preset: TourGroup.friendsPreset),
  'trip-beach': (f) => _group('trip-beach', f, type: TourType.beach),
  'trip-hill': (f) => _group('trip-hill', f, type: TourType.hill),
};

Iterable<Map<String, bool>> _flagCombinations() sync* {
  for (final moments in [true, false]) {
    for (final games in [true, false]) {
      for (final chat in [true, false]) {
        for (final seats in [true, false]) {
          for (final tide in [true, false]) {
            yield {
              'moments': moments,
              'games': games,
              'chat': chat,
              'seats': seats,
              'tide': tide,
            };
          }
        }
      }
    }
  }
}

String _keyFor(String base, Map<String, bool> flags) =>
    '$base|${flags.entries.map((e) => '${e.key}=${e.value ? 1 : 0}').join(',')}';

/// The titles of the tiles in the modules grid, in order. Each tile holds a title and a
/// subtitle, so the titles are every other text.
List<String> _moduleTitles(WidgetTester tester, String key) {
  final grids = find.byType(GridView);
  for (var i = 0; i < grids.evaluate().length; i++) {
    final texts = tester
        .widgetList<Text>(
            find.descendant(of: grids.at(i), matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .toList();
    if (texts.contains(_noticesTitle)) {
      expect(texts.length.isEven, isTrue,
          reason: 'each module tile holds a title and a subtitle');
      return [for (var j = 0; j < texts.length; j += 2) texts[j]];
    }
  }
  fail(
      'the modules grid was not found for $key (grids: ${find.byType(GridView).evaluate().length})');
}

void main() {
  setUpAll(() {
    // The hub remembers the last group in a Hive box, so give Hive a directory.
    Hive.init(Directory.systemTemp.createTempSync('bhromon_golden').path);
  });

  testWidgets(
      'the group tools are the same for every type and flag combination',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final results = <String, List<String>>{};
    for (final base in _bases.entries) {
      for (final flags in _flagCombinations()) {
        final group = base.value(flags);
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('bn')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          // A new key gives each case a new hub, so no state carries over.
          home: TourGroupHubScreen(
            key: UniqueKey(),
            repository: _Repo([group]),
            // The module grid belongs to the hub's original layout.
            groupsV2: false,
          ),
        ));
        await tester.pumpAndSettle();
        // A family card builds its own repository, which needs Firebase; in this test
        // that error is not part of the group tools, so it is cleared here.
        final ignored = tester.takeException();
        if (ignored != null && ignored is! FirebaseException) {
          fail('unexpected error for ${_keyFor(base.key, flags)}: $ignored');
        }
        results[_keyFor(base.key, flags)] =
            _moduleTitles(tester, _keyFor(base.key, flags));
      }
    }

    if (_capture) {
      File(_goldenPath).writeAsStringSync(
          const JsonEncoder.withIndent(' ').convert(results));
      return;
    }
    final golden = jsonDecode(File(_goldenPath).readAsStringSync())
        as Map<String, dynamic>;
    expect(results.keys.toSet(), golden.keys.toSet(),
        reason: 'the set of cases changed');
    for (final key in results.keys) {
      expect(results[key], (golden[key] as List).cast<String>(), reason: key);
    }
  });
}
