import 'package:bhromon/features/tour_group/domain/services/hub_alert_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_alarm_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_journey_test_support.dart';

final _now = DateTime(2027, 1, 13, 20);

const _stops = [
  AlertTarget(
    id: 'S1',
    name: 'Stop one',
    point: kRouteB,
    kind: AlertTargetKind.stop,
  ),
  AlertTarget(
    id: 'S2',
    name: 'Stop two',
    point: GeoPoint(23.2, 90.8),
    kind: AlertTargetKind.stop,
  ),
];

const _destination = AlertTarget(
  id: 'F',
  name: 'Final',
  point: kRouteC,
  kind: AlertTargetKind.finalDestination,
);

List<TripAlarm> _plan({
  JourneyAlarmSettings settings = const JourneyAlarmSettings(),
  DateTime? finalEta,
}) {
  return buildTripAlarmPlan(
    tripId: 'trip-1',
    stops: _stops,
    finalDestination: _destination,
    settings: settings,
    now: _now,
    finalEta: finalEta,
  );
}

void main() {
  group('the default plan', () {
    test('has six stop alarms and five destination alarms, and no ETA alarm',
        () {
      expect(_plan(), hasLength(11));
    });

    test('arms an ETA alarm 25 minutes before the expected arrival', () {
      final eta = _now.add(const Duration(hours: 2));
      final plan = _plan(finalEta: eta);
      expect(plan, hasLength(12));
      final fallback =
          plan.singleWhere((a) => a.kind == TripAlarmKind.etaFallback);
      expect(fallback.fireAt, eta.subtract(const Duration(minutes: 25)));
      expect(fallback.rings, isTrue);
    });

    test('does not arm an ETA alarm that would already be in the past', () {
      final plan = _plan(finalEta: _now.add(const Duration(minutes: 10)));
      expect(plan.where((a) => a.kind == TripAlarmKind.etaFallback), isEmpty);
    });

    test('only the destination wake-up and overshoot ring like an alarm', () {
      final ringing = _plan().where((a) => a.rings).toList();
      expect(
        ringing.map((a) => a.kind).toSet(),
        {TripAlarmKind.finalArrive, TripAlarmKind.overshoot},
      );
      final wake =
          ringing.singleWhere((a) => a.kind == TripAlarmKind.finalArrive);
      expect(wake.maxRings, 10);
      expect(wake.ringSeconds, 60);
    });

    test('approach notices carry their distance and do not ring', () {
      final approaches = _plan()
          .where((a) =>
              a.kind == TripAlarmKind.hubApproach ||
              a.kind == TripAlarmKind.finalApproach)
          .toList();
      expect(approaches, isNotEmpty);
      expect(approaches.every((a) => !a.rings), isTrue);
      expect(approaches.every((a) => a.thresholdM != null), isTrue);
    });
  });

  group('identity', () {
    test('ids are unique within a trip and the same on every call', () {
      final first = _plan(finalEta: _now.add(const Duration(hours: 2)));
      final second = _plan(finalEta: _now.add(const Duration(hours: 2)));
      final ids = first.map((a) => a.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(second.map((a) => a.id).toList(), ids);
    });

    test('a stable id is in the reserved range and differs for different keys',
        () {
      final ids = [for (var i = 0; i < 500; i++) stableAlarmId('trip|$i')];
      expect(ids.toSet(), hasLength(500));
      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(0x40000000));
        expect(id, lessThan(0x80000000));
      }
    });
  });

  group('settings', () {
    test('a muted stop raises no alarms', () {
      final plan = _plan(
        settings: const JourneyAlarmSettings(mutedTargetIds: {'S1'}),
      );
      expect(plan.where((a) => a.targetId == 'S1'), isEmpty);
      expect(plan, hasLength(8));
    });

    test('a muted destination raises no alarms', () {
      final plan = _plan(
        settings: const JourneyAlarmSettings(mutedTargetIds: {'F'}),
      );
      expect(plan.where((a) => a.targetId == 'F'), isEmpty);
      expect(plan, hasLength(6));
    });

    test('switching everything off gives an empty plan, even with an ETA', () {
      final plan = _plan(
        settings: const JourneyAlarmSettings(
          hubApproach: false,
          hubArrive: false,
          finalApproach: false,
          finalArrivalAlarm: false,
          overshootAlarm: false,
          etaFallback: false,
        ),
        finalEta: _now.add(const Duration(hours: 2)),
      );
      expect(plan, isEmpty);
    });

    test('copyWith changes only the fields it is given', () {
      const base = JourneyAlarmSettings();
      final changed = base.copyWith(overshootAlarm: false);
      expect(changed.overshootAlarm, isFalse);
      expect(changed.finalArrivalAlarm, isTrue);
      expect(changed.etaFallbackLead, base.etaFallbackLead);
    });
  });
}
