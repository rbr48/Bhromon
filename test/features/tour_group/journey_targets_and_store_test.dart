import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/data/journey_prefs_store.dart';
import 'package:bhromon/features/tour_group/domain/models/itinerary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/hub_alert_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_targets.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_trip.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_alarm_plan.dart';

import 'live_journey_test_support.dart';

TourGroup _group({
  List<TourStop> stops = const [],
  Map<String, LegPlan> legPlans = const {},
  bool returnHome = false,
}) =>
    TourGroup(
      id: 'tour-1',
      name: 'Trip',
      destination: 'Test',
      originCity: 'Nowhere',
      ownerEmail: 'o@x.com',
      inviteCode: 'ABCDEFGH',
      startDate: DateTime(2027, 1, 13),
      endDate: DateTime(2027, 1, 20),
      createdAt: DateTime(2026, 10, 1),
      stops: stops,
      legPlans: legPlans,
      returnHome: returnHome,
    );

TourStop _at(String id, GeoPoint p) => TourStop(
      id: id,
      name: id,
      arrive: DateTime(2027, 1, 14),
      leave: DateTime(2027, 1, 14),
      lat: p.lat,
      lng: p.lng,
    );

/// A stop with no coordinates: the group cannot be placed near it.
TourStop _unlocated(String id) => TourStop(
      id: id,
      name: 'Unknown place',
      arrive: DateTime(2027, 1, 14),
      leave: DateTime(2027, 1, 14),
    );

void main() {
  group('journey targets', () {
    test('the last outbound stop is the destination and the others are hubs',
        () {
      final t = journeyTargetsFor(_group(stops: [
        _at('a', kRouteA),
        _at('b', kRouteB),
        _at('c', kRouteC),
      ]));
      expect(t.destination?.id, 'c');
      expect(t.destination?.kind, AlertTargetKind.finalDestination);
      expect(t.destination?.arriveRadiusM, kDestinationArriveM);
      expect(t.stops.map((s) => s.id), ['a', 'b']);
      expect(t.stops.every((s) => s.kind == AlertTargetKind.stop), isTrue);
      expect(t.stops.first.arriveRadiusM, kStopArriveM);
      expect(t.route?.points, hasLength(3));
    });

    test('a return home is not the wake-up destination', () {
      final t = journeyTargetsFor(_group(
        stops: [_at('a', kRouteA), _at('c', kRouteC)],
        returnHome: true,
      ));
      expect(t.destination?.id, 'c');
      expect(t.route?.points, hasLength(2),
          reason: 'the trailing origin is not part of the outbound route');
    });

    test('a stop without coordinates is left out', () {
      final t = journeyTargetsFor(_group(stops: [
        _at('a', kRouteA),
        _unlocated('x'),
        _at('c', kRouteC),
      ]));
      expect(t.stops.map((s) => s.id), ['a']);
      expect(t.destination?.id, 'c');
    });

    test('with no located stop there is nothing to watch', () {
      final t = journeyTargetsFor(_group(stops: [_unlocated('x')]));
      expect(t.isEmpty, isTrue);
      expect(t.route, isNull);
    });

    test('the user thresholds replace the defaults', () {
      final t = journeyTargetsFor(
        _group(stops: [_at('a', kRouteA), _at('c', kRouteC)]),
        hubApproachM: const [2000],
        destinationApproachM: const [800],
      );
      expect(t.destination?.approachThresholdsM, [800]);
    });

    test('plannedArrivalAt reads the planned arrival of the last leg', () {
      final arrival = DateTime.utc(2027, 1, 15, 9);
      final group = _group(
        stops: [_at('a', kRouteA), _at('c', kRouteC)],
        legPlans: {'a>c': LegPlan(arriveAt: arrival)},
      );
      expect(plannedArrivalAt(group), arrival);
    });
  });

  group('hub alert engine restore', () {
    final target = AlertTarget(
      id: 'hub',
      name: 'Hub',
      point: kRouteB,
      kind: AlertTargetKind.stop,
      approachThresholdsM: const [5000, 1000],
    );

    test('a target restored as arrived does not announce its arrival again',
        () {
      final engine = HubAlertEngine(targets: [target]);
      engine.restoreState(arrivedNow: {'hub'}, everArrived: {'hub'});
      final alerts = engine.evaluate(at: eastOf(kRouteB, -300));
      expect(alerts, isEmpty);
      expect(engine.arrivedNowIds, {'hub'});
    });

    test('a restored destination that was reached blocks the overshoot', () {
      final destination = AlertTarget(
        id: 'end',
        name: 'End',
        point: kRouteC,
        kind: AlertTargetKind.finalDestination,
      );
      final engine = HubAlertEngine(targets: [destination]);
      engine.restoreState(arrivedNow: {}, everArrived: {'end'});
      final alerts = engine.evaluate(at: eastOf(kRouteC, 1500), pastEndM: 1500);
      expect(alerts, isEmpty);
    });
  });

  group('journey prefs store', () {
    test('settings survive a save and a load', () async {
      final store = JourneyPrefsStore(MemoryJourneyPrefsBackend());
      const settings = JourneyAlarmSettings(
        hubApproach: false,
        hubApproachThresholdsM: [3000, 500],
        finalArrivalAlarm: false,
        etaFallbackLead: Duration(minutes: 40),
        mutedTargetIds: {'hub'},
      );
      await store.saveSettings(settings);
      final loaded = store.readSettings();
      expect(loaded.hubApproach, isFalse);
      expect(loaded.hubApproachThresholdsM, [3000, 500]);
      expect(loaded.finalArrivalAlarm, isFalse);
      expect(loaded.etaFallbackLead, const Duration(minutes: 40));
      expect(loaded.mutedTargetIds, {'hub'});
    });

    test('a damaged settings record keeps the defaults', () async {
      final backend = MemoryJourneyPrefsBackend();
      await backend.write('alarm_settings', {
        'hubApproach': 'yes',
        'hubApproachThresholdsM': [-1, 'far'],
        'etaFallbackLeadMin': 9999,
      });
      final loaded = JourneyPrefsStore(backend).readSettings();
      const defaults = JourneyAlarmSettings();
      expect(loaded.hubApproach, defaults.hubApproach);
      expect(loaded.hubApproachThresholdsM, defaults.hubApproachThresholdsM);
      expect(loaded.etaFallbackLead, defaults.etaFallbackLead);
    });

    test('a trip survives a save and a load, and clearing it removes it',
        () async {
      final store = JourneyPrefsStore(MemoryJourneyPrefsBackend());
      final trip = JourneyTrip(
        id: 't',
        tourId: 'tour-1',
        startedAt: DateTime.utc(2027, 1, 13, 20),
        lastReadingAt: DateTime.utc(2027, 1, 13, 21),
        sharing: true,
      );
      await store.saveTrip(trip);
      final loaded = store.readTrip();
      expect(loaded?.id, 't');
      expect(loaded?.sharing, isTrue);
      expect(loaded?.lastReadingAt, DateTime.utc(2027, 1, 13, 21));
      await store.saveTrip(null);
      expect(store.readTrip(), isNull);
    });

    test('arrivals are kept for their trip only', () async {
      final store = JourneyPrefsStore(MemoryJourneyPrefsBackend());
      await store.saveArrivals(const JourneyArrivals(
        tripId: 'trip-a',
        arrivedNow: {'hub'},
        everArrived: {'hub', 'old'},
      ));
      final loaded = store.readArrivals();
      expect(loaded?.tripId, 'trip-a');
      expect(loaded?.arrivedNow, {'hub'});
      expect(loaded?.everArrived, {'hub', 'old'});
    });

    test('the disclosure is remembered once read', () async {
      final store = JourneyPrefsStore(MemoryJourneyPrefsBackend());
      expect(store.readDisclosureSeen(), isFalse);
      await store.saveDisclosureSeen();
      expect(store.readDisclosureSeen(), isTrue);
    });
  });
}
