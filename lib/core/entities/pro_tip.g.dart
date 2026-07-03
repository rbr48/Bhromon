// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pro_tip.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ProTipImpl _$$ProTipImplFromJson(Map json) => _$ProTipImpl(
      tipId: json['tipId'] as String,
      locationPinId: json['locationPinId'] as String,
      authorId: json['authorId'] as String,
      text: json['text'] as String,
      category: json['category'] as String,
      helpfulVotes: (json['helpfulVotes'] as num).toInt(),
      outdatedVotes: (json['outdatedVotes'] as num).toInt(),
      lastConfirmed: DateTime.parse(json['lastConfirmed'] as String),
      decayStatus: $enumDecode(_$DecayStatusEnumMap, json['decayStatus']),
      hidden: json['hidden'] as bool? ?? false,
    );

Map<String, dynamic> _$$ProTipImplToJson(_$ProTipImpl instance) =>
    <String, dynamic>{
      'tipId': instance.tipId,
      'locationPinId': instance.locationPinId,
      'authorId': instance.authorId,
      'text': instance.text,
      'category': instance.category,
      'helpfulVotes': instance.helpfulVotes,
      'outdatedVotes': instance.outdatedVotes,
      'lastConfirmed': instance.lastConfirmed.toIso8601String(),
      'decayStatus': _$DecayStatusEnumMap[instance.decayStatus]!,
      'hidden': instance.hidden,
    };

const _$DecayStatusEnumMap = {
  DecayStatus.fresh: 'fresh',
  DecayStatus.aging: 'aging',
  DecayStatus.stale: 'stale',
};
