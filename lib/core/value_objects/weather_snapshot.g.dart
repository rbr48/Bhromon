// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WeatherSnapshotImpl _$$WeatherSnapshotImplFromJson(Map json) =>
    _$WeatherSnapshotImpl(
      tempC: (json['tempC'] as num).toDouble(),
      emoji: json['emoji'] as String,
      description: json['description'] as String,
      precipMm: (json['precipMm'] as num).toDouble(),
      windKph: (json['windKph'] as num).toDouble(),
      weatherCode: (json['weatherCode'] as num).toInt(),
      isSafeToVisit: json['isSafeToVisit'] as bool? ?? false,
    );

Map<String, dynamic> _$$WeatherSnapshotImplToJson(
        _$WeatherSnapshotImpl instance) =>
    <String, dynamic>{
      'tempC': instance.tempC,
      'emoji': instance.emoji,
      'description': instance.description,
      'precipMm': instance.precipMm,
      'windKph': instance.windKph,
      'weatherCode': instance.weatherCode,
      'isSafeToVisit': instance.isSafeToVisit,
    };
