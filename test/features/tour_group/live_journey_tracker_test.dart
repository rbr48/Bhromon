import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/live_journey_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_journey_test_support.dart';

final _route = RoutePolyline(const [kRouteA, kRouteB, kRouteC]);
final _t0 = DateTime(2027, 1, 13, 20);

JourneyFix _fix(GeoPoint p, DateTime t,
    {double? accuracy = 10, double? speed}) {
  return JourneyFix(
    lat: p.lat,
    lng: p.lng,
    time: t,
    accuracyM: accuracy,
    speedMps: speed,
  );
}

void main() {
  group('which readings count', () {
    test('a reading with poor or unknown accuracy is ignored', () {
      final tracker = JourneyTracker(route: _route);
      final poor =
          tracker.update(_fix(eastOf(kRouteA, 5000), _t0, accuracy: 120));
      expect(poor.verdict, FixVerdict.rejectedAccuracy);
      expect(poor.snapshot.status, JourneyStatus.waiting);

      final unknown =
          tracker.update(_fix(eastOf(kRouteA, 5000), _t0, accuracy: null));
      expect(unknown.verdict, FixVerdict.rejectedAccuracy);
    });

    test('a reading older than the last accepted one is ignored', () {
      final tracker = JourneyTracker(route: _route)
        ..update(_fix(eastOf(kRouteA, 5000), _t0));
      final late = tracker.update(
        _fix(eastOf(kRouteA, 4000), _t0.subtract(const Duration(seconds: 5))),
      );
      expect(late.verdict, FixVerdict.rejectedOutOfOrder);
    });

    test('a jump faster than 150 km/h is ignored', () {
      final tracker = JourneyTracker(route: _route)
        ..update(_fix(eastOf(kRouteA, 5000), _t0));
      final jump = tracker.update(
        _fix(eastOf(kRouteA, 60000), _t0.add(const Duration(seconds: 1))),
      );
      expect(jump.verdict, FixVerdict.rejectedJump);
      expect(jump.snapshot.alongM, closeTo(5000, 20));
    });

    test('after a long gap the next reading starts again', () {
      final tracker = JourneyTracker(route: _route)
        ..update(_fix(eastOf(kRouteA, 5000), _t0));
      final later = tracker.update(
        _fix(eastOf(kRouteA, 40000), _t0.add(const Duration(hours: 1))),
      );
      expect(later.verdict, FixVerdict.accepted);
      expect(later.snapshot.alongM, closeTo(40000, 30));
    });
  });

  group('progress', () {
    test('a reading on the route gives progress along it', () {
      final tracker = JourneyTracker(route: _route);
      final update = tracker.update(_fix(eastOf(kRouteA, 25000), _t0));
      expect(update.verdict, FixVerdict.accepted);
      expect(update.snapshot.status, JourneyStatus.onRoute);
      expect(update.snapshot.alongM, closeTo(25000, 30));
      expect(update.snapshot.remainingM, closeTo(_route.lengthM - 25000, 30));
      expect(update.snapshot.crossTrackM, lessThan(20));
    });

    test('progress never goes backwards while on the route', () {
      final tracker = JourneyTracker(route: _route)
        ..update(_fix(eastOf(kRouteA, 30000), _t0));
      final back = tracker.update(
        _fix(eastOf(kRouteA, 29960), _t0.add(const Duration(seconds: 10))),
      );
      expect(back.snapshot.alongM, closeTo(30000, 30));
    });

    test('the next stop is the first point the group has not reached', () {
      final tracker = JourneyTracker(route: _route);
      final start = tracker.update(_fix(eastOf(kRouteA, 0), _t0));
      expect(start.snapshot.nextVertex, 1);

      final nearB = tracker.update(
        _fix(eastOf(kRouteA, 50800), _t0.add(const Duration(hours: 1))),
      );
      expect(nearB.snapshot.nextVertex, 2);
      expect(nearB.snapshot.distanceToNextM, isNotNull);
    });
  });

  group('off the route', () {
    test('the status changes only after three readings in a row', () {
      final tracker = JourneyTracker(route: _route);
      final away = northOf(eastOf(kRouteA, 20000), 3000);

      final first = tracker.update(_fix(away, _t0));
      expect(first.snapshot.status, JourneyStatus.onRoute);

      final second = tracker.update(
        _fix(northOf(eastOf(kRouteA, 20100), 3000),
            _t0.add(const Duration(seconds: 10))),
      );
      expect(second.snapshot.status, JourneyStatus.onRoute);

      final third = tracker.update(
        _fix(northOf(eastOf(kRouteA, 20200), 3000),
            _t0.add(const Duration(seconds: 20))),
      );
      expect(third.snapshot.status, JourneyStatus.offRoute);
      expect(third.snapshot.etaToEnd, isNull);
    });

    test('the status returns to on-route once back near the route', () {
      final tracker = JourneyTracker(route: _route);
      for (var i = 0; i < 3; i++) {
        tracker.update(_fix(
          northOf(eastOf(kRouteA, 20000 + i * 100.0), 3000),
          _t0.add(Duration(seconds: 10 * i)),
        ));
      }
      // A phone that lost signal for 11 minutes can reconnect anywhere, so the
      // long gap starts the track again instead of counting as a jump.
      final back = tracker.update(
        _fix(eastOf(kRouteA, 20400), _t0.add(const Duration(minutes: 11))),
      );
      expect(back.snapshot.status, JourneyStatus.onRoute);
    });
  });

  group('speed and arrival time', () {
    test('speed comes from positions and an arrival time is given while moving',
        () {
      final tracker = JourneyTracker(route: _route);
      JourneySnapshot? snapshot;
      var metres = 5000.0;
      var time = _t0;
      for (var i = 0; i < 12; i++) {
        snapshot = tracker.update(_fix(eastOf(kRouteA, metres), time)).snapshot;
        metres += 1000;
        time = time.add(const Duration(minutes: 1));
      }
      expect(snapshot!.speedMps, closeTo(16.67, 0.5));
      expect(snapshot.isStopped, isFalse);
      expect(snapshot.etaToEnd!.inMinutes, inInclusiveRange(100, 115));
    });

    test('a stopped group has no arrival time', () {
      final tracker = JourneyTracker(route: _route);
      for (var i = 0; i < 5; i++) {
        tracker.update(_fix(
          eastOf(kRouteA, 10000),
          _t0.add(Duration(minutes: i)),
          speed: 0,
        ));
      }
      final snapshot = tracker.snapshot;
      expect(snapshot.isStopped, isTrue);
      expect(snapshot.etaToEnd, isNull);
    });
  });

  group('past the final point', () {
    test(
        'the distance past the end is reported, and the route is left after three readings',
        () {
      final tracker = JourneyTracker(route: _route)
        ..update(_fix(eastOf(kRouteA, 95000), _t0));

      final first = tracker.update(
        _fix(eastOf(kRouteC, 3000), _t0.add(const Duration(minutes: 10))),
      );
      expect(first.snapshot.pastEndM, closeTo(3000, 30));

      tracker.update(
          _fix(eastOf(kRouteC, 3100), _t0.add(const Duration(minutes: 11))));
      final third = tracker.update(
        _fix(eastOf(kRouteC, 3200), _t0.add(const Duration(minutes: 12))),
      );
      expect(third.snapshot.pastEndM, closeTo(3200, 30));
      expect(third.snapshot.status, JourneyStatus.offRoute);
      expect(third.snapshot.nextVertex, isNull);
    });
  });

  group('without a route', () {
    test('a tracker with no route reports no route and gives no progress', () {
      final tracker = JourneyTracker(route: null);
      final update = tracker.update(_fix(eastOf(kRouteA, 5000), _t0));
      expect(update.snapshot.status, JourneyStatus.noRoute);
      expect(update.snapshot.alongM, 0);
    });

    test('a route with one point cannot be followed', () {
      final tracker = JourneyTracker(
        route: RoutePolyline(const [kRouteA]),
      );
      expect(tracker.snapshot.status, JourneyStatus.noRoute);
    });
  });
}
