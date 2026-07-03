// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explorer_score.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ExplorerScoreImpl _$$ExplorerScoreImplFromJson(Map json) =>
    _$ExplorerScoreImpl(
      value: (json['value'] as num).toInt(),
      tier: $enumDecode(_$TrustTierEnumMap, json['tier']),
    );

Map<String, dynamic> _$$ExplorerScoreImplToJson(_$ExplorerScoreImpl instance) =>
    <String, dynamic>{
      'value': instance.value,
      'tier': _$TrustTierEnumMap[instance.tier]!,
    };

const _$TrustTierEnumMap = {
  TrustTier.unverified: 'unverified',
  TrustTier.community: 'community',
  TrustTier.verified: 'verified',
  TrustTier.regionExpert: 'regionExpert',
  TrustTier.pioneer: 'pioneer',
};
