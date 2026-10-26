import 'dart:math' as math;

import '../models/itinerary_models.dart';
import '../models/tour_group.dart';
import 'destination_catalog.dart';

/// Great-circle distance in km.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a.toDouble()));
}

/// The origin city or a stop on the route.
class RoutePoint {
  const RoutePoint({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
    this.stop,
  });

  final String id;
  final String name;
  final double? lat;
  final double? lng;

  /// The itinerary stop, or null for the origin city.
  final TourStop? stop;

  bool get isOrigin => stop == null;
  bool get hasLocation => lat != null && lng != null;

  /// "lat,lng" when known, otherwise the name, for map links.
  String get mapsQuery => hasLocation ? '$lat,$lng' : name;
}

enum LegStatus { planned, underway, done }

class RouteLeg {
  const RouteLeg({
    required this.key,
    required this.index,
    required this.from,
    required this.to,
    required this.plan,
  });

  final String key;
  final int index;
  final RoutePoint from;
  final RoutePoint to;
  final LegPlan plan;

  /// The known distance, or one estimated from the two places' coordinates.
  /// Null when neither is available.
  int? get km {
    if (plan.distanceKm != null) return plan.distanceKm;
    if (!from.hasLocation || !to.hasLocation) return null;
    final straight = haversineKm(from.lat!, from.lng!, to.lat!, to.lng!);
    return (straight * plan.mode.detourFactor).round();
  }

  bool get isEstimated => plan.distanceKm == null;

  /// Moving time at the mode's typical speed, plus boarding overheads.
  Duration? get estimatedDuration {
    final distance = km;
    if (distance == null) return null;
    final minutes =
        distance / plan.mode.averageKmh * 60 + plan.mode.overheadMinutes;
    return Duration(minutes: minutes.round());
  }

  /// The planned travel time when both ends are planned, else the estimate.
  Duration? get duration {
    final d = plan.departAt, a = plan.arriveAt;
    if (d != null && a != null && a.isAfter(d)) return a.difference(d);
    return estimatedDuration;
  }

  LegStatus get status {
    if (plan.arrivedAt != null) return LegStatus.done;
    if (plan.departedAt != null) return LegStatus.underway;
    return LegStatus.planned;
  }

  /// When the group should arrive: the planned time, or departure plus the
  /// expected duration once underway.
  DateTime? get eta {
    if (plan.arrivedAt != null) return plan.arrivedAt;
    final left = plan.departedAt;
    final d = duration;
    if (left != null && d != null) return left.add(d);
    return plan.arriveAt;
  }

  /// Google Maps directions for this leg.
  Uri get directionsUri => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'origin': from.mapsQuery,
        'destination': to.mapsQuery,
        'travelmode': plan.mode.mapsTravelMode,
      });
}

/// Where the group is right now on its route, from a GPS position.
class LivePosition {
  const LivePosition({
    required this.leg,
    required this.kmToNext,
    required this.fraction,
    required this.eta,
  });

  /// The leg underway, or the next one when none is.
  final RouteLeg leg;

  /// Road km left to the leg's end, estimated.
  final int kmToNext;

  /// How far along the leg, 0 to 1.
  final double fraction;
  final DateTime eta;
}

class RoutePlan {
  RoutePlan._(this.points, this.legs);

  /// Builds the route for [group]: the origin, each stop in order and, when
  /// set, the origin again.
  factory RoutePlan.of(TourGroup group) {
    final originPreset = presetForName(group.originCity);
    final origin = RoutePoint(
      id: TourGroup.originId,
      name: group.originCity,
      lat: originPreset?.lat,
      lng: originPreset?.lng,
    );
    final stops = [
      for (final s in group.effectiveStops) _pointFor(s),
    ];
    final points = [origin, ...stops, if (group.returnHome) origin];
    final legs = <RouteLeg>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final key = '${points[i].id}>${points[i + 1].id}';
      legs.add(RouteLeg(
        key: key,
        index: i,
        from: points[i],
        to: points[i + 1],
        plan: group.legPlans[key] ?? const LegPlan(),
      ));
    }
    return RoutePlan._(points, legs);
  }

  static RoutePoint _pointFor(TourStop s) {
    final preset = presetById(s.presetId) ?? presetForName(s.name);
    return RoutePoint(
      id: s.id,
      name: s.name,
      lat: s.lat ?? preset?.lat,
      lng: s.lng ?? preset?.lng,
      stop: s,
    );
  }

  final List<RoutePoint> points;
  final List<RouteLeg> legs;

  /// Total km over the legs whose distance is known.
  int get totalKm => legs.fold(0, (n, l) => n + (l.km ?? 0));

  int get doneKm => legs
      .where((l) => l.status == LegStatus.done)
      .fold(0, (n, l) => n + (l.km ?? 0));

  /// The leg being travelled, if any.
  RouteLeg? get currentLeg {
    for (final l in legs) {
      if (l.status == LegStatus.underway) return l;
    }
    return null;
  }

  /// The first leg not yet started.
  RouteLeg? get nextLeg {
    for (final l in legs) {
      if (l.status == LegStatus.planned) return l;
    }
    return null;
  }

  bool get isFinished =>
      legs.isNotEmpty && legs.every((l) => l.status == LegStatus.done);

  /// Share of the route done, by legs completed.
  double get progress => legs.isEmpty
      ? 0
      : legs.where((l) => l.status == LegStatus.done).length / legs.length;

  /// Where a GPS fix at [lat], [lng] puts the group on the current leg (or
  /// the next one). Null when that leg's ends have no coordinates.
  LivePosition? locate(double lat, double lng, DateTime now) {
    final leg = currentLeg ?? nextLeg;
    if (leg == null || !leg.from.hasLocation || !leg.to.hasLocation) {
      return null;
    }
    final fromKm = haversineKm(leg.from.lat!, leg.from.lng!, lat, lng);
    final toKm = haversineKm(lat, lng, leg.to.lat!, leg.to.lng!);
    final fraction = fromKm + toKm == 0 ? 1.0 : fromKm / (fromKm + toKm);
    final left = toKm * leg.plan.mode.detourFactor;
    final minutes = left / leg.plan.mode.averageKmh * 60;
    return LivePosition(
      leg: leg,
      kmToNext: left.round(),
      fraction: fraction.clamp(0.0, 1.0),
      eta: now.add(Duration(minutes: minutes.round())),
    );
  }

  /// Google Maps directions through every point. Maps links take up to nine
  /// waypoints; longer routes are linked leg by leg instead.
  Uri? get directionsUri {
    if (points.length < 2) return null;
    final via = points.sublist(1, points.length - 1);
    if (via.length > 9) return null;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': points.first.mapsQuery,
      'destination': points.last.mapsQuery,
      if (via.isNotEmpty) 'waypoints': via.map((p) => p.mapsQuery).join('|'),
      'travelmode': 'driving',
    });
  }
}

/// A Google Maps search for [what] (such as "hospital") near a position, or
/// near the user when the position is unknown.
Uri nearbySearchUri(String what, {double? lat, double? lng}) {
  final query =
      lat == null || lng == null ? '$what near me' : '$what near $lat,$lng';
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
}
