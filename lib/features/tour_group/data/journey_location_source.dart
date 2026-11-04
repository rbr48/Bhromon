import 'package:geolocator/geolocator.dart';

import '../domain/services/journey_access_policy.dart';
import '../domain/services/live_journey_tracker.dart';

/// The platform settings for one sampling plan (roadmap LJ-2.1).
///
/// On Android, tracking runs in a foreground service, so it keeps going with the
/// screen off. The service shows an ongoing notification while the trip tracks.
/// On iOS, background updates are on with the location indicator shown, so the
/// user can see that tracking is active.
LocationSettings journeyLocationSettings({
  required SamplingPlan sampling,
  required bool isAndroid,
  required String notificationTitle,
  required String notificationText,
}) {
  final distanceFilter = sampling.distanceFilterM.round();
  if (isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      intervalDuration: sampling.interval,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  return AppleSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
    activityType: ActivityType.automotiveNavigation,
    pauseLocationUpdatesAutomatically: false,
    allowBackgroundLocationUpdates: true,
    showBackgroundLocationIndicator: true,
  );
}

/// Turns a platform position into a reading for the tracker. A speed the platform
/// does not know (a negative value) becomes null, so the tracker works it out
/// from the positions instead.
JourneyFix journeyFixFromPosition(Position position) {
  final speed = position.speed;
  return JourneyFix(
    lat: position.latitude,
    lng: position.longitude,
    time: position.timestamp,
    accuracyM: position.accuracy,
    speedMps: speed >= 0 ? speed : null,
  );
}

/// Opens the platform position stream for a set of settings. Tests replace it.
typedef PositionStreamFactory = Stream<Position> Function(
  LocationSettings settings,
);

/// Delivers readings for the tracker while a trip runs (roadmap LJ-2.1).
class JourneyLocationSource {
  JourneyLocationSource({PositionStreamFactory? streamFactory})
      : _streamFactory = streamFactory ?? _platformStream;

  final PositionStreamFactory _streamFactory;

  static Stream<Position> _platformStream(LocationSettings settings) {
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// Readings for one sampling plan, as they arrive.
  Stream<JourneyFix> fixes({
    required SamplingPlan sampling,
    required bool isAndroid,
    required String notificationTitle,
    required String notificationText,
  }) {
    final settings = journeyLocationSettings(
      sampling: sampling,
      isAndroid: isAndroid,
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
    return _streamFactory(settings).map(journeyFixFromPosition);
  }
}
