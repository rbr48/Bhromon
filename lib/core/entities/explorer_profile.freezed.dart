// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'explorer_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ExplorerProfile _$ExplorerProfileFromJson(Map<String, dynamic> json) {
  return _ExplorerProfile.fromJson(json);
}

/// @nodoc
mixin _$ExplorerProfile {
  String get uid => throw _privateConstructorUsedError;
  String get displayName => throw _privateConstructorUsedError;
  ExplorerScore get explorerScore => throw _privateConstructorUsedError;
  TrustTier get tier => throw _privateConstructorUsedError;
  List<String> get badges => throw _privateConstructorUsedError;
  String get division => throw _privateConstructorUsedError;
  @DateTimeConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;
  bool get isPioneer => throw _privateConstructorUsedError;
  bool get isRegionExpert => throw _privateConstructorUsedError;
  String? get avatarUrl => throw _privateConstructorUsedError;
  String? get bio => throw _privateConstructorUsedError;
  String? get coverUrl =>
      throw _privateConstructorUsedError; // ── Travel Diary stats ───────────────────────────────────────────────────
  /// District names where the user has saved diary entries
  List<String> get districtsDiaryLogged => throw _privateConstructorUsedError;

  /// Trip log IDs the user has bookmarked (saved diaries)
  List<String> get savedTripLogIds => throw _privateConstructorUsedError;

  /// Total number of travel days logged across all diary entries
  int get totalTripDays => throw _privateConstructorUsedError;

  /// Total BDT spent across all diary entries
  double get totalSpentBDT => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ExplorerProfileCopyWith<ExplorerProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExplorerProfileCopyWith<$Res> {
  factory $ExplorerProfileCopyWith(
          ExplorerProfile value, $Res Function(ExplorerProfile) then) =
      _$ExplorerProfileCopyWithImpl<$Res, ExplorerProfile>;
  @useResult
  $Res call(
      {String uid,
      String displayName,
      ExplorerScore explorerScore,
      TrustTier tier,
      List<String> badges,
      String division,
      @DateTimeConverter() DateTime createdAt,
      bool isPioneer,
      bool isRegionExpert,
      String? avatarUrl,
      String? bio,
      String? coverUrl,
      List<String> districtsDiaryLogged,
      List<String> savedTripLogIds,
      int totalTripDays,
      double totalSpentBDT});

  $ExplorerScoreCopyWith<$Res> get explorerScore;
}

/// @nodoc
class _$ExplorerProfileCopyWithImpl<$Res, $Val extends ExplorerProfile>
    implements $ExplorerProfileCopyWith<$Res> {
  _$ExplorerProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = null,
    Object? explorerScore = null,
    Object? tier = null,
    Object? badges = null,
    Object? division = null,
    Object? createdAt = null,
    Object? isPioneer = null,
    Object? isRegionExpert = null,
    Object? avatarUrl = freezed,
    Object? bio = freezed,
    Object? coverUrl = freezed,
    Object? districtsDiaryLogged = null,
    Object? savedTripLogIds = null,
    Object? totalTripDays = null,
    Object? totalSpentBDT = null,
  }) {
    return _then(_value.copyWith(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      explorerScore: null == explorerScore
          ? _value.explorerScore
          : explorerScore // ignore: cast_nullable_to_non_nullable
              as ExplorerScore,
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as TrustTier,
      badges: null == badges
          ? _value.badges
          : badges // ignore: cast_nullable_to_non_nullable
              as List<String>,
      division: null == division
          ? _value.division
          : division // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isPioneer: null == isPioneer
          ? _value.isPioneer
          : isPioneer // ignore: cast_nullable_to_non_nullable
              as bool,
      isRegionExpert: null == isRegionExpert
          ? _value.isRegionExpert
          : isRegionExpert // ignore: cast_nullable_to_non_nullable
              as bool,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      bio: freezed == bio
          ? _value.bio
          : bio // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _value.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      districtsDiaryLogged: null == districtsDiaryLogged
          ? _value.districtsDiaryLogged
          : districtsDiaryLogged // ignore: cast_nullable_to_non_nullable
              as List<String>,
      savedTripLogIds: null == savedTripLogIds
          ? _value.savedTripLogIds
          : savedTripLogIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      totalTripDays: null == totalTripDays
          ? _value.totalTripDays
          : totalTripDays // ignore: cast_nullable_to_non_nullable
              as int,
      totalSpentBDT: null == totalSpentBDT
          ? _value.totalSpentBDT
          : totalSpentBDT // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ExplorerScoreCopyWith<$Res> get explorerScore {
    return $ExplorerScoreCopyWith<$Res>(_value.explorerScore, (value) {
      return _then(_value.copyWith(explorerScore: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ExplorerProfileImplCopyWith<$Res>
    implements $ExplorerProfileCopyWith<$Res> {
  factory _$$ExplorerProfileImplCopyWith(_$ExplorerProfileImpl value,
          $Res Function(_$ExplorerProfileImpl) then) =
      __$$ExplorerProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String displayName,
      ExplorerScore explorerScore,
      TrustTier tier,
      List<String> badges,
      String division,
      @DateTimeConverter() DateTime createdAt,
      bool isPioneer,
      bool isRegionExpert,
      String? avatarUrl,
      String? bio,
      String? coverUrl,
      List<String> districtsDiaryLogged,
      List<String> savedTripLogIds,
      int totalTripDays,
      double totalSpentBDT});

  @override
  $ExplorerScoreCopyWith<$Res> get explorerScore;
}

/// @nodoc
class __$$ExplorerProfileImplCopyWithImpl<$Res>
    extends _$ExplorerProfileCopyWithImpl<$Res, _$ExplorerProfileImpl>
    implements _$$ExplorerProfileImplCopyWith<$Res> {
  __$$ExplorerProfileImplCopyWithImpl(
      _$ExplorerProfileImpl _value, $Res Function(_$ExplorerProfileImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? displayName = null,
    Object? explorerScore = null,
    Object? tier = null,
    Object? badges = null,
    Object? division = null,
    Object? createdAt = null,
    Object? isPioneer = null,
    Object? isRegionExpert = null,
    Object? avatarUrl = freezed,
    Object? bio = freezed,
    Object? coverUrl = freezed,
    Object? districtsDiaryLogged = null,
    Object? savedTripLogIds = null,
    Object? totalTripDays = null,
    Object? totalSpentBDT = null,
  }) {
    return _then(_$ExplorerProfileImpl(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      explorerScore: null == explorerScore
          ? _value.explorerScore
          : explorerScore // ignore: cast_nullable_to_non_nullable
              as ExplorerScore,
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as TrustTier,
      badges: null == badges
          ? _value._badges
          : badges // ignore: cast_nullable_to_non_nullable
              as List<String>,
      division: null == division
          ? _value.division
          : division // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isPioneer: null == isPioneer
          ? _value.isPioneer
          : isPioneer // ignore: cast_nullable_to_non_nullable
              as bool,
      isRegionExpert: null == isRegionExpert
          ? _value.isRegionExpert
          : isRegionExpert // ignore: cast_nullable_to_non_nullable
              as bool,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      bio: freezed == bio
          ? _value.bio
          : bio // ignore: cast_nullable_to_non_nullable
              as String?,
      coverUrl: freezed == coverUrl
          ? _value.coverUrl
          : coverUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      districtsDiaryLogged: null == districtsDiaryLogged
          ? _value._districtsDiaryLogged
          : districtsDiaryLogged // ignore: cast_nullable_to_non_nullable
              as List<String>,
      savedTripLogIds: null == savedTripLogIds
          ? _value._savedTripLogIds
          : savedTripLogIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      totalTripDays: null == totalTripDays
          ? _value.totalTripDays
          : totalTripDays // ignore: cast_nullable_to_non_nullable
              as int,
      totalSpentBDT: null == totalSpentBDT
          ? _value.totalSpentBDT
          : totalSpentBDT // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ExplorerProfileImpl implements _ExplorerProfile {
  const _$ExplorerProfileImpl(
      {required this.uid,
      required this.displayName,
      required this.explorerScore,
      required this.tier,
      required final List<String> badges,
      required this.division,
      @DateTimeConverter() required this.createdAt,
      this.isPioneer = false,
      this.isRegionExpert = false,
      this.avatarUrl,
      this.bio,
      this.coverUrl,
      final List<String> districtsDiaryLogged = const [],
      final List<String> savedTripLogIds = const [],
      this.totalTripDays = 0,
      this.totalSpentBDT = 0.0})
      : _badges = badges,
        _districtsDiaryLogged = districtsDiaryLogged,
        _savedTripLogIds = savedTripLogIds;

  factory _$ExplorerProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExplorerProfileImplFromJson(json);

  @override
  final String uid;
  @override
  final String displayName;
  @override
  final ExplorerScore explorerScore;
  @override
  final TrustTier tier;
  final List<String> _badges;
  @override
  List<String> get badges {
    if (_badges is EqualUnmodifiableListView) return _badges;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_badges);
  }

  @override
  final String division;
  @override
  @DateTimeConverter()
  final DateTime createdAt;
  @override
  @JsonKey()
  final bool isPioneer;
  @override
  @JsonKey()
  final bool isRegionExpert;
  @override
  final String? avatarUrl;
  @override
  final String? bio;
  @override
  final String? coverUrl;
// ── Travel Diary stats ───────────────────────────────────────────────────
  /// District names where the user has saved diary entries
  final List<String> _districtsDiaryLogged;
// ── Travel Diary stats ───────────────────────────────────────────────────
  /// District names where the user has saved diary entries
  @override
  @JsonKey()
  List<String> get districtsDiaryLogged {
    if (_districtsDiaryLogged is EqualUnmodifiableListView)
      return _districtsDiaryLogged;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_districtsDiaryLogged);
  }

  /// Trip log IDs the user has bookmarked (saved diaries)
  final List<String> _savedTripLogIds;

  /// Trip log IDs the user has bookmarked (saved diaries)
  @override
  @JsonKey()
  List<String> get savedTripLogIds {
    if (_savedTripLogIds is EqualUnmodifiableListView) return _savedTripLogIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_savedTripLogIds);
  }

  /// Total number of travel days logged across all diary entries
  @override
  @JsonKey()
  final int totalTripDays;

  /// Total BDT spent across all diary entries
  @override
  @JsonKey()
  final double totalSpentBDT;

  @override
  String toString() {
    return 'ExplorerProfile(uid: $uid, displayName: $displayName, explorerScore: $explorerScore, tier: $tier, badges: $badges, division: $division, createdAt: $createdAt, isPioneer: $isPioneer, isRegionExpert: $isRegionExpert, avatarUrl: $avatarUrl, bio: $bio, coverUrl: $coverUrl, districtsDiaryLogged: $districtsDiaryLogged, savedTripLogIds: $savedTripLogIds, totalTripDays: $totalTripDays, totalSpentBDT: $totalSpentBDT)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExplorerProfileImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.explorerScore, explorerScore) ||
                other.explorerScore == explorerScore) &&
            (identical(other.tier, tier) || other.tier == tier) &&
            const DeepCollectionEquality().equals(other._badges, _badges) &&
            (identical(other.division, division) ||
                other.division == division) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.isPioneer, isPioneer) ||
                other.isPioneer == isPioneer) &&
            (identical(other.isRegionExpert, isRegionExpert) ||
                other.isRegionExpert == isRegionExpert) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.bio, bio) || other.bio == bio) &&
            (identical(other.coverUrl, coverUrl) ||
                other.coverUrl == coverUrl) &&
            const DeepCollectionEquality()
                .equals(other._districtsDiaryLogged, _districtsDiaryLogged) &&
            const DeepCollectionEquality()
                .equals(other._savedTripLogIds, _savedTripLogIds) &&
            (identical(other.totalTripDays, totalTripDays) ||
                other.totalTripDays == totalTripDays) &&
            (identical(other.totalSpentBDT, totalSpentBDT) ||
                other.totalSpentBDT == totalSpentBDT));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      displayName,
      explorerScore,
      tier,
      const DeepCollectionEquality().hash(_badges),
      division,
      createdAt,
      isPioneer,
      isRegionExpert,
      avatarUrl,
      bio,
      coverUrl,
      const DeepCollectionEquality().hash(_districtsDiaryLogged),
      const DeepCollectionEquality().hash(_savedTripLogIds),
      totalTripDays,
      totalSpentBDT);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ExplorerProfileImplCopyWith<_$ExplorerProfileImpl> get copyWith =>
      __$$ExplorerProfileImplCopyWithImpl<_$ExplorerProfileImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExplorerProfileImplToJson(
      this,
    );
  }
}

abstract class _ExplorerProfile implements ExplorerProfile {
  const factory _ExplorerProfile(
      {required final String uid,
      required final String displayName,
      required final ExplorerScore explorerScore,
      required final TrustTier tier,
      required final List<String> badges,
      required final String division,
      @DateTimeConverter() required final DateTime createdAt,
      final bool isPioneer,
      final bool isRegionExpert,
      final String? avatarUrl,
      final String? bio,
      final String? coverUrl,
      final List<String> districtsDiaryLogged,
      final List<String> savedTripLogIds,
      final int totalTripDays,
      final double totalSpentBDT}) = _$ExplorerProfileImpl;

  factory _ExplorerProfile.fromJson(Map<String, dynamic> json) =
      _$ExplorerProfileImpl.fromJson;

  @override
  String get uid;
  @override
  String get displayName;
  @override
  ExplorerScore get explorerScore;
  @override
  TrustTier get tier;
  @override
  List<String> get badges;
  @override
  String get division;
  @override
  @DateTimeConverter()
  DateTime get createdAt;
  @override
  bool get isPioneer;
  @override
  bool get isRegionExpert;
  @override
  String? get avatarUrl;
  @override
  String? get bio;
  @override
  String? get coverUrl;
  @override // ── Travel Diary stats ───────────────────────────────────────────────────
  /// District names where the user has saved diary entries
  List<String> get districtsDiaryLogged;
  @override

  /// Trip log IDs the user has bookmarked (saved diaries)
  List<String> get savedTripLogIds;
  @override

  /// Total number of travel days logged across all diary entries
  int get totalTripDays;
  @override

  /// Total BDT spent across all diary entries
  double get totalSpentBDT;
  @override
  @JsonKey(ignore: true)
  _$$ExplorerProfileImplCopyWith<_$ExplorerProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
