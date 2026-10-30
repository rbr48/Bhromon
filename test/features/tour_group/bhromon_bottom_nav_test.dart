import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/bhromon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

/// A tour-less stand-in for a tour screen: the screen's tour, if any, comes in
/// through its address, the way the app's own tour screens receive it.
GoRouter _router(String location) => GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => Scaffold(
            body: const Text('start page'),
            bottomNavigationBar: BhromonBottomNav(
              selectedIndex: int.parse(state.uri.queryParameters['tab'] ?? '0'),
              tourId: state.uri.queryParameters['tourId'],
            ),
          ),
        ),
        GoRoute(
          path: '/group-hub',
          builder: (context, state) => Scaffold(
            body:
                Text('hub page ${state.uri.queryParameters['tourId'] ?? '-'}'),
          ),
        ),
        GoRoute(
          path: '/group/:tourId/feed',
          builder: (context, state) =>
              Text('feed of ${state.pathParameters['tourId']}'),
        ),
        GoRoute(
          path: '/group/:tourId/channels',
          builder: (context, state) =>
              Text('channels of ${state.pathParameters['tourId']}'),
        ),
        GoRoute(
          path: '/game-zone',
          builder: (context, state) =>
              Text('games of ${state.uri.queryParameters['tourId']}'),
        ),
      ],
    );

Future<void> _pumpAt(WidgetTester tester, String location) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: _router(location),
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('bhromon_nav').path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('a tour tab opens the tour the screen belongs to', () {
    testWidgets('Moments opens the feed of that tour', (tester) async {
      await _pumpAt(tester, '/start?tourId=tour_a');

      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      expect(find.text('feed of tour_a'), findsOneWidget);
    });

    testWidgets('Channels opens the channels of that tour', (tester) async {
      await _pumpAt(tester, '/start?tourId=tour_a');

      await tester.tap(find.text('Channels'));
      await tester.pumpAndSettle();

      expect(find.text('channels of tour_a'), findsOneWidget);
    });

    testWidgets('Game Zone carries that tour in its address', (tester) async {
      await _pumpAt(tester, '/start?tourId=tour_a');

      await tester.tap(find.text('Game Zone'));
      await tester.pumpAndSettle();

      expect(find.text('games of tour_a'), findsOneWidget);
    });

    testWidgets('Tours opens the hub on that tour', (tester) async {
      await _pumpAt(tester, '/start?tab=1&tourId=tour_a');

      await tester.tap(find.text('Tours'));
      await tester.pumpAndSettle();

      expect(find.text('hub page tour_a'), findsOneWidget);
    });
  });

  group('a screen without a tour', () {
    testWidgets('Moments goes to the hub, which asks for a tour first',
        (tester) async {
      await _pumpAt(tester, '/start');

      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      expect(find.text('hub page -'), findsOneWidget);
      expect(
        find.text(
            'মোমেন্টস দেখতে অনুগ্রহ করে একটি ট্যুর গ্রুপ নির্বাচন বা তৈরি করুন।'),
        findsOneWidget,
      );
    });

    testWidgets('does not borrow the tour the hub remembers', (tester) async {
      final box = await tester.runAsync(
        () => Hive.openBox<dynamic>('tour_groups_box'),
      );
      await tester.runAsync(
        () => box!.put('last_active_tour_id', 'tour_b'),
      );
      addTearDown(
          () => tester.runAsync(() => box!.delete('last_active_tour_id')));

      await _pumpAt(tester, '/start');

      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      expect(find.text('hub page -'), findsOneWidget);
      expect(find.text('feed of tour_b'), findsNothing);
    });
  });
}
