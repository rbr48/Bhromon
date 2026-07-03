// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explorer_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ExplorerProfileImpl _$$ExplorerProfileImplFromJson(Map json) =>
    _$ExplorerProfileImpl(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String,
      explorerScore: ExplorerScore.fromJson(
          Map<String, dynamic>.from(json['explorerScore'] as Map)),
      tier: $enumDecode(_$TrustTierEnumMap, json['tier']),
      badges:
          (json['badges'] as List<dynamic>).map((e) => e as String).toList(),
      division: json['division'] as String,
      createdAt: const DateTimeConverter().fromJson(json['createdAt']),
      isPioneer: json['isPioneer'] as bool? ?? false,
      isRegionExpert: json['isRegionExpert'] as bool? ?? false,
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      coverUrl: json['coverUrl'] as String?,
      districtsDiaryLogged: (json['districtsDiaryLogged'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      savedTripLogIds: (json['savedTripLogIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      totalTripDays: (json['totalTripDays'] as num?)?.toInt() ?? 0,
      totalSpentBDT: (json['totalSpentBDT'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$$ExplorerProfileImplToJson(
        _$ExplorerProfileImpl instance) =>
    <String, dynamic>{
      'uid': instance.uid,
      'displayName': instance.displayName,
      'explorerScore': instance.explorerScore.toJson(),
      'tier': _$TrustTierEnumMap[instance.tier]!,
      'badges': instance.badges,
      'division': instance.division,
      'createdAt': const DateTimeConverter().toJson(instance.createdAt),
      'isPioneer': instance.isPioneer,
      'isRegionExpert': instance.isRegionExpert,
      'avatarUrl': instance.avatarUrl,
      'bio': instance.bio,
      'coverUrl': instance.coverUrl,
      'districtsDiaryLogged': instance.districtsDiaryLogged,
      'savedTripLogIds': instance.savedTripLogIds,
      'totalTripDays': instance.totalTripDays,
      'totalSpentBDT': instance.totalSpentBDT,
    };

const _$TrustTierEnumMap = {
  TrustTier.unverified: 'unverified',
  TrustTier.community: 'community',
  TrustTier.verified: 'verified',
  TrustTier.regionExpert: 'regionExpert',
  TrustTier.pioneer: 'pioneer',
};
