import 'dart:math' as math;

import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';

/// The route the journey tests use: three points on one parallel, about 102 km
/// end to end. A is the origin, B a stop about half way, and C the final
/// destination.
const GeoPoint kRouteA = GeoPoint(23.0, 90.0);
const GeoPoint kRouteB = GeoPoint(23.0, 90.5);
const GeoPoint kRouteC = GeoPoint(23.0, 91.0);

double _metresPerDegreeLat() => kEarthRadiusM * math.pi / 180;

/// [origin] moved [metres] east along its parallel. Negative values go west.
GeoPoint eastOf(GeoPoint origin, double metres) {
  final metresPerLng =
      _metresPerDegreeLat() * math.cos(origin.lat * math.pi / 180);
  return GeoPoint(origin.lat, origin.lng + metres / metresPerLng);
}

/// [origin] moved [metres] north along its meridian. Negative values go south.
GeoPoint northOf(GeoPoint origin, double metres) =>
    GeoPoint(origin.lat + metres / _metresPerDegreeLat(), origin.lng);
