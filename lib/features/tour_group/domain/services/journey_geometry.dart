import 'dart:math' as math;

/// A place on Earth, in decimal degrees.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

/// Mean Earth radius, in metres.
const double kEarthRadiusM = 6371000;

double _radians(double degrees) => degrees * math.pi / 180;

/// Great-circle distance between two points, in metres.
double distanceM(GeoPoint a, GeoPoint b) {
  final dLat = _radians(b.lat - a.lat);
  final dLng = _radians(b.lng - a.lng);
  final sLat = math.sin(dLat / 2);
  final sLng = math.sin(dLng / 2);
  final h = sLat * sLat +
      math.cos(_radians(a.lat)) * math.cos(_radians(b.lat)) * sLng * sLng;
  return 2 * kEarthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Where a point falls on one straight segment.
class SegmentProjection {
  const SegmentProjection({required this.t, required this.crossTrackM});

  /// The closest point's position along the segment: 0 at the start and 1 at
  /// the end. It is below 0 or above 1 when the point lies past an end.
  final double t;

  /// The distance from the point to the closest point on the segment, in
  /// metres. Past an end, this is the distance to that end.
  final double crossTrackM;
}

/// Projects [p] onto the segment from [a] to [b]. The projection uses a flat
/// frame around [a], which is accurate over the few hundred kilometres a tour
/// covers.
SegmentProjection projectOntoSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
  const metresPerLat = kEarthRadiusM * math.pi / 180;
  final metresPerLng = metresPerLat * math.cos(_radians(a.lat));
  final bx = (b.lng - a.lng) * metresPerLng;
  final by = (b.lat - a.lat) * metresPerLat;
  final px = (p.lng - a.lng) * metresPerLng;
  final py = (p.lat - a.lat) * metresPerLat;
  final lengthSq = bx * bx + by * by;
  final t = lengthSq == 0 ? 0.0 : (px * bx + py * by) / lengthSq;
  final clamped = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  final dx = px - clamped * bx;
  final dy = py - clamped * by;
  return SegmentProjection(t: t, crossTrackM: math.sqrt(dx * dx + dy * dy));
}

/// Where a point sits on a [RoutePolyline].
class RouteProjection {
  const RouteProjection({
    required this.alongM,
    required this.crossTrackM,
    required this.segmentIndex,
    this.pastEndM = 0,
  });

  /// The distance along the route from its start to the closest point, in
  /// metres. Past the last point it keeps counting, so it can exceed the
  /// route's length.
  final double alongM;

  /// The distance from the point to the route, in metres.
  final double crossTrackM;

  /// The segment the closest point is on. The first segment is 0.
  final int segmentIndex;

  /// How far past the final point the closest point lies, in metres. Zero when
  /// the point is not beyond the end of the route.
  final double pastEndM;
}

/// A route: ordered points joined by straight segments.
class RoutePolyline {
  RoutePolyline(List<GeoPoint> points) : points = List.unmodifiable(points) {
    final along = <double>[0];
    final segments = <double>[];
    for (var i = 0; i + 1 < this.points.length; i++) {
      final length = distanceM(this.points[i], this.points[i + 1]);
      segments.add(length);
      along.add(along.last + length);
    }
    _segmentM = List.unmodifiable(segments);
    _alongAtPointM = List.unmodifiable(along);
  }

  final List<GeoPoint> points;
  late final List<double> _segmentM;
  late final List<double> _alongAtPointM;

  /// True when there are at least two points, so there is a route to follow.
  bool get isUsable => points.length >= 2;

  /// The route's length in metres, along its segments.
  double get lengthM => _alongAtPointM.last;

  /// The distance along the route to point [index], in metres.
  double alongOf(int index) => _alongAtPointM[index];

  /// Projects [p] onto the route. The route must be usable.
  RouteProjection project(GeoPoint p) {
    assert(isUsable, 'project needs at least two points');
    RouteProjection? best;
    for (var i = 0; i < _segmentM.length; i++) {
      final seg = projectOntoSegment(p, points[i], points[i + 1]);
      if (best != null && seg.crossTrackM >= best.crossTrackM) continue;
      final t = seg.t;
      final isLast = i == _segmentM.length - 1;
      double along;
      double pastEnd = 0;
      if (isLast && t > 1) {
        pastEnd = (t - 1) * _segmentM[i];
        along = _alongAtPointM[i + 1] + pastEnd;
      } else if (i == 0 && t < 0) {
        along = 0;
      } else {
        final clamped = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
        along = _alongAtPointM[i] + clamped * _segmentM[i];
      }
      best = RouteProjection(
        alongM: along,
        crossTrackM: seg.crossTrackM,
        segmentIndex: i,
        pastEndM: pastEnd,
      );
    }
    return best!;
  }
}
