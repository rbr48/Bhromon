import 'dart:math' as math;

/// Geohash encoding and radius query bounds, following geofire-common's
/// algorithm (Cloud Functions use the same one, functions/src/lib/geohash.ts,
/// to keep `location_pins.geoHash` current).
///
/// To find pins within a radius, query each `(start, end)` pair from
/// [geohashQueryBounds] with `orderBy('geoHash').startAt([start]).endAt([end])`
/// and drop results farther than the radius with [distanceInMeters]: the
/// ranges cover the circle but also some area around it.

const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
const int _bitsPerChar = 5;
const int _maximumBitsPrecision = 22 * _bitsPerChar;
const double _earthMeridionalCircumference = 40007860;
const double _metersPerDegreeLatitude = 110574;
const double _earthEquatorialRadius = 6378137.0;
const double _e2 = 0.00669447819799;
const double _epsilon = 1e-12;

/// Characters stored on each pin: ~1 m cells.
const int kGeohashPrecision = 10;

/// Geohash of ([lat], [lng]) with [precision] characters.
String encodeGeohash(double lat, double lng,
    [int precision = kGeohashPrecision]) {
  if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
    throw ArgumentError('invalid coordinates ($lat, $lng)');
  }
  var latMin = -90.0, latMax = 90.0, lngMin = -180.0, lngMax = 180.0;
  final hash = StringBuffer();
  var value = 0, bits = 0;
  var evenBit = true;
  while (hash.length < precision) {
    if (evenBit) {
      final mid = (lngMin + lngMax) / 2;
      if (lng > mid) {
        value = (value << 1) + 1;
        lngMin = mid;
      } else {
        value = value << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat > mid) {
        value = (value << 1) + 1;
        latMin = mid;
      } else {
        value = value << 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (bits < 4) {
      bits++;
    } else {
      hash.write(_base32[value]);
      bits = 0;
      value = 0;
    }
  }
  return hash.toString();
}

/// Great-circle distance in metres (haversine).
double distanceInMeters(double lat1, double lng1, double lat2, double lng2) {
  const radius = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Geohash ranges that together cover every point within [radiusMeters] of
/// ([lat], [lng]).
List<(String start, String end)> geohashQueryBounds(
    double lat, double lng, double radiusMeters) {
  final queryBits = math.max(1, _boundingBoxBits(lat, lng, radiusMeters));
  final precision = (queryBits / _bitsPerChar).ceil();
  final queries = [
    for (final (cLat, cLng) in _boundingBoxCoordinates(lat, lng, radiusMeters))
      _geohashQuery(encodeGeohash(cLat, cLng, precision), queryBits),
  ];
  final unique = <(String, String)>[];
  for (final q in queries) {
    if (!unique.contains(q)) unique.add(q);
  }
  return unique;
}

double _log2(double x) => math.log(x) / math.ln2;

double _metersToLongitudeDegrees(double distance, double latitude) {
  final radians = latitude * math.pi / 180;
  final num = math.cos(radians) * _earthEquatorialRadius * math.pi / 180;
  final denom = 1 / math.sqrt(1 - _e2 * math.sin(radians) * math.sin(radians));
  final deltaDeg = num * denom;
  if (deltaDeg < _epsilon) return distance > 0 ? 360 : 0;
  return math.min(360, distance / deltaDeg);
}

double _longitudeBitsForResolution(double resolution, double latitude) {
  final degs = _metersToLongitudeDegrees(resolution, latitude);
  return degs.abs() > 0.000001 ? math.max(1, _log2(360 / degs)) : 1;
}

double _latitudeBitsForResolution(double resolution) => math.min(
    _log2(_earthMeridionalCircumference / 2 / resolution),
    _maximumBitsPrecision.toDouble());

double _wrapLongitude(double longitude) {
  if (longitude <= 180 && longitude >= -180) return longitude;
  final adjusted = longitude + 180;
  if (adjusted > 0) return (adjusted % 360) - 180;
  return 180 - (-adjusted % 360);
}

int _boundingBoxBits(double lat, double lng, double size) {
  final latDelta = size / _metersPerDegreeLatitude;
  final north = math.min(90.0, lat + latDelta);
  final south = math.max(-90.0, lat - latDelta);
  final bitsLat = _latitudeBitsForResolution(size).floor() * 2;
  final bitsLngNorth = _longitudeBitsForResolution(size, north).floor() * 2 - 1;
  final bitsLngSouth = _longitudeBitsForResolution(size, south).floor() * 2 - 1;
  return [bitsLat, bitsLngNorth, bitsLngSouth, _maximumBitsPrecision]
      .reduce(math.min);
}

List<(double, double)> _boundingBoxCoordinates(
    double lat, double lng, double radius) {
  final latDegrees = radius / _metersPerDegreeLatitude;
  final north = math.min(90.0, lat + latDegrees);
  final south = math.max(-90.0, lat - latDegrees);
  final lngDegs = math.max(_metersToLongitudeDegrees(radius, north),
      _metersToLongitudeDegrees(radius, south));
  final west = _wrapLongitude(lng - lngDegs);
  final east = _wrapLongitude(lng + lngDegs);
  return [
    (lat, lng),
    (lat, west),
    (lat, east),
    (north, lng),
    (north, west),
    (north, east),
    (south, lng),
    (south, west),
    (south, east),
  ];
}

(String, String) _geohashQuery(String geohash, int bits) {
  final precision = (bits / _bitsPerChar).ceil();
  if (geohash.length < precision) return (geohash, '$geohash~');
  final hash = geohash.substring(0, precision);
  final base = hash.substring(0, hash.length - 1);
  final lastValue = _base32.indexOf(hash[hash.length - 1]);
  final significantBits = bits - base.length * _bitsPerChar;
  final unusedBits = _bitsPerChar - significantBits;
  final startValue = (lastValue >> unusedBits) << unusedBits;
  final endValue = startValue + (1 << unusedBits);
  if (endValue > 31) return ('$base${_base32[startValue]}', '$base~');
  return ('$base${_base32[startValue]}', '$base${_base32[endValue]}');
}
