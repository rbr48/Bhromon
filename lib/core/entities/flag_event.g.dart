// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flag_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FlagEventImpl _$$FlagEventImplFromJson(Map json) => _$FlagEventImpl(
      eventId: json['eventId'] as String,
      targetId: json['targetId'] as String,
      targetType: json['targetType'] as String,
      flagType: $enumDecode(_$FlagTypeEnumMap, json['flagType']),
      actorId: json['actorId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      reason: json['reason'] as String?,
    );

Map<String, dynamic> _$$FlagEventImplToJson(_$FlagEventImpl instance) =>
    <String, dynamic>{
      'eventId': instance.eventId,
      'targetId': instance.targetId,
      'targetType': instance.targetType,
      'flagType': _$FlagTypeEnumMap[instance.flagType]!,
      'actorId': instance.actorId,
      'timestamp': instance.timestamp.toIso8601String(),
      'reason': instance.reason,
    };

const _$FlagTypeEnumMap = {
  FlagType.outdated: 'outdated',
  FlagType.inaccurate: 'inaccurate',
  FlagType.spam: 'spam',
  FlagType.safety: 'safety',
};
