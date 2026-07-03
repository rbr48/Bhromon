// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geo_coordinate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$GeoCoordinateImpl _$$GeoCoordinateImplFromJson(Map json) =>
    _$GeoCoordinateImpl(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );

Map<String, dynamic> _$$GeoCoordinateImplToJson(_$GeoCoordinateImpl instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
    };
