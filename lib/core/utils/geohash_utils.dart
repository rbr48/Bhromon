import 'dart:math';
import '../value_objects/geo_coordinate.dart';

class GeoHashUtils {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const Map<String, int> _base32Map = {
    '0': 0,
    '1': 1,
    '2': 2,
    '3': 3,
    '4': 4,
    '5': 5,
    '6': 6,
    '7': 7,
    '8': 8,
    '9': 9,
    'b': 10,
    'c': 11,
    'd': 12,
    'e': 13,
    'f': 14,
    'g': 15,
    'h': 16,
    'j': 17,
    'k': 18,
    'm': 19,
    'n': 20,
    'p': 21,
    'q': 22,
    'r': 23,
    's': 24,
    't': 25,
    'u': 26,
    'v': 27,
    'w': 28,
    'x': 29,
    'y': 30,
    'z': 31
  };

  static String encode(double latitude, double longitude, {int precision = 9}) {
    double latMin = -90.0, latMax = 90.0;
    double lonMin = -180.0, lonMax = 180.0;

    StringBuffer geohash = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (geohash.length < precision) {
      if (isEven) {
        double mid = (lonMin + lonMax) / 2.0;
        if (longitude > mid) {
          ch |= (1 << (4 - bit));
          lonMin = mid;
        } else {
          lonMax = mid;
        }
      } else {
        double mid = (latMin + latMax) / 2.0;
        if (latitude > mid) {
          ch |= (1 << (4 - bit));
          latMin = mid;
        } else {
          latMax = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        geohash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return geohash.toString();
  }

  static GeoCoordinate decode(String geohash) {
    double latMin = -90.0, latMax = 90.0;
    double lonMin = -180.0, lonMax = 180.0;

    bool isEven = true;
    for (int i = 0; i < geohash.length; i++) {
      int? cd = _base32Map[geohash[i]];
      if (cd == null) throw ArgumentError('Invalid geohash character');

      for (int mask = 16; mask > 0; mask >>= 1) {
        if (isEven) {
          double mid = (lonMin + lonMax) / 2;
          if ((cd & mask) != 0) {
            lonMin = mid;
          } else {
            lonMax = mid;
          }
        } else {
          double mid = (latMin + latMax) / 2;
          if ((cd & mask) != 0) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isEven = !isEven;
      }
    }
    return GeoCoordinate(
      latitude: (latMin + latMax) / 2,
      longitude: (lonMin + lonMax) / 2,
    );
  }

  // Simplified approximation of adjacent cells for Firestore geoqueries
  static List<String> getNeighbourCells(GeoCoordinate centre, double radiusKm,
      {int precision = 6}) {
    // In practice, we query the center geohash and its 8 neighboring cells to cover a full radius.
    // Let's implement neighbor calculations.

    // We can compute adjacent cells using standard geohash rules.
    // Since complex geohash arithmetic can be verbose, we can define a lookup/shift mechanism.
    // Let's implement a simplified grid offset.
    // 0.045 degrees is approximately 5 km at the equator.
    final double latOffset = (radiusKm / 111.0);
    final double lngOffset =
        (radiusKm / (111.0 * cos(centre.latitude * pi / 180.0)));

    final List<double> latDirs = [-latOffset, 0, latOffset];
    final List<double> lngDirs = [-lngOffset, 0, lngOffset];

    final Set<String> hashes = {};
    for (final dy in latDirs) {
      for (final dx in lngDirs) {
        final hash = encode(centre.latitude + dy, centre.longitude + dx,
            precision: precision);
        hashes.add(hash);
      }
    }
    return hashes.toList();
  }
}
