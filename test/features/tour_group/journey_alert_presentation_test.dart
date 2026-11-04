import 'package:bhromon/features/tour_group/domain/services/hub_alert_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_alert_presentation.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_alarm_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const _approachStop = HubAlert(
  kind: HubAlertKind.approach,
  targetId: 'S1',
  distanceM: 4800,
  thresholdM: 5000,
);

const _arriveFinal = HubAlert(
  kind: HubAlertKind.arrive,
  targetId: 'F',
  distanceM: 300,
);

const _overshootFinal = HubAlert(
  kind: HubAlertKind.overshoot,
  targetId: 'F',
  distanceM: 1500,
);

void main() {
  group('alarmKindFor', () {
    test('stop and destination alerts map to their own kinds', () {
      expect(
        alarmKindFor(_approachStop, AlertTargetKind.stop),
        TripAlarmKind.hubApproach,
      );
      expect(
        alarmKindFor(_arriveFinal, AlertTargetKind.finalDestination),
        TripAlarmKind.finalArrive,
      );
      expect(
        alarmKindFor(_overshootFinal, AlertTargetKind.finalDestination),
        TripAlarmKind.overshoot,
      );
      expect(
        alarmKindFor(
          const HubAlert(
            kind: HubAlertKind.arrive,
            targetId: 'S1',
            distanceM: 800,
          ),
          AlertTargetKind.stop,
        ),
        TripAlarmKind.hubArrive,
      );
      expect(
        alarmKindFor(
          const HubAlert(
            kind: HubAlertKind.approach,
            targetId: 'F',
            distanceM: 2500,
            thresholdM: 3000,
          ),
          AlertTargetKind.finalDestination,
        ),
        TripAlarmKind.finalApproach,
      );
    });
  });

  group('presentAlert', () {
    test('an approach to a stop notifies, with the distance to go', () {
      final p = presentAlert(
        tripId: 'trip-1',
        alert: _approachStop,
        targetKind: AlertTargetKind.stop,
        placeName: 'Bandarban',
        kmText: '5',
      );
      expect(p.rings, isFalse);
      expect(p.channel, JourneyChannel.stop);
      expect(
        p.title,
        const JourneyText('alarm_title_approach', {'place': 'Bandarban'}),
      );
      expect(p.body, const JourneyText('alarm_body_distance', {'km': '5'}));
    });

    test('the final arrival rings on the alarm channel', () {
      final p = presentAlert(
        tripId: 'trip-1',
        alert: _arriveFinal,
        targetKind: AlertTargetKind.finalDestination,
        placeName: 'Sajek',
      );
      expect(p.rings, isTrue);
      expect(p.channel, JourneyChannel.alarm);
      expect(p.title, const JourneyText('alarm_title_final'));
      expect(p.body, const JourneyText('alarm_body_place', {'place': 'Sajek'}));
    });

    test('an overshoot rings with its own title', () {
      final p = presentAlert(
        tripId: 'trip-1',
        alert: _overshootFinal,
        targetKind: AlertTargetKind.finalDestination,
        placeName: 'Sajek',
      );
      expect(p.rings, isTrue);
      expect(p.channel, JourneyChannel.alarm);
      expect(p.title, const JourneyText('alarm_title_overshoot'));
    });

    test('a stop arrival notifies only', () {
      final p = presentAlert(
        tripId: 'trip-1',
        alert: const HubAlert(
          kind: HubAlertKind.arrive,
          targetId: 'S1',
          distanceM: 800,
        ),
        targetKind: AlertTargetKind.stop,
        placeName: 'Bandarban',
      );
      expect(p.rings, isFalse);
      expect(p.channel, JourneyChannel.stop);
      expect(p.body, const JourneyText('alarm_body_arrived'));
    });

    test('an alert finds the alarm the plan armed for it', () {
      final plan = buildTripAlarmPlan(
        tripId: 'trip-1',
        stops: const [
          AlertTarget(
            id: 'S1',
            name: 'Bandarban',
            point: GeoPoint(22.2, 92.2),
            kind: AlertTargetKind.stop,
          ),
        ],
        finalDestination: null,
        settings: const JourneyAlarmSettings(
          hubApproachThresholdsM: [5000],
          hubArrive: false,
        ),
        now: DateTime.utc(2027, 1, 13, 20),
      );
      final armed = plan.single;
      final shown = presentAlert(
        tripId: 'trip-1',
        alert: _approachStop,
        targetKind: AlertTargetKind.stop,
        placeName: 'Bandarban',
      );
      expect(shown.id, armed.id);
    });

    test('ids differ between alarms of one trip and between trips', () {
      final ids = {
        presentAlert(
          tripId: 'trip-1',
          alert: _arriveFinal,
          targetKind: AlertTargetKind.finalDestination,
          placeName: 'x',
        ).id,
        presentAlert(
          tripId: 'trip-1',
          alert: _overshootFinal,
          targetKind: AlertTargetKind.finalDestination,
          placeName: 'x',
        ).id,
        presentAlert(
          tripId: 'trip-2',
          alert: _arriveFinal,
          targetKind: AlertTargetKind.finalDestination,
          placeName: 'x',
        ).id,
      };
      expect(ids, hasLength(3));
    });
  });
}
