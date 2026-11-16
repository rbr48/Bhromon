import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/core/layout/breakpoints.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/active_group.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_hub_preference.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/desktop_nav.dart';
import 'package:bhromon/features/tour_group/presentation/tour_routes.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/bhromon_bottom_nav.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/desktop_right_dock.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/desktop_tour_sidebar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/trip_shell.dart';

class _FakeTourRepo extends TourGroupRepository {
  final Map<String, TourGroup> _groups;

  _FakeTourRepo(List<TourGroup> list)
      : _groups = {for (final g in list) g.id: g};

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(_groups[tourId]);

  @override
  Stream<List<TourGroup>> watchMyGroups() =>
      Stream.value(_groups.values.toList());

  @override
  String get currentUid => 'test-user-uid';

  @override
  String get currentEmail => 'user@test.com';

  @override
  String get currentDisplayName => 'Test User';
}

TourGroup _buildTestGroup({
  required String id,
  required String name,
  bool family = false,
  String? preset,
  TourType tourType = TourType.beach,
}) {
  final now = DateTime(2026, 11, 1);
  return TourGroup(
    id: id,
    name: name,
    ownerEmail: 'user@test.com',
    inviteCode: 'CODE$id',
    destination: tourType == TourType.beach ? "Cox's Bazar" : '',
    startDate: now,
    endDate: now.add(const Duration(days: 3)),
    createdAt: now,
    kind: family ? GroupKind.family : GroupKind.tour,
    preset: preset,
    tourType: tourType,
  );
}

class _FakeTourHubPreference extends TourHubPreference {
  String? _value;

  @override
  String? read() => _value;

  @override
  Future<void> remember(String tourId) async {
    _value = tourId;
  }

  @override
  Future<void> forget(String tourId) async {
    if (_value == tourId) _value = null;
  }
}

void main() {
  late TourHubPreference testPref;
  late ActiveGroup activeGroup;

  setUp(() {
    testPref = _FakeTourHubPreference();
    activeGroup = ActiveGroup(preference: testPref);
    ActiveGroup.setInstanceForTesting(activeGroup);
  });

  tearDown(() {
    ActiveGroup.resetInstanceForTesting();
  });

  final tripGroup = _buildTestGroup(
    id: 'trip-1',
    name: 'Saint Martin Tour',
    tourType: TourType.beach,
  );

  final studyGroup = _buildTestGroup(
    id: 'study-1',
    name: 'JAIBB Banking Circle',
    family: true,
    preset: TourGroup.studyPreset,
    tourType: TourType.nature,
  );

  final messGroup = _buildTestGroup(
    id: 'mess-1',
    name: 'Dhanmondi Mess',
    family: true,
    preset: TourGroup.messPreset,
    tourType: TourType.nature,
  );

  group('Group switching route resolution (pathForGroupSwitch)', () {
    test(
        'switches between groups while preserving common tools (e.g. notices, channels)',
        () {
      // Both trip and study circle have channels
      expect(
        pathForGroupSwitch(studyGroup, '/group/trip-1/channels'),
        '/group/study-1/channels',
      );
      expect(
        pathForGroupSwitch(tripGroup, '/group/study-1/channels'),
        '/group/trip-1/channels',
      );
    });

    test('redirects to group-hub when target group lacks the current tool', () {
      // Study circle does not have seats/logistics or journey
      expect(
        pathForGroupSwitch(studyGroup, '/group/trip-1/logistics'),
        '/group-hub?tourId=study-1',
      );
      expect(
        pathForGroupSwitch(studyGroup, '/group/trip-1/journey'),
        '/group-hub?tourId=study-1',
      );
      // Trip does not have study_subjects or meals
      expect(
        pathForGroupSwitch(tripGroup, '/group/study-1/study-subjects'),
        '/group-hub?tourId=trip-1',
      );
    });

    test('resolves deep nested tool routes correctly to the base tool route',
        () {
      expect(
        pathForGroupSwitch(messGroup, '/group/study-1/channels/general'),
        '/group/mess-1/channels',
      );
    });

    test(
        'switches cleanly from global screens (chats, game-zone, notifications, hub)',
        () {
      expect(
        pathForGroupSwitch(studyGroup, '/chats'),
        '/group-hub?tourId=study-1',
      );
      expect(
        pathForGroupSwitch(tripGroup, '/game-zone'),
        '/group-hub?tourId=trip-1',
      );
      expect(
        pathForGroupSwitch(messGroup, '/group-hub'),
        '/group-hub?tourId=mess-1',
      );
    });
  });

  group('ActiveGroup state machine & persistence', () {
    test('select remembers the group id and notifies stream listeners',
        () async {
      String? notifiedId;
      final sub = activeGroup.changes.listen((id) => notifiedId = id);

      expect(activeGroup.current, isNull);

      await activeGroup.select('trip-1');
      expect(activeGroup.current, 'trip-1');
      await Future<void>.delayed(Duration.zero);
      expect(notifiedId, 'trip-1');

      await activeGroup.select('study-1');
      expect(activeGroup.current, 'study-1');
      await Future<void>.delayed(Duration.zero);
      expect(notifiedId, 'study-1');

      await sub.cancel();
    });

    test('clearIf removes active group only when id matches', () async {
      await activeGroup.select('trip-1');
      expect(activeGroup.current, 'trip-1');

      await activeGroup.clearIf('other-id');
      expect(activeGroup.current, 'trip-1');

      await activeGroup.clearIf('trip-1');
      expect(activeGroup.current, isNull);
    });
  });

  group('Responsive viewport breakpoints for group switching affordances', () {
    test(
        'on mobile (<900px), bottom nav is visible, dock and sidebar are hidden',
        () {
      expect(isDesktopShellWidth(800), isFalse);
      expect(isDesktopDockWidth(800), isFalse);
    });

    test(
        'on medium desktop / laptop (900px - 1279px), right dock is hidden and bottom nav is hidden',
        () {
      const laptopWidth = 1024.0;
      expect(isDesktopShellWidth(laptopWidth), isTrue);
      expect(isDesktopDockWidth(laptopWidth), isFalse);
      // Demonstrates the "black hole" where neither bottom nav nor right dock is available
    });

    test('on wide desktop (>=1280px), both sidebar and right dock are active',
        () {
      const wideWidth = 1440.0;
      expect(isDesktopShellWidth(wideWidth), isTrue);
      expect(isDesktopDockWidth(wideWidth), isTrue);
      expect(desktopDockWidthFor(wideWidth), 320);
    });
  });

  group('DesktopRightDock group switching panel', () {
    testWidgets(
        'tapping a group in DesktopGroupListPanel selects active group and navigates',
        (tester) async {
      final repo = _FakeTourRepo([tripGroup, studyGroup, messGroup]);
      String? navigatedRoute;

      final router = GoRouter(
        initialLocation: '/chats',
        routes: [
          GoRoute(
            path: '/chats',
            builder: (context, state) => Scaffold(
              body: DesktopRightDock(
                activeTourId: 'trip-1',
                repository: repo,
                currentLocation: '/chats',
                showGroups: true,
                showChats: false,
              ),
            ),
          ),
          GoRoute(
            path: '/group-hub',
            builder: (context, state) {
              navigatedRoute =
                  '/group-hub?tourId=${state.uri.queryParameters['tourId']}';
              return const Scaffold(body: Text('Hub View'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', ''), Locale('bn', '')],
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('JAIBB Banking Circle'), findsOneWidget);
      expect(find.text('Saint Martin Tour'), findsOneWidget);

      // Tap on JAIBB study circle
      await tester.tap(find.text('JAIBB Banking Circle'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Confirms navigation triggered
      expect(navigatedRoute, '/group-hub?tourId=study-1');
    });

    testWidgets(
        'dockShowsGroups is true across all locations including /group-hub',
        (tester) async {
      expect(TripShell.dockShowsGroups('/group-hub'), isTrue);
      expect(TripShell.dockShowsGroups('/chats'), isTrue);
      expect(TripShell.dockShowsGroups('/group/trip-1/feed'), isTrue);
      expect(TripShell.dockShowsGroups('/notifications'), isTrue);
    });
  });

  group('DesktopTourSidebar group identity presentation', () {
    testWidgets(
        'sidebar displays group title, type label, and group-specific modules',
        (tester) async {
      final repo = _FakeTourRepo([studyGroup]);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', ''), Locale('bn', '')],
          home: Scaffold(
            body: DesktopTourSidebar(
              tourId: 'study-1',
              currentLocation: '/group/study-1/study-subjects',
              repository: repo,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('JAIBB Banking Circle'), findsOneWidget);
      expect(find.text('Study group'), findsOneWidget);
      // Study circle should have Study Subjects tool
      expect(find.text('Subjects'), findsOneWidget);
      // Study circle should NOT have trip-specific tools
      expect(find.text('Seat layout'), findsNothing);
      expect(find.text('Checklist'), findsNothing);
    });

    testWidgets(
        'clicking sidebar header opens DesktopGroupSwitcherDialog and allows switching',
        (tester) async {
      final repo = _FakeTourRepo([tripGroup, studyGroup]);
      String? navigatedRoute;

      final router = GoRouter(
        initialLocation: '/chats',
        routes: [
          GoRoute(
            path: '/chats',
            builder: (ctx, state) => Scaffold(
              body: DesktopTourSidebar(
                tourId: 'trip-1',
                currentLocation: '/chats',
                repository: repo,
              ),
            ),
          ),
          GoRoute(
            path: '/group-hub',
            builder: (ctx, state) {
              navigatedRoute =
                  '/group-hub?tourId=${state.uri.queryParameters['tourId']}';
              return const Scaffold(body: Text('Hub View'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', ''), Locale('bn', '')],
        ),
      );

      await tester.pumpAndSettle();

      // Tap on group title/dropdown icon in sidebar header
      await tester.tap(find.byIcon(Icons.unfold_more_rounded));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Switch Group'), findsOneWidget);
      expect(find.text('JAIBB Banking Circle'), findsOneWidget);

      // Tap on JAIBB in dialog
      await tester.tap(find.text('JAIBB Banking Circle'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(navigatedRoute, '/group-hub?tourId=study-1');
      expect(ActiveGroup.instance.current, 'study-1');
    });
  });

  group('TripShell dynamic active group synchronization', () {
    testWidgets(
        'TripShell dynamically updates sidebar when ActiveGroup emits new group on /group-hub',
        (tester) async {
      final repo = _FakeTourRepo([tripGroup, studyGroup]);

      final router = GoRouter(
        initialLocation: '/group-hub',
        routes: [
          GoRoute(
            path: '/group-hub',
            builder: (ctx, state) => MediaQuery(
              data: const MediaQueryData(size: Size(1366, 768)),
              child: TripShell(
                tourId: 'trip-1',
                location: '/group-hub',
                repository: repo,
                child: const Text('Hub Content'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', ''), Locale('bn', '')],
        ),
      );

      await tester.pumpAndSettle();

      // Initially displays Saint Martin Tour in both sidebar and right dock
      expect(
        find.descendant(
          of: find.byType(DesktopTourSidebar),
          matching: find.text('Saint Martin Tour'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopRightDock),
          matching: find.text('Saint Martin Tour'),
        ),
        findsOneWidget,
      );
      expect(find.text('Shared fund & ledger'), findsOneWidget);
      expect(find.text('Subjects'), findsNothing);

      // Now user selects study group in hub (which calls ActiveGroup.select)
      await tester.runAsync(() async {
        await ActiveGroup.instance.select('study-1');
      });
      await tester.pumpAndSettle();

      // Sidebar dynamically reflects the new group without route push!
      expect(
        find.descendant(
          of: find.byType(DesktopTourSidebar),
          matching: find.text('JAIBB Banking Circle'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopTourSidebar),
          matching: find.text('Study group'),
        ),
        findsOneWidget,
      );
      expect(find.text('Subjects'), findsOneWidget);
      expect(find.text('Shared fund & ledger'), findsNothing);
    });
  });
}
