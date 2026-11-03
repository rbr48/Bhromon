import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

// The groups list, the group page and the members sheet, through a real router, so the
// back stack and the tool tiles behave as they do in the app.

class _Repo extends TourGroupRepository {
  _Repo({required this.groups, this.members = const []});

  final List<TourGroup> groups;
  final List<TourMember> members;

  @override
  String get currentEmail => 'me@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) {
    return Stream.multi((controller) {
      controller.add(members);
      controller.close();
    });
  }
}

TourGroup _trip(String id) => TourGroup(
      id: id,
      name: 'Sajek $id',
      ownerEmail: 'me@bhromon.fun',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      tourType: TourType.hill,
    );

TourMember _member(String name, String email, TourRole role) => TourMember(
      tourId: 't1',
      email: email,
      displayName: name,
      role: role,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026, 10, 1),
      familyCount: 1,
    );

/// The router the app uses for these screens. [feedBuilds] counts how often the feed
/// page is built, which is how often a tool tile's route opened.
GoRouter _router(_Repo repo, List<int> feedBuilds) {
  return GoRouter(
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
      GoRoute(
        path: '/group/:tourId/feed',
        builder: (context, state) {
          feedBuilds.add(1);
          return const Scaffold(body: Text('Feed page'));
        },
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  GoRouter router, {
  Size size = const Size(800, 2400),
}) async {
  tester.view.physicalSize = size;
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
}

double _listOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_nav').path);
  });

  testWidgets('a double tap on a tool tile opens its route once',
      (tester) async {
    final feedBuilds = <int>[];
    final repo = _Repo(groups: [_trip('t1')]);
    final router = _router(repo, feedBuilds);
    addTearDown(router.dispose);
    await _pump(tester, router);

    await tester.tap(find.text('Sajek t1'));
    await tester.pumpAndSettle();

    // Two taps on the same tile before the next frame: a double tap.
    final spot = tester.getCenter(find.text('Moments 📸'));
    await tester.tapAt(spot);
    await tester.tapAt(spot);
    await tester.pumpAndSettle();

    expect(find.text('Feed page'), findsOneWidget);
    expect(feedBuilds, hasLength(1),
        reason: 'the double tap opened the feed page twice');
  });

  testWidgets('going back from a group page keeps the groups list where it was',
      (tester) async {
    final groups = [for (var i = 0; i < 14; i++) _trip('g$i')];
    final repo = _Repo(groups: groups);
    final router = _router(repo, []);
    addTearDown(router.dispose);
    await _pump(tester, router, size: const Size(800, 700));

    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final before = _listOffset(tester);
    expect(before, greaterThan(0),
        reason: 'the list must scroll for this test');

    await tester.tap(find.text('Sajek g4'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to groups'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to groups'));
    await tester.pumpAndSettle();

    expect(_listOffset(tester), closeTo(before, 1.0));
  });

  testWidgets('the members sheet closes on back, and the group page stays',
      (tester) async {
    final repo = _Repo(
      groups: [_trip('t1')],
      members: [
        _member('Organizer', 'me@bhromon.fun', TourRole.owner),
        _member('Rahim', 'rahim@bhromon.fun', TourRole.member),
      ],
    );
    final router = _router(repo, []);
    addTearDown(router.dispose);
    await _pump(tester, router);

    await tester.tap(find.text('Sajek t1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Back to groups'), findsOneWidget,
        reason: 'back closed the sheet, not the group page');
  });
}
