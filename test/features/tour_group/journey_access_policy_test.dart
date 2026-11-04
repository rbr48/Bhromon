import 'package:bhromon/features/tour_group/domain/services/journey_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';

LocationStep _step(
  LocationAccess access, {
  bool serviceEnabled = true,
  bool needsBackground = true,
  bool disclosureAccepted = false,
}) {
  return nextLocationStep(
    access: access,
    serviceEnabled: serviceEnabled,
    needsBackground: needsBackground,
    disclosureAccepted: disclosureAccepted,
  );
}

void main() {
  group('nextLocationStep', () {
    test('a phone with its location service off is told to turn it on', () {
      expect(
        _step(LocationAccess.always, serviceEnabled: false),
        LocationStep.turnOnService,
      );
    });

    test('a refusal for good opens the settings', () {
      expect(_step(LocationAccess.deniedForever), LocationStep.openSettings);
    });

    test('an undecided or refused phone is asked for while-in-use first', () {
      expect(_step(LocationAccess.notDetermined), LocationStep.askWhileInUse);
      expect(_step(LocationAccess.denied), LocationStep.askWhileInUse);
    });

    test('a background trip shows the disclosure before asking for always', () {
      expect(_step(LocationAccess.whileInUse), LocationStep.showDisclosure);
      expect(
        _step(LocationAccess.whileInUse, disclosureAccepted: true),
        LocationStep.askAlways,
      );
    });

    test('always access is ready', () {
      expect(_step(LocationAccess.always), LocationStep.ready);
    });

    test('a trip without background tracking is ready with while-in-use', () {
      expect(
        _step(LocationAccess.whileInUse, needsBackground: false),
        LocationStep.ready,
      );
    });
  });

  group('SamplingPlan', () {
    test('moving samples every 10 seconds, stopped every minute', () {
      expect(
        SamplingPlan.forState(moving: true, longStop: false).interval,
        const Duration(seconds: 10),
      );
      expect(
        SamplingPlan.forState(moving: false, longStop: false).interval,
        const Duration(seconds: 60),
      );
    });

    test('a long stop samples every five minutes', () {
      expect(
        SamplingPlan.forState(moving: false, longStop: true).interval,
        const Duration(minutes: 5),
      );
    });

    test('a moving phone ignores a stale long-stop flag', () {
      expect(
        SamplingPlan.forState(moving: true, longStop: true).interval,
        const Duration(seconds: 10),
      );
    });

    test('the distance filter is 25 metres unless the phone is resting', () {
      expect(SamplingPlan.moving.distanceFilterM, 25);
      expect(SamplingPlan.stationary.distanceFilterM, 25);
      expect(SamplingPlan.resting.distanceFilterM, 50);
    });
  });

  group('StationaryDetector', () {
    final t0 = DateTime.utc(2027, 1, 13, 20);

    test('starts as moving, with no long stop', () {
      final detector = StationaryDetector();
      expect(detector.isMoving, isTrue);
      expect(detector.isLongStop(t0.add(const Duration(hours: 2))), isFalse);
    });

    test('a stop shorter than 30 minutes is not a long stop', () {
      final detector = StationaryDetector()..observe(speedMps: 0, at: t0);
      expect(detector.isMoving, isFalse);
      expect(
        detector.isLongStop(t0.add(const Duration(minutes: 29))),
        isFalse,
      );
    });

    test('a stop of 30 minutes is a long stop', () {
      final detector = StationaryDetector()..observe(speedMps: 0, at: t0);
      expect(
        detector.isLongStop(t0.add(const Duration(minutes: 30))),
        isTrue,
      );
    });

    test('the first moment of a stop is kept, not the latest reading', () {
      final detector = StationaryDetector()
        ..observe(speedMps: 0, at: t0)
        ..observe(speedMps: 0, at: t0.add(const Duration(minutes: 25)));
      expect(
        detector.isLongStop(t0.add(const Duration(minutes: 30))),
        isTrue,
      );
    });

    test('moving again ends the stop', () {
      final detector = StationaryDetector()
        ..observe(speedMps: 0, at: t0)
        ..observe(speedMps: 12, at: t0.add(const Duration(minutes: 20)));
      expect(detector.isMoving, isTrue);
      expect(
        detector.isLongStop(t0.add(const Duration(minutes: 60))),
        isFalse,
      );
    });
  });
}
