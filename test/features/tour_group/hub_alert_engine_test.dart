import 'package:bhromon/features/tour_group/domain/services/hub_alert_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_journey_test_support.dart';

const _stop = AlertTarget(
  id: 'B',
  name: 'Stop B',
  point: kRouteB,
  kind: AlertTargetKind.stop,
  approachThresholdsM: [5000, 1000],
  arriveRadiusM: 1000,
);

const _finalStop = AlertTarget(
  id: 'C',
  name: 'Final',
  point: kRouteC,
  kind: AlertTargetKind.finalDestination,
  approachThresholdsM: [10000, 3000, 1000],
  arriveRadiusM: 500,
);

/// [p] moved [metres] west.
GeoPoint _west(GeoPoint p, double metres) => eastOf(p, -metres);

void main() {
  group('approach alerts', () {
    test('an approach fires once, at the tightest threshold crossed', () {
      final engine = HubAlertEngine(targets: const [_stop]);
      expect(engine.evaluate(at: _west(kRouteB, 20000)), isEmpty);

      final first = engine.evaluate(at: _west(kRouteB, 4800));
      expect(first, hasLength(1));
      expect(first.single.kind, HubAlertKind.approach);
      expect(first.single.targetId, 'B');
      expect(first.single.thresholdM, 5000);

      expect(engine.evaluate(at: _west(kRouteB, 4500)), isEmpty);
      expect(engine.evaluate(at: _west(kRouteB, 3000)), isEmpty);
    });

    test('a jump across two thresholds raises one alert, for the tightest', () {
      final engine = HubAlertEngine(targets: const [_finalStop]);
      final alerts = engine.evaluate(at: _west(kRouteC, 2500));
      expect(alerts, hasLength(1));
      expect(alerts.single.thresholdM, 3000);

      // The 10 km threshold was marked as fired by that jump.
      expect(engine.evaluate(at: _west(kRouteC, 9000)), isEmpty);
    });

    test('GPS jitter at a threshold does not fire it again', () {
      final engine = HubAlertEngine(targets: const [_stop]);
      expect(engine.evaluate(at: _west(kRouteB, 4900)), hasLength(1));
      for (final metres in [5050.0, 4950.0, 5100.0, 4980.0]) {
        expect(engine.evaluate(at: _west(kRouteB, metres)), isEmpty,
            reason: 'at $metres m');
      }
      // Well beyond threshold plus hysteresis: the threshold re-arms.
      expect(engine.evaluate(at: _west(kRouteB, 6100)), isEmpty);
      expect(engine.evaluate(at: _west(kRouteB, 4900)), hasLength(1));
    });
  });

  group('arrival', () {
    test('arrival fires once, and only again after the group has left', () {
      final engine = HubAlertEngine(targets: const [_stop]);
      final first = engine.evaluate(at: _west(kRouteB, 800));
      expect(first.map((a) => a.kind), [HubAlertKind.arrive]);

      expect(engine.evaluate(at: _west(kRouteB, 700)), isEmpty);
      expect(engine.evaluate(at: _west(kRouteB, 1500)), isEmpty);
      expect(engine.evaluate(at: _west(kRouteB, 2100)), isEmpty);

      final again = engine.evaluate(at: _west(kRouteB, 900));
      expect(again.map((a) => a.kind), [HubAlertKind.arrive]);
    });
  });

  group('overshoot', () {
    test('fires once when the group is far past the final destination', () {
      final engine = HubAlertEngine(targets: const [_finalStop]);
      expect(engine.evaluate(at: _west(kRouteC, 20000)), isEmpty);

      final past = eastOf(kRouteC, 1500);
      final first = engine.evaluate(at: past, pastEndM: 1500);
      expect(
        first.where((a) => a.kind == HubAlertKind.overshoot),
        hasLength(1),
      );

      final further =
          engine.evaluate(at: eastOf(kRouteC, 2000), pastEndM: 2000);
      expect(
        further.where((a) => a.kind == HubAlertKind.overshoot),
        isEmpty,
      );
    });

    test('re-arms once the group is back on the route', () {
      final engine = HubAlertEngine(targets: const [_finalStop]);
      engine.evaluate(at: eastOf(kRouteC, 1500), pastEndM: 1500);

      engine.evaluate(at: _west(kRouteC, 5000));

      final again = engine.evaluate(at: eastOf(kRouteC, 1500), pastEndM: 1500);
      expect(
        again.where((a) => a.kind == HubAlertKind.overshoot),
        hasLength(1),
      );
    });

    test('does not fire after the group has arrived at the final destination',
        () {
      final engine = HubAlertEngine(targets: const [_finalStop]);
      final arrived = engine.evaluate(at: eastOf(kRouteC, 200));
      expect(arrived.map((a) => a.kind), contains(HubAlertKind.arrive));

      final driving =
          engine.evaluate(at: eastOf(kRouteC, 1600), pastEndM: 1600);
      expect(
        driving.where((a) => a.kind == HubAlertKind.overshoot),
        isEmpty,
      );
    });

    test('a stop never raises an overshoot', () {
      final engine = HubAlertEngine(targets: const [_stop]);
      final alerts = engine.evaluate(at: eastOf(kRouteB, 5000), pastEndM: 5000);
      expect(
        alerts.where((a) => a.kind == HubAlertKind.overshoot),
        isEmpty,
      );
    });
  });
}
