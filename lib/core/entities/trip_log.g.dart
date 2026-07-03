// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TripLogImpl _$$TripLogImplFromJson(Map json) => _$TripLogImpl(
      tripId: json['tripId'] as String,
      authorId: json['authorId'] as String,
      title: json['title'] as String,
      blocks: (json['blocks'] as List<dynamic>)
          .map((e) => TripBlock.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      routePoints: (json['routePoints'] as List<dynamic>)
          .map((e) =>
              GeoCoordinate.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      costItems: (json['costItems'] as List<dynamic>)
          .map((e) => CostItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      locationPinId: json['locationPinId'] as String,
      trustScore: (json['trustScore'] as num).toInt(),
      helpfulVotes: (json['helpfulVotes'] as num).toInt(),
      lastConfirmed: const DateTimeConverter().fromJson(json['lastConfirmed']),
      division: json['division'] as String,
      district: json['district'] as String,
      hidden: json['hidden'] as bool? ?? false,
      tier: $enumDecodeNullable(_$TrustTierEnumMap, json['tier']) ??
          TrustTier.unverified,
      syncStatus:
          $enumDecodeNullable(_$SyncStatusEnumMap, json['syncStatus']) ??
              SyncStatus.synced,
      isPremiumGuide: json['isPremiumGuide'] as bool? ?? false,
      hiddenReason: json['hiddenReason'] as String?,
      publishedAt:
          const NullableDateTimeConverter().fromJson(json['publishedAt']),
      visibility:
          $enumDecodeNullable(_$DiaryVisibilityEnumMap, json['visibility']) ??
              DiaryVisibility.community,
      weatherAtVisit: json['weatherAtVisit'] == null
          ? null
          : WeatherSnapshot.fromJson(
              Map<String, dynamic>.from(json['weatherAtVisit'] as Map)),
      mood: $enumDecodeNullable(_$TripMoodEnumMap, json['mood']),
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      reactions: (json['reactions'] as Map?)?.map(
            (k, e) => MapEntry(k as String, (e as num).toInt()),
          ) ??
          const {},
      coAuthors: (json['coAuthors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      tripStartDate:
          const NullableDateTimeConverter().fromJson(json['tripStartDate']),
      tripEndDate:
          const NullableDateTimeConverter().fromJson(json['tripEndDate']),
    );

Map<String, dynamic> _$$TripLogImplToJson(_$TripLogImpl instance) =>
    <String, dynamic>{
      'tripId': instance.tripId,
      'authorId': instance.authorId,
      'title': instance.title,
      'blocks': instance.blocks.map((e) => e.toJson()).toList(),
      'routePoints': instance.routePoints.map((e) => e.toJson()).toList(),
      'costItems': instance.costItems.map((e) => e.toJson()).toList(),
      'locationPinId': instance.locationPinId,
      'trustScore': instance.trustScore,
      'helpfulVotes': instance.helpfulVotes,
      'lastConfirmed': const DateTimeConverter().toJson(instance.lastConfirmed),
      'division': instance.division,
      'district': instance.district,
      'hidden': instance.hidden,
      'tier': _$TrustTierEnumMap[instance.tier]!,
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus]!,
      'isPremiumGuide': instance.isPremiumGuide,
      'hiddenReason': instance.hiddenReason,
      'publishedAt':
          const NullableDateTimeConverter().toJson(instance.publishedAt),
      'visibility': _$DiaryVisibilityEnumMap[instance.visibility]!,
      'weatherAtVisit': instance.weatherAtVisit?.toJson(),
      'mood': _$TripMoodEnumMap[instance.mood],
      'tags': instance.tags,
      'reactions': instance.reactions,
      'coAuthors': instance.coAuthors,
      'tripStartDate':
          const NullableDateTimeConverter().toJson(instance.tripStartDate),
      'tripEndDate':
          const NullableDateTimeConverter().toJson(instance.tripEndDate),
    };

const _$TrustTierEnumMap = {
  TrustTier.unverified: 'unverified',
  TrustTier.community: 'community',
  TrustTier.verified: 'verified',
  TrustTier.regionExpert: 'regionExpert',
  TrustTier.pioneer: 'pioneer',
};

const _$SyncStatusEnumMap = {
  SyncStatus.synced: 'synced',
  SyncStatus.pendingUpload: 'pendingUpload',
  SyncStatus.conflict: 'conflict',
  SyncStatus.failed: 'failed',
};

const _$DiaryVisibilityEnumMap = {
  DiaryVisibility.private: 'private',
  DiaryVisibility.friends: 'friends',
  DiaryVisibility.community: 'community',
};

const _$TripMoodEnumMap = {
  TripMood.adventure: 'adventure',
  TripMood.peaceful: 'peaceful',
  TripMood.spiritual: 'spiritual',
  TripMood.thrilling: 'thrilling',
  TripMood.family: 'family',
  TripMood.romantic: 'romantic',
};
