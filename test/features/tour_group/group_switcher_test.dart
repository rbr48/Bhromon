import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/active_group.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

// A switcher chip expands that group inline and makes that group the active one,
// the same as a tap on its card.

class _Repo extends TourGroupRepository {
  _Repo({required this.groups});

  final List<TourGroup> groups;

  @override
  String get currentEmail => 'me@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(const []);

  @override
  Stream<bool> watchIsMember(String tourId) => Stream.value(true);
}

TourGroup _trip(String id, String name) => TourGroup(
      id: id,
      name: name,
      ownerEmail: 'me@bhromon.fun',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      tourType: TourType.hill,
    );

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_switch').path);
    // The app opens this box at start-up; the active group is saved in it.
    await Hive.openBox<dynamic>('tour_groups_box');
  });

  testWidgets(
      'a switcher chip expands that group inline and makes it the active group',
      (tester) async {
    final repo = _Repo(groups: [_trip('a', 'Sajek'), _trip('b', 'Bandarban')]);
    final router = GoRouter(
      initialLocation: '/group-hub',
      routes: [
        GoRoute(
          path: '/group-hub',
          builder: (context, state) => TourGroupHubScreen(
            repository: repo,
            initialTourId: state.uri.queryParameters['tourId'],
            preference: TourHubPreference(),
            groupsV2: true,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bandarban'));
    await tester.pumpAndSettle();

    // The selection is written asynchronously; give the write time to land.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(ActiveGroup.instance.current, 'b');
  });
}
