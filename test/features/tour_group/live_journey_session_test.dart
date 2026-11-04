import 'package:bhromon/features/tour_group/data/journey_alarm_scheduler.dart';
import 'package:bhromon/features/tour_group/data/journey_prefs_store.dart';
import 'package:bhromon/features/tour_group/data/live_journey_session.dart';
import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_alert_presentation.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_trip.dart';
import 'package:bhromon/features/tour_group/domain/services/live_journey_tracker.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_alarm_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_journey_test_support.dart';

/// The route: a hub at [kRouteB] and the destination at [kRouteC], both on one
/// parallel, about 42 km apart. The origin has no coordinates, so the route is
/// the two points.
const String kHub = 'hub';
const String kEnd = 'end';
const String kTripId = 'trip-1';

TourGroup _group() => TourGroup(
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
          id: kHub,
          name: 'Hub',
          arrive: DateTime(2027, 1, 14),
          leave: DateTime(2027, 1, 14),
          lat: kRouteB.lat,
          lng: kRouteB.lng,
        ),
        TourStop(
          id: kEnd,
          name: 'Destination',
          arrive: DateTime(2027, 1, 15),
          leave: DateTime(2027, 1, 15),
          lat: kRouteC.lat,
          lng: kRouteC.lng,
        ),
      ],
      legPlans: const {},
      returnHome: false,
    );

const _copy = JourneyServiceCopy(
  title: 'Journey',
  tracking: 'Tracking',
  sharing: 'Sharing',
);

class _Clock {
  DateTime now = DateTime.utc(2027, 1, 13, 20);
}

class _FakeAlarmPort implements JourneyNotificationPort {
  final Map<int, DateTime> scheduled = {};
  final List<int> cancelled = [];

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required JourneyChannel channel,
    required bool rings,
  }) async {
    scheduled[id] = fireAt;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}

class _FakeNotices implements JourneyNoticePort {
  final List<String> titles = [];
  final List<bool> rings = [];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required JourneyChannel channel,
    required bool rings,
    required String payload,
  }) async {
    titles.add(title);
    this.rings.add(rings);
  }
}

class _FakeEvents implements JourneyEventSink {
  final List<String> recorded = [];

  @override
  Future<void> record({
    required String tourId,
    required String stopId,
    required JourneyEventType type,
  }) async {
    recorded.add('${type.name}:$stopId');
  }
}

class _Harness {
  _Harness({MemoryJourneyPrefsBackend? backend})
      : store = JourneyPrefsStore(backend ?? MemoryJourneyPrefsBackend()) {
    session = _build(store);
  }

  final _Clock clock = _Clock();
  final JourneyPrefsStore store;
  final _FakeAlarmPort alarmPort = _FakeAlarmPort();
  final _FakeNotices notices = _FakeNotices();
  final _FakeEvents events = _FakeEvents();
  final List<JourneyPresentation> rings = [];
  final List<int> sampling = [];
  late LiveJourneySession session;

  LiveJourneySession _build(JourneyPrefsStore store) {
    return LiveJourneySession(
      store: store,
      fixes: (plan, title, text) {
        sampling.add(plan.interval.inSeconds);
        return const Stream<JourneyFix>.empty();
      },
      scheduler: JourneyAlarmScheduler(port: alarmPort),
      notices: notices,
      events: events,
      text: (t) => t.key,
      formatNumber: (n) => '$n',
      onRing: rings.add,
      now: () => clock.now,
    );
  }

  /// A reading [after] the last one, at [p] and [speed] metres per second.
  Future<void> step(
    GeoPoint p, {
    Duration after = const Duration(seconds: 60),
    double speed = 16,
  }) async {
    clock.now = clock.now.add(after);
    await session.onFix(JourneyFix(
      lat: p.lat,
      lng: p.lng,
      time: clock.now,
      accuracyM: 5,
      speedMps: speed,
    ));
  }

  Future<void> start({DateTime? eta, JourneyAlarmSettings? settings}) async {
    if (settings != null) await session.updateSettings(settings);
    await session.start(
      group: _group(),
      tripId: kTripId,
      plannedFinalEta: eta,
      copy: _copy,
    );
  }
}

/// Eight kilometres west of the hub, the start of most journeys.
GeoPoint get _westOfHub => eastOf(kRouteB, -8000);

void main() {
  group('live journey session', () {
    test('an approach notice fires once as the group nears a stop', () async {
      final h = _Harness();
      await h.start();
      await h.step(_westOfHub);
      expect(h.notices.titles, isEmpty, reason: '8 km is outside 5 km');

      await h.step(eastOf(kRouteB, -4000));
      expect(h.notices.titles, ['alarm_title_approach']);

      await h.step(eastOf(kRouteB, -3500));
      expect(h.notices.titles, hasLength(1), reason: 'a threshold fires once');
    });

    test('arrival at a stop gives one notice and no ring', () async {
      final h = _Harness();
      await h.start();
      await h.step(_westOfHub);
      await h.step(eastOf(kRouteB, -900));
      expect(h.notices.titles.last, 'alarm_title_arrive');
      expect(h.notices.rings.last, isFalse);
      expect(h.rings, isEmpty);
    });

    test('arriving at the destination rings and cancels the ETA alarm',
        () async {
      final h = _Harness();
      final eta = h.clock.now.add(const Duration(hours: 2));
      await h.start(eta: eta);
      final etaId = tripAlarmId(kTripId, TripAlarmKind.etaFallback, kEnd);
      expect(h.alarmPort.scheduled.containsKey(etaId), isTrue);

      await h.step(eastOf(kRouteC, -900));
      await h.step(eastOf(kRouteC, -400));
      expect(h.rings, hasLength(1));
      expect(h.rings.single.title.key, 'alarm_title_final');
      expect(h.alarmPort.scheduled.containsKey(etaId), isFalse,
          reason: 'the destination was reached, so the time alarm is dropped');
      expect(h.alarmPort.cancelled, contains(etaId));
    });

    test('going past the destination without arriving rings the overshoot',
        () async {
      final h = _Harness();
      await h.start();
      await h.step(eastOf(kRouteC, -900));
      await h.step(eastOf(kRouteC, 1300));
      expect(h.rings.map((r) => r.title.key), ['alarm_title_overshoot']);
    });

    test('a muted stop gives no notice', () async {
      final h = _Harness();
      await h.start(
        settings: const JourneyAlarmSettings(mutedTargetIds: {kHub}),
      );
      await h.step(_westOfHub);
      await h.step(eastOf(kRouteB, -4000));
      await h.step(eastOf(kRouteB, -900));
      expect(h.notices.titles, isEmpty);
    });

    test('turning off stop approach notices keeps the arrival', () async {
      final h = _Harness();
      await h.start(
        settings: const JourneyAlarmSettings(hubApproach: false),
      );
      await h.step(_westOfHub);
      await h.step(eastOf(kRouteB, -4000));
      expect(h.notices.titles, isEmpty);
      await h.step(eastOf(kRouteB, -900));
      expect(h.notices.titles, ['alarm_title_arrive']);
    });

    test('arrivals and departures are recorded only while sharing', () async {
      final h = _Harness();
      await h.start();
      await h.step(_westOfHub);
      await h.step(eastOf(kRouteB, -900));
      expect(h.events.recorded, isEmpty, reason: 'sharing is off');

      await h.session.setSharing(on: true);
      await h.step(eastOf(kRouteB, 2600));
      expect(h.events.recorded, ['depart:$kHub']);
    });

    test('a shared arrival is recorded once for the stop', () async {
      final h = _Harness();
      await h.start();
      await h.session.setSharing(on: true);
      await h.step(_westOfHub);
      await h.step(eastOf(kRouteB, -900));
      await h.step(eastOf(kRouteB, -800));
      await h.step(eastOf(kRouteB, -850));
      expect(h.events.recorded, ['arrive:$kHub']);
    });

    test('stop ends the trip, cancels its alarms and clears the store',
        () async {
      final h = _Harness();
      final eta = h.clock.now.add(const Duration(hours: 2));
      await h.start(eta: eta);
      expect(h.alarmPort.scheduled, isNotEmpty);
      await h.session.stop();
      expect(h.session.isTracking, isFalse);
      expect(h.alarmPort.scheduled, isEmpty);
      expect(h.store.readTrip(), isNull);
    });

    test('a restart restores the trip without ringing an arrival again',
        () async {
      final backend = MemoryJourneyPrefsBackend();
      final first = _Harness(backend: backend);
      await first.start();
      await first.step(_westOfHub);
      await first.step(eastOf(kRouteB, -900));
      expect(first.notices.titles, ['alarm_title_arrive']);

      final second = _Harness(backend: backend);
      second.clock.now = first.clock.now;
      final restored = await second.session.restore(
        group: _group(),
        copy: _copy,
      );
      expect(restored, isTrue);
      expect(second.session.isTracking, isTrue);
      await second.step(eastOf(kRouteB, -850));
      expect(second.notices.titles, isEmpty,
          reason: 'the arrival was stored before the restart');
    });

    test('a trip idle for 36 hours ends instead of resuming', () async {
      final backend = MemoryJourneyPrefsBackend();
      final store = JourneyPrefsStore(backend);
      final now = DateTime.utc(2027, 1, 13, 20);
      await store.saveTrip(JourneyTrip(
        id: kTripId,
        tourId: 'tour-1',
        startedAt: now.subtract(const Duration(days: 3)),
        lastReadingAt: now.subtract(const Duration(hours: 37)),
      ));
      final h = _Harness(backend: backend);
      h.clock.now = now;
      final restored = await h.session.restore(group: _group(), copy: _copy);
      expect(restored, isFalse);
      expect(h.store.readTrip(), isNull);
    });

    test('a long stop asks once and samples less', () async {
      final h = _Harness();
      await h.start();
      final before = h.sampling.length;
      for (var i = 0; i < 32; i++) {
        await h.step(_westOfHub, speed: 0);
      }
      expect(h.session.isLongStop, isTrue);
      expect(h.session.longStopPrompt, isTrue);
      expect(h.sampling.length, greaterThan(before),
          reason: 'the stream restarts with the resting plan');
      h.session.dismissLongStopPrompt();
      expect(h.session.longStopPrompt, isFalse);
    });

    test('settings persist and apply to the running trip', () async {
      final h = _Harness();
      await h.start();
      const next = JourneyAlarmSettings(finalArrivalAlarm: false);
      await h.session.updateSettings(next);
      expect(h.store.readSettings().finalArrivalAlarm, isFalse);
      await h.step(eastOf(kRouteC, -400));
      expect(h.rings, isEmpty);
    });
  });
}
