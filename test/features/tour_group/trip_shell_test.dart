import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/desktop_tour_sidebar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/trip_shell.dart';

void main() {
  test('each tour screen sits under the tab it belongs to', () {
    expect(tripTabFor('/group/t1/feed'), 1);
    expect(tripTabFor('/group/t1/channels'), 2);
    expect(tripTabFor('/game-zone'), 3);
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
                repository: _NoFirebaseRepository(),
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
  });
}

/// A repository that never reaches Firebase. The side rail shows no group,
/// which is all these navigation tests need.
class _NoFirebaseRepository extends TourGroupRepository {
  @override
  Stream<TourGroup?> watchGroup(String tourId) => Stream.value(null);
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
