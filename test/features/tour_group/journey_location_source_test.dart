import 'dart:async';

import 'package:bhromon/features/tour_group/data/journey_location_source.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_access_policy.dart';
import 'package:bhromon/features/tour_group/domain/services/live_journey_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _position({double speed = 12, DateTime? time}) {
  return Position(
    longitude: 90.4125,
    latitude: 23.8103,
    timestamp: time ?? DateTime.utc(2027, 1, 13, 20),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

void main() {
  group('journeyLocationSettings', () {
    test('Android tracks in a foreground service at the sampling interval', () {
      final settings = journeyLocationSettings(
        sampling: SamplingPlan.moving,
        isAndroid: true,
        notificationTitle: 'Trip',
        notificationText: 'Tracking',
      );
      expect(settings, isA<AndroidSettings>());
      final android = settings as AndroidSettings;
      expect(android.intervalDuration, const Duration(seconds: 10));
      expect(android.distanceFilter, 25);
      final config = android.foregroundNotificationConfig;
      expect(config, isNotNull);
      expect(config!.setOngoing, isTrue);
      expect(config.notificationTitle, 'Trip');
    });

    test('iOS keeps tracking in the background, with the indicator shown', () {
      final settings = journeyLocationSettings(
        sampling: SamplingPlan.stationary,
        isAndroid: false,
        notificationTitle: 'Trip',
        notificationText: 'Tracking',
      );
      expect(settings, isA<AppleSettings>());
      final apple = settings as AppleSettings;
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
      expect(apple.activityType, ActivityType.automotiveNavigation);
      expect(apple.distanceFilter, 25);
    });

    test('the resting plan widens the distance filter and samples less', () {
      final android = journeyLocationSettings(
        sampling: SamplingPlan.resting,
        isAndroid: true,
        notificationTitle: 'Trip',
        notificationText: 'Tracking',
      ) as AndroidSettings;
      expect(android.distanceFilter, 50);
      expect(android.intervalDuration, const Duration(minutes: 5));
    });
  });

  group('journeyFixFromPosition', () {
    test('keeps the place, its time, its accuracy and its speed', () {
      final fix = journeyFixFromPosition(_position(speed: 12));
      expect(fix.lat, 23.8103);
      expect(fix.lng, 90.4125);
      expect(fix.time, DateTime.utc(2027, 1, 13, 20));
      expect(fix.accuracyM, 8);
      expect(fix.speedMps, 12);
    });

    test('an unknown speed becomes null, so the tracker works it out', () {
      expect(journeyFixFromPosition(_position(speed: -1)).speedMps, isNull);
    });
  });

  group('JourneyLocationSource', () {
    test('passes the settings on and maps each position to a reading',
        () async {
      final controller = StreamController<Position>();
      LocationSettings? seen;
      final source = JourneyLocationSource(streamFactory: (settings) {
        seen = settings;
        return controller.stream;
      });

      final fixes = <JourneyFix>[];
      final subscription = source
          .fixes(
            sampling: SamplingPlan.moving,
            isAndroid: true,
            notificationTitle: 'Trip',
            notificationText: 'Tracking',
          )
          .listen(fixes.add);

      controller
        ..add(_position(speed: 9))
        ..add(_position(speed: 10, time: DateTime.utc(2027, 1, 13, 20, 0, 10)));
      await Future<void>.delayed(Duration.zero);

      expect(seen, isA<AndroidSettings>());
      expect(fixes.map((f) => f.speedMps), [9, 10]);
      await subscription.cancel();
      await controller.close();
    });
  });
}
