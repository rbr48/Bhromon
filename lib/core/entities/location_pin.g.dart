// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_pin.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$LocationPinImpl _$$LocationPinImplFromJson(Map json) => _$LocationPinImpl(
      pinId: json['pinId'] as String,
      name: json['name'] as String,
      geoHash: json['geoHash'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      trustTier: $enumDecode(_$TrustTierEnumMap, json['trustTier']),
      lastConfirmed: DateTime.parse(json['lastConfirmed'] as String),
      linkedTripIds: (json['linkedTripIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      linkedTipIds: (json['linkedTipIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      division: json['division'] as String,
      district: json['district'] as String,
      createdByUid: json['createdByUid'] as String,
      hidden: json['hidden'] as bool? ?? false,
      businessProfileId: json['businessProfileId'] as String?,
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      category: json['category'] as String? ?? 'place',
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      visitCount: (json['visitCount'] as num?)?.toInt() ?? 0,
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$LocationPinImplToJson(_$LocationPinImpl instance) =>
    <String, dynamic>{
      'pinId': instance.pinId,
      'name': instance.name,
      'geoHash': instance.geoHash,
      'lat': instance.lat,
      'lng': instance.lng,
      'trustTier': _$TrustTierEnumMap[instance.trustTier]!,
      'lastConfirmed': instance.lastConfirmed.toIso8601String(),
      'linkedTripIds': instance.linkedTripIds,
      'linkedTipIds': instance.linkedTipIds,
      'division': instance.division,
      'district': instance.district,
      'createdByUid': instance.createdByUid,
      'hidden': instance.hidden,
      'businessProfileId': instance.businessProfileId,
      'imageUrl': instance.imageUrl,
      'description': instance.description,
      'category': instance.category,
      'averageRating': instance.averageRating,
      'visitCount': instance.visitCount,
      'photos': instance.photos,
    };

const _$TrustTierEnumMap = {
  TrustTier.unverified: 'unverified',
  TrustTier.community: 'community',
  TrustTier.verified: 'verified',
  TrustTier.regionExpert: 'regionExpert',
  TrustTier.pioneer: 'pioneer',
};
