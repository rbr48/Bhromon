// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'location_pin.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

LocationPin _$LocationPinFromJson(Map<String, dynamic> json) {
  return _LocationPin.fromJson(json);
}

/// @nodoc
mixin _$LocationPin {
  String get pinId => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get geoHash => throw _privateConstructorUsedError;
  double get lat => throw _privateConstructorUsedError;
  double get lng => throw _privateConstructorUsedError;
  TrustTier get trustTier => throw _privateConstructorUsedError;
  DateTime get lastConfirmed => throw _privateConstructorUsedError;
  List<String> get linkedTripIds => throw _privateConstructorUsedError;
  List<String> get linkedTipIds => throw _privateConstructorUsedError;
  String get division => throw _privateConstructorUsedError;
  String get district => throw _privateConstructorUsedError;
  String get createdByUid => throw _privateConstructorUsedError;
  bool get hidden => throw _privateConstructorUsedError;
  String? get businessProfileId =>
      throw _privateConstructorUsedError; // Rich metadata fields (optional, populated by enrichment bot / user edit)
  String? get imageUrl => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String get category =>
      throw _privateConstructorUsedError; // e.g. waterfall, beach, temple, forest, market, heritage, hill, place
  double get averageRating => throw _privateConstructorUsedError;
  int get visitCount => throw _privateConstructorUsedError;
  List<String> get photos => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $LocationPinCopyWith<LocationPin> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LocationPinCopyWith<$Res> {
  factory $LocationPinCopyWith(
          LocationPin value, $Res Function(LocationPin) then) =
      _$LocationPinCopyWithImpl<$Res, LocationPin>;
  @useResult
  $Res call(
      {String pinId,
      String name,
      String geoHash,
      double lat,
      double lng,
      TrustTier trustTier,
      DateTime lastConfirmed,
      List<String> linkedTripIds,
      List<String> linkedTipIds,
      String division,
      String district,
      String createdByUid,
      bool hidden,
      String? businessProfileId,
      String? imageUrl,
      String? description,
      String category,
      double averageRating,
      int visitCount,
      List<String> photos});
}

/// @nodoc
class _$LocationPinCopyWithImpl<$Res, $Val extends LocationPin>
    implements $LocationPinCopyWith<$Res> {
  _$LocationPinCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pinId = null,
    Object? name = null,
    Object? geoHash = null,
    Object? lat = null,
    Object? lng = null,
    Object? trustTier = null,
    Object? lastConfirmed = null,
    Object? linkedTripIds = null,
    Object? linkedTipIds = null,
    Object? division = null,
    Object? district = null,
    Object? createdByUid = null,
    Object? hidden = null,
    Object? businessProfileId = freezed,
    Object? imageUrl = freezed,
    Object? description = freezed,
    Object? category = null,
    Object? averageRating = null,
    Object? visitCount = null,
    Object? photos = null,
  }) {
    return _then(_value.copyWith(
      pinId: null == pinId
          ? _value.pinId
          : pinId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      geoHash: null == geoHash
          ? _value.geoHash
          : geoHash // ignore: cast_nullable_to_non_nullable
              as String,
      lat: null == lat
          ? _value.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _value.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      trustTier: null == trustTier
          ? _value.trustTier
          : trustTier // ignore: cast_nullable_to_non_nullable
              as TrustTier,
      lastConfirmed: null == lastConfirmed
          ? _value.lastConfirmed
          : lastConfirmed // ignore: cast_nullable_to_non_nullable
              as DateTime,
      linkedTripIds: null == linkedTripIds
          ? _value.linkedTripIds
          : linkedTripIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      linkedTipIds: null == linkedTipIds
          ? _value.linkedTipIds
          : linkedTipIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      division: null == division
          ? _value.division
          : division // ignore: cast_nullable_to_non_nullable
              as String,
      district: null == district
          ? _value.district
          : district // ignore: cast_nullable_to_non_nullable
              as String,
      createdByUid: null == createdByUid
          ? _value.createdByUid
          : createdByUid // ignore: cast_nullable_to_non_nullable
              as String,
      hidden: null == hidden
          ? _value.hidden
          : hidden // ignore: cast_nullable_to_non_nullable
              as bool,
      businessProfileId: freezed == businessProfileId
          ? _value.businessProfileId
          : businessProfileId // ignore: cast_nullable_to_non_nullable
              as String?,
      imageUrl: freezed == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String,
      averageRating: null == averageRating
          ? _value.averageRating
          : averageRating // ignore: cast_nullable_to_non_nullable
              as double,
      visitCount: null == visitCount
          ? _value.visitCount
          : visitCount // ignore: cast_nullable_to_non_nullable
              as int,
      photos: null == photos
          ? _value.photos
          : photos // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$LocationPinImplCopyWith<$Res>
    implements $LocationPinCopyWith<$Res> {
  factory _$$LocationPinImplCopyWith(
          _$LocationPinImpl value, $Res Function(_$LocationPinImpl) then) =
      __$$LocationPinImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String pinId,
      String name,
      String geoHash,
      double lat,
      double lng,
      TrustTier trustTier,
      DateTime lastConfirmed,
      List<String> linkedTripIds,
      List<String> linkedTipIds,
      String division,
      String district,
      String createdByUid,
      bool hidden,
      String? businessProfileId,
      String? imageUrl,
      String? description,
      String category,
      double averageRating,
      int visitCount,
      List<String> photos});
}

/// @nodoc
class __$$LocationPinImplCopyWithImpl<$Res>
    extends _$LocationPinCopyWithImpl<$Res, _$LocationPinImpl>
    implements _$$LocationPinImplCopyWith<$Res> {
  __$$LocationPinImplCopyWithImpl(
      _$LocationPinImpl _value, $Res Function(_$LocationPinImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pinId = null,
    Object? name = null,
    Object? geoHash = null,
    Object? lat = null,
    Object? lng = null,
    Object? trustTier = null,
    Object? lastConfirmed = null,
    Object? linkedTripIds = null,
    Object? linkedTipIds = null,
    Object? division = null,
    Object? district = null,
    Object? createdByUid = null,
    Object? hidden = null,
    Object? businessProfileId = freezed,
    Object? imageUrl = freezed,
    Object? description = freezed,
    Object? category = null,
    Object? averageRating = null,
    Object? visitCount = null,
    Object? photos = null,
  }) {
    return _then(_$LocationPinImpl(
      pinId: null == pinId
          ? _value.pinId
          : pinId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      geoHash: null == geoHash
          ? _value.geoHash
          : geoHash // ignore: cast_nullable_to_non_nullable
              as String,
      lat: null == lat
          ? _value.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _value.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      trustTier: null == trustTier
          ? _value.trustTier
          : trustTier // ignore: cast_nullable_to_non_nullable
              as TrustTier,
      lastConfirmed: null == lastConfirmed
          ? _value.lastConfirmed
          : lastConfirmed // ignore: cast_nullable_to_non_nullable
              as DateTime,
      linkedTripIds: null == linkedTripIds
          ? _value._linkedTripIds
          : linkedTripIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      linkedTipIds: null == linkedTipIds
          ? _value._linkedTipIds
          : linkedTipIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      division: null == division
          ? _value.division
          : division // ignore: cast_nullable_to_non_nullable
              as String,
      district: null == district
          ? _value.district
          : district // ignore: cast_nullable_to_non_nullable
              as String,
      createdByUid: null == createdByUid
          ? _value.createdByUid
          : createdByUid // ignore: cast_nullable_to_non_nullable
              as String,
      hidden: null == hidden
          ? _value.hidden
          : hidden // ignore: cast_nullable_to_non_nullable
              as bool,
      businessProfileId: freezed == businessProfileId
          ? _value.businessProfileId
          : businessProfileId // ignore: cast_nullable_to_non_nullable
              as String?,
      imageUrl: freezed == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String,
      averageRating: null == averageRating
          ? _value.averageRating
          : averageRating // ignore: cast_nullable_to_non_nullable
              as double,
      visitCount: null == visitCount
          ? _value.visitCount
          : visitCount // ignore: cast_nullable_to_non_nullable
              as int,
      photos: null == photos
          ? _value._photos
          : photos // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LocationPinImpl implements _LocationPin {
  const _$LocationPinImpl(
      {required this.pinId,
      required this.name,
      required this.geoHash,
      required this.lat,
      required this.lng,
      required this.trustTier,
      required this.lastConfirmed,
      required final List<String> linkedTripIds,
      required final List<String> linkedTipIds,
      required this.division,
      required this.district,
      required this.createdByUid,
      this.hidden = false,
      this.businessProfileId,
      this.imageUrl,
      this.description,
      this.category = 'place',
      this.averageRating = 0.0,
      this.visitCount = 0,
      final List<String> photos = const []})
      : _linkedTripIds = linkedTripIds,
        _linkedTipIds = linkedTipIds,
        _photos = photos;

  factory _$LocationPinImpl.fromJson(Map<String, dynamic> json) =>
      _$$LocationPinImplFromJson(json);

  @override
  final String pinId;
  @override
  final String name;
  @override
  final String geoHash;
  @override
  final double lat;
  @override
  final double lng;
  @override
  final TrustTier trustTier;
  @override
  final DateTime lastConfirmed;
  final List<String> _linkedTripIds;
  @override
  List<String> get linkedTripIds {
    if (_linkedTripIds is EqualUnmodifiableListView) return _linkedTripIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedTripIds);
  }

  final List<String> _linkedTipIds;
  @override
  List<String> get linkedTipIds {
    if (_linkedTipIds is EqualUnmodifiableListView) return _linkedTipIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedTipIds);
  }

  @override
  final String division;
  @override
  final String district;
  @override
  final String createdByUid;
  @override
  @JsonKey()
  final bool hidden;
  @override
  final String? businessProfileId;
// Rich metadata fields (optional, populated by enrichment bot / user edit)
  @override
  final String? imageUrl;
  @override
  final String? description;
  @override
  @JsonKey()
  final String category;
// e.g. waterfall, beach, temple, forest, market, heritage, hill, place
  @override
  @JsonKey()
  final double averageRating;
  @override
  @JsonKey()
  final int visitCount;
  final List<String> _photos;
  @override
  @JsonKey()
  List<String> get photos {
    if (_photos is EqualUnmodifiableListView) return _photos;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_photos);
  }

  @override
  String toString() {
    return 'LocationPin(pinId: $pinId, name: $name, geoHash: $geoHash, lat: $lat, lng: $lng, trustTier: $trustTier, lastConfirmed: $lastConfirmed, linkedTripIds: $linkedTripIds, linkedTipIds: $linkedTipIds, division: $division, district: $district, createdByUid: $createdByUid, hidden: $hidden, businessProfileId: $businessProfileId, imageUrl: $imageUrl, description: $description, category: $category, averageRating: $averageRating, visitCount: $visitCount, photos: $photos)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LocationPinImpl &&
            (identical(other.pinId, pinId) || other.pinId == pinId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.geoHash, geoHash) || other.geoHash == geoHash) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.trustTier, trustTier) ||
                other.trustTier == trustTier) &&
            (identical(other.lastConfirmed, lastConfirmed) ||
                other.lastConfirmed == lastConfirmed) &&
            const DeepCollectionEquality()
                .equals(other._linkedTripIds, _linkedTripIds) &&
            const DeepCollectionEquality()
                .equals(other._linkedTipIds, _linkedTipIds) &&
            (identical(other.division, division) ||
                other.division == division) &&
            (identical(other.district, district) ||
                other.district == district) &&
            (identical(other.createdByUid, createdByUid) ||
                other.createdByUid == createdByUid) &&
            (identical(other.hidden, hidden) || other.hidden == hidden) &&
            (identical(other.businessProfileId, businessProfileId) ||
                other.businessProfileId == businessProfileId) &&
            (identical(other.imageUrl, imageUrl) ||
                other.imageUrl == imageUrl) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.category, category) ||
                other.category == category) &&
            (identical(other.averageRating, averageRating) ||
                other.averageRating == averageRating) &&
            (identical(other.visitCount, visitCount) ||
                other.visitCount == visitCount) &&
            const DeepCollectionEquality().equals(other._photos, _photos));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        pinId,
        name,
        geoHash,
        lat,
        lng,
        trustTier,
        lastConfirmed,
        const DeepCollectionEquality().hash(_linkedTripIds),
        const DeepCollectionEquality().hash(_linkedTipIds),
        division,
        district,
        createdByUid,
        hidden,
        businessProfileId,
        imageUrl,
        description,
        category,
        averageRating,
        visitCount,
        const DeepCollectionEquality().hash(_photos)
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LocationPinImplCopyWith<_$LocationPinImpl> get copyWith =>
      __$$LocationPinImplCopyWithImpl<_$LocationPinImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LocationPinImplToJson(
      this,
    );
  }
}

abstract class _LocationPin implements LocationPin {
  const factory _LocationPin(
      {required final String pinId,
      required final String name,
      required final String geoHash,
      required final double lat,
      required final double lng,
      required final TrustTier trustTier,
      required final DateTime lastConfirmed,
      required final List<String> linkedTripIds,
      required final List<String> linkedTipIds,
      required final String division,
      required final String district,
      required final String createdByUid,
      final bool hidden,
      final String? businessProfileId,
      final String? imageUrl,
      final String? description,
      final String category,
      final double averageRating,
      final int visitCount,
      final List<String> photos}) = _$LocationPinImpl;

  factory _LocationPin.fromJson(Map<String, dynamic> json) =
      _$LocationPinImpl.fromJson;

  @override
  String get pinId;
  @override
  String get name;
  @override
  String get geoHash;
  @override
  double get lat;
  @override
  double get lng;
  @override
  TrustTier get trustTier;
  @override
  DateTime get lastConfirmed;
  @override
  List<String> get linkedTripIds;
  @override
  List<String> get linkedTipIds;
  @override
  String get division;
  @override
  String get district;
  @override
  String get createdByUid;
  @override
  bool get hidden;
  @override
  String? get businessProfileId;
  @override // Rich metadata fields (optional, populated by enrichment bot / user edit)
  String? get imageUrl;
  @override
  String? get description;
  @override
  String get category;
  @override // e.g. waterfall, beach, temple, forest, market, heritage, hill, place
  double get averageRating;
  @override
  int get visitCount;
  @override
  List<String> get photos;
  @override
  @JsonKey(ignore: true)
  _$$LocationPinImplCopyWith<_$LocationPinImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
