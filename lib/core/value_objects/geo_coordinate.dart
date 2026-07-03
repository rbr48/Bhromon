import 'dart:math';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../utils/geohash_utils.dart';

part 'geo_coordinate.freezed.dart';
part 'geo_coordinate.g.dart';

@freezed
class GeoCoordinate with _$GeoCoordinate {
  const GeoCoordinate._();

  const factory GeoCoordinate({
    required double latitude,
    required double longitude,
  }) = _GeoCoordinate;

  factory GeoCoordinate.fromJson(Map<String, dynamic> json) =>
      _$GeoCoordinateFromJson(json);

  String toGeoHash({int precision = 9}) {
    return GeoHashUtils.encode(latitude, longitude, precision: precision);
  }

  double distanceTo(GeoCoordinate other) {
    const double earthRadiusKm = 6371.0;
    
    final double dLat = _degreesToRadians(other.latitude - latitude);
    final double dLng = _degreesToRadians(other.longitude - longitude);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(latitude)) *
            cos(_degreesToRadians(other.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
            
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }
}
