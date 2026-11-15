import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/bhromon_bottom_nav.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/desktop_right_dock.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/desktop_tour_sidebar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/shell_page_route.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/trip_shell.dart';

void main() {
  test('each tour screen sits under the tab it belongs to', () {
    expect(tripTabFor('/group/t1/channels'), 1);
    expect(tripTabFor('/group/t1/feed'), 2);
    expect(tripTabFor('/chats'), 3);
    expect(tripTabFor('/profile/u1'), 4);
    for (final screen in [
      'journey',
      'checklist',
      'notices',
      'logistics',
      'tide',
      'ledger',
      'safety',
      'quiz',
      'scrapbook',
    ]) {
      expect(tripTabFor('/group/t1/$screen'), 0, reason: screen);
    }
  });

  test('each tab opens its own route, in the same order as the mapping', () {
    final paths = tripTabPaths('t1');
    expect(paths, hasLength(5));
    for (var i = 0; i < paths.length; i++) {
      expect(tripTabFor(paths[i]), i, reason: paths[i]);
    }
  });

  group('navigation from the group hub', () {
    late GoRouter router;

    setUpAll(() {
      // The shell remembers the last tour in a Hive box, so give Hive a
      // directory to write to, as the app does at startup.
      Hive.init(Directory.systemTemp.createTempSync('bhromon_nav').path);
    });

    setUp(() {
      // The same shape as the app: the hub is a root route, and each trip
      // screen is its own route wrapped in TripShell.
      router = GoRouter(
        initialLocation: '/hub',
        routes: [
          GoRoute(
            path: '/hub',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/group/t1/journey'),
                child: const Text('open journey'),
              ),
            ),
          ),
          for (final screen in ['feed', 'journey', 'ledger'])
            GoRoute(
              path: '/group/:tourId/$screen',
              builder: (context, state) => TripShell(
                tourId: state.pathParameters['tourId']!,
                location: state.uri.path,
                repository: _NoFirebaseRepository(_trip),
                child: _Screen(screen),
              ),
            ),
        ],
      );
    });

    testWidgets('a trip screen keeps its back button', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open journey'));
      await tester.pumpAndSettle();

      expect(find.text('body of journey'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('switching tabs keeps the hub underneath', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open journey'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();
      expect(find.text('body of feed'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open journey'), findsOneWidget);
    });

    testWidgets('a wide window shows the tabs in the side bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open journey'));
      await tester.pumpAndSettle();

      expect(find.byType(DesktopTourSidebar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();
      expect(find.text('body of feed'), findsOneWidget);
    });

    testWidgets('on a wide window the content stops at the width cap',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open journey'));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(_Screen)).width,
        TripShell.contentMaxWidth,
      );
    });

    testWidgets('a group chat on a phone keeps the tab bar', (tester) async {
      await _pumpPhone(tester, hideNavWhileTyping: true);

      expect(find.text('body of channels'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets(
        'a group chat on a phone takes the tab bar away while the keyboard is open',
        (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      await _pumpPhone(tester, hideNavWhileTyping: true);

      expect(find.text('body of channels'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets(
        'a trip screen on a phone keeps the tab bar with the keyboard open',
        (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      await _pumpPhone(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('the desktop shell', () {
    testWidgets('a study circle is offered its study tools, not a trip\'s',
        (tester) async {
      await _pumpDesktop(tester, width: 1150, group: _studyCircle);

      expect(find.byIcon(Icons.school_outlined), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      // No seat plan, route, packing list or scrapbook for a study circle.
      expect(
          find.byIcon(Icons.airline_seat_recline_extra_outlined), findsNothing);
      expect(find.byIcon(Icons.alt_route_outlined), findsNothing);
      expect(find.byIcon(Icons.fact_check_outlined), findsNothing);
      expect(find.byIcon(Icons.auto_stories_outlined), findsNothing);
    });

    testWidgets('a trip is offered its trip tools', (tester) async {
      await _pumpDesktop(tester, width: 1150, group: _trip);

      expect(find.byIcon(Icons.airline_seat_recline_extra_outlined),
          findsOneWidget);
      expect(find.byIcon(Icons.alt_route_outlined), findsOneWidget);
      expect(find.byIcon(Icons.school_outlined), findsNothing);
    });

    testWidgets('the dock is left out where it would squeeze the page',
        (tester) async {
      await _pumpDesktop(tester, width: 1150, group: _trip);

      expect(find.byType(DesktopTourSidebar), findsOneWidget);
      expect(find.byType(DesktopRightDock), findsNothing);
      // 1150 less the 260 of the side bar.
      expect(tester.getSize(find.byType(_Screen)).width, 890);
    });

    testWidgets('a wide window has the dock too', (tester) async {
      await _pumpDesktop(tester, width: 1400, group: _trip);

      expect(find.byType(DesktopRightDock), findsOneWidget);
      expect(tester.getSize(find.byType(_Screen)).width, 1400 - 260 - 280);
    });

    testWidgets('the page is told its own width, not the window\'s',
        (tester) async {
      late double told;
      await _pumpDesktop(
        tester,
        width: 1400,
        group: _trip,
        child: Builder(builder: (context) {
          told = MediaQuery.sizeOf(context).width;
          return const _Screen('notices');
        }),
      );

      expect(told, 1400 - 260 - 280);
    });

    testWidgets('a screen with its own tab bar shows none on a desktop window',
        (tester) async {
      await _pumpDesktop(
        tester,
        width: 1150,
        group: _trip,
        child: const Scaffold(
          body: Text('own bar'),
          bottomNavigationBar: BhromonBottomNav(selectedIndex: 0),
        ),
      );

      expect(find.text('own bar'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    test('the dock never repeats the list the page is showing', () {
      expect(TripShell.dockShowsGroups('/group-hub'), isFalse);
      expect(TripShell.dockShowsChats('/group-hub'), isTrue);
      expect(TripShell.dockShowsChats('/chats'), isFalse);
      expect(TripShell.dockShowsChats('/chat/abc'), isFalse);
      expect(TripShell.dockShowsGroups('/chats'), isTrue);
      expect(TripShell.dockShowsGroups('/group/t1/notices'), isTrue);
      expect(TripShell.dockShowsChats('/group/t1/notices'), isTrue);
    });
  });

  group('a page opened over a tool', () {
    GoRouter routerFor(TourGroup group) => GoRouter(
          initialLocation: '/group/t1/study-subjects',
          routes: [
            for (final screen in ['study-subjects', 'notices'])
              GoRoute(
                path: '/group/:tourId/$screen',
                builder: (context, state) => TripShell(
                  tourId: 't1',
                  location: state.uri.path,
                  repository: _NoFirebaseRepository(group),
                  guardMembership: false,
                  child: Scaffold(
                    body: Column(children: [
                      Text('list of $screen'),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          ShellPageRoute<void>(
                            repository: _NoFirebaseRepository(group),
                            builder: (_) =>
                                const Scaffold(body: Text('one subject')),
                          ),
                        ),
                        child: const Text('open subject'),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        );

    testWidgets('keeps the side bar on a desktop window', (tester) async {
      tester.view.physicalSize = const Size(1150, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: routerFor(_trip)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open subject'));
      await tester.pumpAndSettle();

      expect(find.text('one subject'), findsOneWidget);
      expect(find.byType(DesktopTourSidebar), findsOneWidget);
      expect(tester.getSize(find.text('one subject')).width, lessThan(900));
    });

    testWidgets('is a plain page on a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: routerFor(_trip)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open subject'));
      await tester.pumpAndSettle();

      expect(find.text('one subject'), findsOneWidget);
      expect(find.byType(DesktopTourSidebar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('is closed when another tool is picked in the side bar',
        (tester) async {
      tester.view.physicalSize = const Size(1150, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: routerFor(_trip)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open subject'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.campaign_outlined));
      await tester.pumpAndSettle();

      expect(find.text('one subject'), findsNothing);
      expect(find.text('list of notices'), findsOneWidget);
    });
  });
}

/// Shows a trip screen at phone width. [hideNavWhileTyping] is the group chat's setting.
Future<void> _pumpPhone(WidgetTester tester,
    {bool hideNavWhileTyping = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // TripShell reads the router to decide whether the back button pops, so the
  // screen is shown under a router, as in the app.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TripShell(
          tourId: 't1',
          location: '/group/t1/channels',
          repository: _NoFirebaseRepository(),
          hideNavWhileTyping: hideNavWhileTyping,
          child: const _Screen('channels'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

TourGroup _groupOf({bool family = false, String? preset}) => TourGroup(
      id: 't1',
      name: 'G',
      ownerEmail: 'a@b.c',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 4),
      createdAt: DateTime(2026, 10, 1),
      kind: family ? GroupKind.family : GroupKind.tour,
      preset: preset,
    );

final TourGroup _trip = _groupOf();
final TourGroup _studyCircle =
    _groupOf(family: true, preset: TourGroup.studyPreset);

/// Shows one screen inside the shell in a window [width] wide.
Future<void> _pumpDesktop(
  WidgetTester tester, {
  required double width,
  TourGroup? group,
  String location = '/group/t1/notices',
  Widget child = const _Screen('notices'),
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => TripShell(
          tourId: 't1',
          location: location,
          repository: _NoFirebaseRepository(group),
          guardMembership: false,
          child: child,
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

/// A repository that never reaches Firebase. The side bar shows the group it is given.
class _NoFirebaseRepository extends TourGroupRepository {
  _NoFirebaseRepository([this.group]);

  /// The group the side bar is shown for, or none.
  final TourGroup? group;

  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(group);

  @override
  Stream<List<TourGroup>> watchMyGroups() => Stream.value(const <TourGroup>[]);
}

class _Screen extends StatelessWidget {
  const _Screen(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(child: Text('body of $name')),
    );
  }
}
