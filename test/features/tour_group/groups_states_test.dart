import 'dart:async';
import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_group_hub_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

// The states the groups list and the group page must show (plan section 5.2): an error
// with a retry, the offline banner, and a viewer removed while a group page is open.

const _offline = 'You are offline. These groups are saved on this device.';
const _removed = 'You are no longer a member of this group.';

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

class _Repo extends TourGroupRepository {
  _Repo({required this.groups, this.membership});

  final List<TourGroup> groups;

  /// The viewer's membership of a tour, as the guard sees it. Null means always a member.
  final Stream<bool>? membership;

  @override
  String get currentEmail => 'me@bhromon.fun';

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(groups);

  @override
  Stream<List<TourGroup>> restartMyGroups() => Stream.value(groups);

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(const []);

  @override
  Stream<bool> watchIsMember(String tourId) => membership ?? Stream.value(true);

  @override
  Future<void> clearLocalTourData(String tourId) async {}
}

/// Fails the first time the groups are read, and answers the retry.
class _FlakyRepo extends _Repo {
  _FlakyRepo({required super.groups});

  int restarts = 0;

  @override
  Stream<List<TourGroup>> watchMyGroups() =>
      Stream.error(StateError('no connection'));

  @override
  Stream<List<TourGroup>> restartMyGroups() {
    restarts++;
    return Stream.value(groups);
  }
}

TourGroupHubScreen _hub(TourGroupRepository repo, {String? routeId}) {
  return TourGroupHubScreen(
    repository: repo,
    initialTourId: routeId,
    preference: TourHubPreference(),
    groupsV2: true,
  );
}

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: home,
  );
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(home));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_states').path);
  });

  tearDown(() {
    TourGroupRepository.groupsServedFromCache.value = false;
  });

  testWidgets(
      'when the groups cannot load, the list says so, and Try again reads them',
      (tester) async {
    final repo = _FlakyRepo(groups: [_trip('t1')]);
    await _pump(tester, _hub(repo));

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Sajek t1'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repo.restarts, 1, reason: 'the retry reads the groups again');
    expect(find.text('Sajek t1'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets(
      'the groups offline banner shows once its answer is from the cache',
      (tester) async {
    final fromCache = ValueNotifier<bool>(false);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: GroupsOfflineBanner(
          fromCache: fromCache,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    fromCache.value = true;
    await tester.pump(const Duration(seconds: 8));
    expect(find.text(_offline), findsOneWidget);
  });

  testWidgets(
      'a viewer removed while viewing a group sees a notice',
      (tester) async {
    final membership = StreamController<bool>.broadcast();
    addTearDown(membership.close);
    final repo = _Repo(groups: [_trip('t1')], membership: membership.stream);
    final router = GoRouter(
      initialLocation: '/group-hub',
      routes: [
        GoRoute(
          path: '/group-hub',
          builder: (context, state) => _hub(
            repo,
            routeId: state.uri.queryParameters['tourId'],
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

    await tester.tap(find.text('Sajek t1'));
    await tester.pumpAndSettle();

    membership.add(true);
    await tester.pump();
    membership.add(false);
    await tester.pumpAndSettle();

    expect(find.text('Sajek t1'), findsOneWidget, reason: 'on the list');
    expect(find.text(_removed), findsOneWidget, reason: 'with the notice');
  });
}
