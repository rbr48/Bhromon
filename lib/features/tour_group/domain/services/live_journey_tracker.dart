import 'dart:math' as math;

import 'journey_geometry.dart';

/// One GPS reading from this device.
class JourneyFix {
  const JourneyFix({
    required this.lat,
    required this.lng,
    required this.time,
    this.accuracyM,
    this.speedMps,
  });

  final double lat;
  final double lng;
  final DateTime time;

  /// The horizontal accuracy radius, in metres. Null when the platform gave none.
  final double? accuracyM;

  /// The speed the platform reports, in metres per second. Null when unknown.
  final double? speedMps;

  GeoPoint get point => GeoPoint(lat, lng);
}

/// What the tracker did with a reading.
enum FixVerdict {
  accepted,
  rejectedAccuracy,
  rejectedOutOfOrder,
  rejectedJump,
}

/// Where the group is, as far as the tracker knows.
enum JourneyStatus {
  /// There is no route to follow, because a stop has no coordinates.
  noRoute,

  /// No reading has been accepted yet.
  waiting,

  /// Following the route.
  onRoute,

  /// Several readings in a row are far from the route.
  offRoute,
}

/// Tuning for [JourneyTracker]. The defaults suit buses and cars on
/// Bangladesh roads.
class JourneyTrackerConfig {
  const JourneyTrackerConfig({
    this.maxAccuracyM = 75,
    this.maxSpeedMps = 42,
    this.gapReset = const Duration(minutes: 10),
    this.minSpeedInterval = const Duration(seconds: 3),
    this.offRouteM = 2000,
    this.offRouteFixes = 3,
    this.speedSmoothing = 0.3,
    this.stoppedBelowMps = 2,
    this.roadFactor = 1.25,
    this.stopReachedWithinM = 500,
  });

  /// Readings less accurate than this are ignored.
  final double maxAccuracyM;

  /// A move between two readings faster than this is a GPS jump. 42 m/s is
  /// 150 km/h.
  final double maxSpeedMps;

  /// After this long without a reading, the next reading starts again.
  final Duration gapReset;

  /// A speed is worked out from positions only over at least this interval.
  final Duration minSpeedInterval;

  /// A reading farther than this from the route is off the route.
  final double offRouteM;

  /// This many off-route readings in a row make the status off-route.
  final int offRouteFixes;

  /// The weight of the newest speed in the running average, from 0 to 1.
  final double speedSmoothing;

  /// Slower than this counts as stopped, so no arrival time is given.
  final double stoppedBelowMps;

  /// Road distance per metre of straight-line route, because roads bend.
  final double roadFactor;

  /// A stop counts as reached once the group is within this many metres of it.
  final double stopReachedWithinM;
}

/// The tracker's view of the journey after a reading.
class JourneySnapshot {
  const JourneySnapshot({
    required this.status,
    required this.alongM,
    required this.totalM,
    required this.crossTrackM,
    required this.pastEndM,
    required this.speedMps,
    required this.isStopped,
    required this.roadRemainingM,
    this.nextVertex,
    this.distanceToNextM,
    this.etaToEnd,
    this.etaToNext,
  });

  final JourneyStatus status;

  /// How far along the route the group is, in metres. While the group is on
  /// the route it never goes backwards.
  final double alongM;

  /// The route's length, in metres.
  final double totalM;

  /// The straight-line route left to go, in metres, never below zero.
  double get remainingM => math.max(0.0, totalM - alongM);

  /// The road distance left to go: [remainingM] scaled by the road factor.
  final double roadRemainingM;

  /// How far the latest reading is from the route, in metres.
  final double crossTrackM;

  /// How far past the final point the group is, in metres. Zero before the end.
  final double pastEndM;

  /// The smoothed speed, in metres per second.
  final double speedMps;

  /// True while the speed is below the stopped threshold.
  final bool isStopped;

  /// The index of the next point the group has not reached, or null once the
  /// last point is reached.
  final int? nextVertex;

  /// The straight-line distance along the route to [nextVertex], in metres.
  final double? distanceToNextM;

  /// The time to the end of the route at the smoothed speed. Null when the
  /// group is stopped, off the route, or has no route.
  final Duration? etaToEnd;

  /// The time to [nextVertex], on the same terms as [etaToEnd].
  final Duration? etaToNext;
}

/// The result of [JourneyTracker.update].
class JourneyUpdate {
  const JourneyUpdate({required this.verdict, required this.snapshot});

  final FixVerdict verdict;
  final JourneySnapshot snapshot;
}

/// Follows the group along a route from a stream of GPS readings.
///
/// The tracker is pure. It takes each reading's own time and never reads the
/// clock. It ignores inaccurate and impossible readings, smooths the speed,
/// keeps progress from going backwards while the group is on the route, and
/// reports when the group has strayed from it.
class JourneyTracker {
  JourneyTracker({
    required RoutePolyline? route,
    this.config = const JourneyTrackerConfig(),
  }) : _route = route != null && route.isUsable ? route : null;

  final RoutePolyline? _route;
  final JourneyTrackerConfig config;

  JourneyFix? _last;
  double _speed = 0;
  bool _hasSpeed = false;
  double? _alongM;
  double _crossM = 0;
  double _pastEndM = 0;
  int _offRouteRun = 0;
  JourneyStatus _status = JourneyStatus.waiting;

  /// The current view, without a new reading.
  JourneySnapshot get snapshot => _snapshot();

  /// Takes one reading. Returns what was done with it and the view after it.
  JourneyUpdate update(JourneyFix fix) {
    final route = _route;
    if (route == null) {
      return JourneyUpdate(
        verdict: FixVerdict.accepted,
        snapshot: _snapshot(),
      );
    }
    final accuracy = fix.accuracyM;
    if (accuracy == null || accuracy > config.maxAccuracyM) {
      return JourneyUpdate(
        verdict: FixVerdict.rejectedAccuracy,
        snapshot: _snapshot(),
      );
    }

    double? sampleMps = fix.speedMps;
    final last = _last;
    if (last != null) {
      final gap = fix.time.difference(last.time);
      if (gap <= Duration.zero) {
        return JourneyUpdate(
          verdict: FixVerdict.rejectedOutOfOrder,
          snapshot: _snapshot(),
        );
      }
      if (gap < config.gapReset) {
        final impliedMps =
            distanceM(last.point, fix.point) / (gap.inMilliseconds / 1000);
        if (impliedMps > config.maxSpeedMps) {
          return JourneyUpdate(
            verdict: FixVerdict.rejectedJump,
            snapshot: _snapshot(),
          );
        }
        if (sampleMps == null && gap >= config.minSpeedInterval) {
          sampleMps = impliedMps;
        }
      }
    }
    if (sampleMps != null && sampleMps.isFinite) {
      final clamped = math.min(math.max(sampleMps, 0.0), config.maxSpeedMps);
      _speed = _hasSpeed
          ? config.speedSmoothing * clamped +
              (1 - config.speedSmoothing) * _speed
          : clamped;
      _hasSpeed = true;
    }
    _last = fix;

    final projection = route.project(fix.point);
    final off = projection.crossTrackM > config.offRouteM;
    _offRouteRun = off ? _offRouteRun + 1 : 0;
    _status = _offRouteRun >= config.offRouteFixes
        ? JourneyStatus.offRoute
        : JourneyStatus.onRoute;
    _crossM = projection.crossTrackM;
    _pastEndM = projection.pastEndM;
    final current = _alongM;
    _alongM = current == null
        ? projection.alongM
        : (off ? current : math.max(current, projection.alongM));

    return JourneyUpdate(verdict: FixVerdict.accepted, snapshot: _snapshot());
  }

  JourneySnapshot _snapshot() {
    final route = _route;
    final total = route?.lengthM ?? 0.0;
    final along = _alongM ?? 0.0;
    final remaining = math.max(0.0, total - along);
    final speed = _hasSpeed ? _speed : 0.0;
    final isStopped = speed < config.stoppedBelowMps;
    final status = route == null ? JourneyStatus.noRoute : _status;

    int? nextVertex;
    double? distanceToNext;
    // Off the route, progress is the last known one, so no next stop is given.
    // Past the end there is no next stop either.
    if (route != null && status != JourneyStatus.offRoute && _pastEndM == 0) {
      for (var i = 0; i < route.points.length; i++) {
        final at = route.alongOf(i);
        if (at > along + config.stopReachedWithinM) {
          nextVertex = i;
          distanceToNext = at - along;
          break;
        }
      }
    }

    final moving = status == JourneyStatus.onRoute && !isStopped;
    final roadRemaining = remaining * config.roadFactor;
    final etaToEnd =
        moving ? Duration(seconds: (roadRemaining / speed).round()) : null;
    final etaToNext = moving && distanceToNext != null
        ? Duration(
            seconds: (distanceToNext * config.roadFactor / speed).round(),
          )
        : null;

    return JourneySnapshot(
      status: status,
      alongM: along,
      totalM: total,
      crossTrackM: _crossM,
      pastEndM: _pastEndM,
      speedMps: speed,
      isStopped: isStopped,
      roadRemainingM: roadRemaining,
      nextVertex: nextVertex,
      distanceToNextM: distanceToNext,
      etaToEnd: etaToEnd,
      etaToNext: etaToNext,
    );
  }
}
