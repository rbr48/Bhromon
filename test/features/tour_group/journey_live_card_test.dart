import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/journey_alarm_scheduler.dart';
import 'package:bhromon/features/tour_group/data/journey_prefs_store.dart';
import 'package:bhromon/features/tour_group/data/live_journey_session.dart';
import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_alert_presentation.dart';
import 'package:bhromon/features/tour_group/domain/services/live_journey_tracker.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/journey/journey_live_card.dart';

import 'live_journey_test_support.dart';

class _NoAlarms implements JourneyNotificationPort {
  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required JourneyChannel channel,
    required bool rings,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}

class _NoNotices implements JourneyNoticePort {
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required JourneyChannel channel,
    required bool rings,
    required String payload,
  }) async {}
}

class _NoEvents implements JourneyEventSink {
  @override
  Future<void> record({
    required String tourId,
    required String stopId,
    required JourneyEventType type,
  }) async {}
}

TourGroup _group({bool located = true}) => TourGroup(
      id: 'tour-1',
      name: 'Trip',
      destination: 'Test',
      originCity: 'Nowhere',
      ownerEmail: 'o@x.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2027, 1, 13),
      endDate: DateTime(2027, 1, 20),
      createdAt: DateTime(2026, 10, 1),
      stops: [
        TourStop(
          id: 'hub',
          name: 'Hub',
          arrive: DateTime(2027, 1, 14),
          leave: DateTime(2027, 1, 14),
          lat: located ? kRouteB.lat : null,
          lng: located ? kRouteB.lng : null,
        ),
        TourStop(
          id: 'end',
          name: 'Destination',
          arrive: DateTime(2027, 1, 15),
          leave: DateTime(2027, 1, 15),
          lat: located ? kRouteC.lat : null,
          lng: located ? kRouteC.lng : null,
        ),
      ],
      legPlans: const {},
      returnHome: false,
    );

const _copy = JourneyServiceCopy(
    title: 'Journey', tracking: 'Tracking', sharing: 'Sharing');

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

LiveJourneySession _session(DateTime Function() now) => LiveJourneySession(
      store: JourneyPrefsStore(MemoryJourneyPrefsBackend()),
      fixes: (plan, title, text) => const Stream<JourneyFix>.empty(),
      scheduler: JourneyAlarmScheduler(port: _NoAlarms()),
      notices: _NoNotices(),
      events: _NoEvents(),
      text: (t) => t.key,
      formatNumber: (n) => '$n',
      onRing: (_) {},
      now: now,
    );

void main() {
  final replan = Uri.parse('https://www.google.com/maps/dir/?api=1');

  Future<void> pumpCard(
    WidgetTester tester,
    LiveJourneySession session, {
    Uri? replanUri,
  }) async {
    await tester.pumpWidget(_app(JourneyLiveCard(
      session: session,
      onStart: () async {},
      onAlarmSettings: () {},
      replanUri: replanUri,
    )));
    // The localizations load after the first frame.
    await tester.pump();
  }

  testWidgets('before a trip the card explains tracking and offers to start',
      (tester) async {
    final session = _session(() => DateTime.utc(2027, 1, 13, 20));
    addTearDown(session.stop);
    await pumpCard(tester, session);

    expect(find.text('Start journey'), findsOneWidget);
    expect(find.textContaining('Tracking runs only during a journey'),
        findsOneWidget);
    expect(find.text('End journey'), findsNothing);
  });

  testWidgets(
      'a started trip shows its progress along the route, then the speed',
      (tester) async {
    var clock = DateTime.utc(2027, 1, 13, 20);
    final session = _session(() => clock);
    await session.start(
      group: _group(),
      tripId: 'trip-1',
      plannedFinalEta: null,
      copy: _copy,
    );
    await pumpCard(tester, session, replanUri: replan);

    expect(find.text('Tracking this journey'), findsOneWidget,
        reason: 'no reading yet');
    expect(find.text('End journey'), findsOneWidget);
    expect(find.text('Start journey'), findsNothing);

    clock = clock.add(const Duration(minutes: 1));
    await session.onFix(JourneyFix(
      lat: eastOf(kRouteB, -8000).lat,
      lng: eastOf(kRouteB, -8000).lng,
      time: clock,
      accuracyM: 5,
      speedMps: 16,
    ));
    await tester.pump();

    expect(find.textContaining('km to Destination'), findsOneWidget);
    expect(find.textContaining('km/h'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Open in Google Maps'), findsNothing,
        reason: 'the group is on the route');
    await session.stop();
  });

  testWidgets(
      'off the route the card says so and offers a re-plan in Google Maps',
      (tester) async {
    var clock = DateTime.utc(2027, 1, 13, 20);
    final session = _session(() => clock);
    await session.start(
      group: _group(),
      tripId: 'trip-1',
      plannedFinalEta: null,
      copy: _copy,
    );
    await pumpCard(tester, session, replanUri: replan);

    // Three readings about 3 km north of the route: the tracker calls it off route.
    final away = northOf(eastOf(kRouteB, -8000), 3000);
    for (var i = 0; i < 3; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await session.onFix(JourneyFix(
        lat: away.lat,
        lng: away.lng,
        time: clock,
        accuracyM: 5,
        speedMps: 16,
      ));
    }
    await tester.pump();

    expect(find.text('The group is off the planned route.'), findsOneWidget);
    expect(find.text('Open in Google Maps'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'the progress along the route means nothing off it');
    await session.stop();
  });

  testWidgets('a long stop asks once, and keeping tracking hides the question',
      (tester) async {
    var clock = DateTime.utc(2027, 1, 13, 20);
    final session = _session(() => clock);
    await session.start(
      group: _group(),
      tripId: 'trip-1',
      plannedFinalEta: null,
      copy: _copy,
    );
    await pumpCard(tester, session);

    final still = eastOf(kRouteB, -8000);
    for (var i = 0; i < 32; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await session.onFix(JourneyFix(
        lat: still.lat,
        lng: still.lng,
        time: clock,
        accuracyM: 5,
        speedMps: 0,
      ));
    }
    await tester.pump();

    expect(find.textContaining('Still for 30 minutes'), findsOneWidget);
    await tester.tap(find.text('Keep tracking'));
    await tester.pump();
    expect(find.textContaining('Still for 30 minutes'), findsNothing);
    await session.stop();
  });

  testWidgets('a trip with no located stop says there are no notices',
      (tester) async {
    final session = _session(() => DateTime.utc(2027, 1, 13, 20));
    await session.start(
      group: _group(located: false),
      tripId: 'trip-1',
      plannedFinalEta: null,
      copy: _copy,
    );
    await pumpCard(tester, session);
    expect(find.textContaining('there are no notices'), findsOneWidget);
    await session.stop();
  });

  testWidgets('ending the trip asks first, then returns the card to idle',
      (tester) async {
    final session = _session(() => DateTime.utc(2027, 1, 13, 20));
    await session.start(
      group: _group(),
      tripId: 'trip-1',
      plannedFinalEta: null,
      copy: _copy,
    );
    await pumpCard(tester, session);

    await tester.tap(find.text('End journey'));
    await tester.pumpAndSettle();
    expect(find.text('End this journey? Tracking and alarms stop.'),
        findsOneWidget);
    await tester.tap(find.text('End journey').last);
    await tester.pumpAndSettle();

    expect(session.isTracking, isFalse);
    expect(find.text('Start journey'), findsOneWidget);
    await session.stop();
  });
}
