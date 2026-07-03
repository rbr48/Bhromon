// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_bundle.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OfflineBundleImpl _$$OfflineBundleImplFromJson(Map json) =>
    _$OfflineBundleImpl(
      districtId: json['districtId'] as String,
      districtName: json['districtName'] as String,
      pins: (json['pins'] as List<dynamic>)
          .map((e) => LocationPin.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      trips: (json['trips'] as List<dynamic>)
          .map((e) => TripLog.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      tips: (json['tips'] as List<dynamic>)
          .map((e) => ProTip.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      tileKeys:
          (json['tileKeys'] as List<dynamic>).map((e) => e as String).toList(),
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      syncStatus:
          $enumDecodeNullable(_$SyncStatusEnumMap, json['syncStatus']) ??
              SyncStatus.synced,
    );

Map<String, dynamic> _$$OfflineBundleImplToJson(_$OfflineBundleImpl instance) =>
    <String, dynamic>{
      'districtId': instance.districtId,
      'districtName': instance.districtName,
      'pins': instance.pins.map((e) => e.toJson()).toList(),
      'trips': instance.trips.map((e) => e.toJson()).toList(),
      'tips': instance.tips.map((e) => e.toJson()).toList(),
      'tileKeys': instance.tileKeys,
      'downloadedAt': instance.downloadedAt.toIso8601String(),
      'sizeBytes': instance.sizeBytes,
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus]!,
    };

const _$SyncStatusEnumMap = {
  SyncStatus.synced: 'synced',
  SyncStatus.pendingUpload: 'pendingUpload',
  SyncStatus.conflict: 'conflict',
  SyncStatus.failed: 'failed',
};
