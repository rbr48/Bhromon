import 'package:bhromon/features/tour_group/domain/services/hub_alert_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/live_journey_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_journey_test_support.dart';

const _stopB = AlertTarget(
  id: 'B',
  name: 'Stop B',
  point: kRouteB,
  kind: AlertTargetKind.stop,
  approachThresholdsM: [5000, 1000],
  arriveRadiusM: 1000,
);

const _finalC = AlertTarget(
  id: 'C',
  name: 'Final',
  point: kRouteC,
  kind: AlertTargetKind.finalDestination,
  approachThresholdsM: [10000, 3000, 1000],
  arriveRadiusM: 500,
);

/// Drives a bus from A along the route at 60 km/h, with a reading every 10 s
/// and up to 15 m of noise. [lost] says whether the device gets no reading at a
/// given distance along the route. Returns every alert the engine raised.
List<HubAlert> _drive({
  bool Function(double alongM)? lost,
  required double extraM,
}) {
  final route = RoutePolyline(const [kRouteA, kRouteB, kRouteC]);
  final tracker = JourneyTracker(route: route);
  final engine = HubAlertEngine(targets: const [_stopB, _finalC]);

  var seed = 12345;
  double noise() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return (seed / 0x7fffffff) * 2 - 1;
  }

  const noiseM = 15.0;
  const metresPerReading = 60 / 3.6 * 10; // 60 km/h for 10 s
  final endAlongM = route.lengthM + extraM;
  final alerts = <HubAlert>[];
  var along = 0.0;
  var time = DateTime(2027, 1, 13, 20);
  while (along <= endAlongM) {
    if (lost == null || !lost(along)) {
      final base = eastOf(kRouteA, along);
      final point = northOf(eastOf(base, noise() * noiseM), noise() * noiseM);
      final update = tracker.update(JourneyFix(
        lat: point.lat,
        lng: point.lng,
        time: time,
        accuracyM: 12,
      ));
      if (update.verdict == FixVerdict.accepted) {
        alerts.addAll(engine.evaluate(
          at: point,
          pastEndM: update.snapshot.pastEndM,
        ));
      }
    }
    along += metresPerReading;
    time = time.add(const Duration(seconds: 10));
  }
  return alerts;
}

/// One line per alert, so a sequence can be compared as a list of strings.
List<String> _lines(List<HubAlert> alerts) => [
      for (final a in alerts)
        [a.kind.name, a.targetId, if (a.thresholdM != null) a.thresholdM!]
            .join(' '),
    ];

void main() {
  test('a full trip raises each alert once, in order, and no overshoot', () {
    final alerts = _drive(extraM: 300);
    expect(_lines(alerts), [
      'approach B 5000.0',
      'arrive B',
      'approach C 10000.0',
      'approach C 3000.0',
      'approach C 1000.0',
      'arrive C',
    ]);
  });

  test('a lost signal near the destination still raises the overshoot once',
      () {
    final cAlong = RoutePolyline(const [kRouteA, kRouteB, kRouteC]).lengthM;
    // No readings from 1.2 km before the destination until 2 km past it.
    final alerts = _drive(
      lost: (along) => along > cAlong - 1200 && along < cAlong + 1999,
      extraM: 2600,
    );
    expect(_lines(alerts), [
      'approach B 5000.0',
      'arrive B',
      'approach C 10000.0',
      'approach C 3000.0',
      'overshoot C',
    ]);
    expect(
      alerts.where((a) => a.kind == HubAlertKind.overshoot).single.distanceM,
      // The first reading past 1 km falls somewhere in the 166 m reading gap.
      inInclusiveRange(1000, 2300),
    );
  });
}
