// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trip_log.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TripLog _$TripLogFromJson(Map<String, dynamic> json) {
  return _TripLog.fromJson(json);
}

/// @nodoc
mixin _$TripLog {
  String get tripId => throw _privateConstructorUsedError;
  String get authorId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  List<TripBlock> get blocks => throw _privateConstructorUsedError;
  List<GeoCoordinate> get routePoints => throw _privateConstructorUsedError;
  List<CostItem> get costItems => throw _privateConstructorUsedError;
  String get locationPinId => throw _privateConstructorUsedError;
  int get trustScore => throw _privateConstructorUsedError;
  int get helpfulVotes => throw _privateConstructorUsedError;
  @DateTimeConverter()
  DateTime get lastConfirmed => throw _privateConstructorUsedError;
  String get division => throw _privateConstructorUsedError;
  String get district => throw _privateConstructorUsedError;
  bool get hidden => throw _privateConstructorUsedError;
  TrustTier get tier => throw _privateConstructorUsedError;
  SyncStatus get syncStatus => throw _privateConstructorUsedError;
  bool get isPremiumGuide => throw _privateConstructorUsedError;
  String? get hiddenReason => throw _privateConstructorUsedError;
  @NullableDateTimeConverter()
  DateTime? get publishedAt =>
      throw _privateConstructorUsedError; // ── Travel Diary fields ──────────────────────────────────────────────────
  /// Who can see this entry: private | friends | community
  DiaryVisibility get visibility => throw _privateConstructorUsedError;

  /// Auto-stamped weather at time of first save
  WeatherSnapshot? get weatherAtVisit => throw _privateConstructorUsedError;

  /// Emotional tone of the trip
  TripMood? get mood => throw _privateConstructorUsedError;

  /// Travel-style tags (solo, family, nature, heritage, etc.)
  List<String> get tags => throw _privateConstructorUsedError;

  /// Reaction counts: {'wantToGo': 5, 'beenHere': 12, 'learned': 3, 'beautiful': 8}
  Map<String, int> get reactions => throw _privateConstructorUsedError;

  /// Co-author UIDs who contributed blocks to this diary entry
  List<String> get coAuthors => throw _privateConstructorUsedError;

  /// When the actual trip started (separate from publishedAt)
  @NullableDateTimeConverter()
  DateTime? get tripStartDate => throw _privateConstructorUsedError;

  /// When the actual trip ended
  @NullableDateTimeConverter()
  DateTime? get tripEndDate => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TripLogCopyWith<TripLog> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TripLogCopyWith<$Res> {
  factory $TripLogCopyWith(TripLog value, $Res Function(TripLog) then) =
      _$TripLogCopyWithImpl<$Res, TripLog>;
  @useResult
  $Res call(
      {String tripId,
      String authorId,
      String title,
      List<TripBlock> blocks,
      List<GeoCoordinate> routePoints,
      List<CostItem> costItems,
      String locationPinId,
      int trustScore,
      int helpfulVotes,
      @DateTimeConverter() DateTime lastConfirmed,
      String division,
      String district,
      bool hidden,
      TrustTier tier,
      SyncStatus syncStatus,
      bool isPremiumGuide,
      String? hiddenReason,
      @NullableDateTimeConverter() DateTime? publishedAt,
      DiaryVisibility visibility,
      WeatherSnapshot? weatherAtVisit,
      TripMood? mood,
      List<String> tags,
      Map<String, int> reactions,
      List<String> coAuthors,
      @NullableDateTimeConverter() DateTime? tripStartDate,
      @NullableDateTimeConverter() DateTime? tripEndDate});

  $WeatherSnapshotCopyWith<$Res>? get weatherAtVisit;
}

/// @nodoc
class _$TripLogCopyWithImpl<$Res, $Val extends TripLog>
    implements $TripLogCopyWith<$Res> {
  _$TripLogCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tripId = null,
    Object? authorId = null,
    Object? title = null,
    Object? blocks = null,
    Object? routePoints = null,
    Object? costItems = null,
    Object? locationPinId = null,
    Object? trustScore = null,
    Object? helpfulVotes = null,
    Object? lastConfirmed = null,
    Object? division = null,
    Object? district = null,
    Object? hidden = null,
    Object? tier = null,
    Object? syncStatus = null,
    Object? isPremiumGuide = null,
    Object? hiddenReason = freezed,
    Object? publishedAt = freezed,
    Object? visibility = null,
    Object? weatherAtVisit = freezed,
    Object? mood = freezed,
    Object? tags = null,
    Object? reactions = null,
    Object? coAuthors = null,
    Object? tripStartDate = freezed,
    Object? tripEndDate = freezed,
  }) {
    return _then(_value.copyWith(
      tripId: null == tripId
          ? _value.tripId
          : tripId // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _value.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      blocks: null == blocks
          ? _value.blocks
          : blocks // ignore: cast_nullable_to_non_nullable
              as List<TripBlock>,
      routePoints: null == routePoints
          ? _value.routePoints
          : routePoints // ignore: cast_nullable_to_non_nullable
              as List<GeoCoordinate>,
      costItems: null == costItems
          ? _value.costItems
          : costItems // ignore: cast_nullable_to_non_nullable
              as List<CostItem>,
      locationPinId: null == locationPinId
          ? _value.locationPinId
          : locationPinId // ignore: cast_nullable_to_non_nullable
              as String,
      trustScore: null == trustScore
          ? _value.trustScore
          : trustScore // ignore: cast_nullable_to_non_nullable
              as int,
      helpfulVotes: null == helpfulVotes
          ? _value.helpfulVotes
          : helpfulVotes // ignore: cast_nullable_to_non_nullable
              as int,
      lastConfirmed: null == lastConfirmed
          ? _value.lastConfirmed
          : lastConfirmed // ignore: cast_nullable_to_non_nullable
              as DateTime,
      division: null == division
          ? _value.division
          : division // ignore: cast_nullable_to_non_nullable
              as String,
      district: null == district
          ? _value.district
          : district // ignore: cast_nullable_to_non_nullable
              as String,
      hidden: null == hidden
          ? _value.hidden
          : hidden // ignore: cast_nullable_to_non_nullable
              as bool,
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as TrustTier,
      syncStatus: null == syncStatus
          ? _value.syncStatus
          : syncStatus // ignore: cast_nullable_to_non_nullable
              as SyncStatus,
      isPremiumGuide: null == isPremiumGuide
          ? _value.isPremiumGuide
          : isPremiumGuide // ignore: cast_nullable_to_non_nullable
              as bool,
      hiddenReason: freezed == hiddenReason
          ? _value.hiddenReason
          : hiddenReason // ignore: cast_nullable_to_non_nullable
              as String?,
      publishedAt: freezed == publishedAt
          ? _value.publishedAt
          : publishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      visibility: null == visibility
          ? _value.visibility
          : visibility // ignore: cast_nullable_to_non_nullable
              as DiaryVisibility,
      weatherAtVisit: freezed == weatherAtVisit
          ? _value.weatherAtVisit
          : weatherAtVisit // ignore: cast_nullable_to_non_nullable
              as WeatherSnapshot?,
      mood: freezed == mood
          ? _value.mood
          : mood // ignore: cast_nullable_to_non_nullable
              as TripMood?,
      tags: null == tags
          ? _value.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      reactions: null == reactions
          ? _value.reactions
          : reactions // ignore: cast_nullable_to_non_nullable
              as Map<String, int>,
      coAuthors: null == coAuthors
          ? _value.coAuthors
          : coAuthors // ignore: cast_nullable_to_non_nullable
              as List<String>,
      tripStartDate: freezed == tripStartDate
          ? _value.tripStartDate
          : tripStartDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      tripEndDate: freezed == tripEndDate
          ? _value.tripEndDate
          : tripEndDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $WeatherSnapshotCopyWith<$Res>? get weatherAtVisit {
    if (_value.weatherAtVisit == null) {
      return null;
    }

    return $WeatherSnapshotCopyWith<$Res>(_value.weatherAtVisit!, (value) {
      return _then(_value.copyWith(weatherAtVisit: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$TripLogImplCopyWith<$Res> implements $TripLogCopyWith<$Res> {
  factory _$$TripLogImplCopyWith(
          _$TripLogImpl value, $Res Function(_$TripLogImpl) then) =
      __$$TripLogImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String tripId,
      String authorId,
      String title,
      List<TripBlock> blocks,
      List<GeoCoordinate> routePoints,
      List<CostItem> costItems,
      String locationPinId,
      int trustScore,
      int helpfulVotes,
      @DateTimeConverter() DateTime lastConfirmed,
      String division,
      String district,
      bool hidden,
      TrustTier tier,
      SyncStatus syncStatus,
      bool isPremiumGuide,
      String? hiddenReason,
      @NullableDateTimeConverter() DateTime? publishedAt,
      DiaryVisibility visibility,
      WeatherSnapshot? weatherAtVisit,
      TripMood? mood,
      List<String> tags,
      Map<String, int> reactions,
      List<String> coAuthors,
      @NullableDateTimeConverter() DateTime? tripStartDate,
      @NullableDateTimeConverter() DateTime? tripEndDate});

  @override
  $WeatherSnapshotCopyWith<$Res>? get weatherAtVisit;
}

/// @nodoc
class __$$TripLogImplCopyWithImpl<$Res>
    extends _$TripLogCopyWithImpl<$Res, _$TripLogImpl>
    implements _$$TripLogImplCopyWith<$Res> {
  __$$TripLogImplCopyWithImpl(
      _$TripLogImpl _value, $Res Function(_$TripLogImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tripId = null,
    Object? authorId = null,
    Object? title = null,
    Object? blocks = null,
    Object? routePoints = null,
    Object? costItems = null,
    Object? locationPinId = null,
    Object? trustScore = null,
    Object? helpfulVotes = null,
    Object? lastConfirmed = null,
    Object? division = null,
    Object? district = null,
    Object? hidden = null,
    Object? tier = null,
    Object? syncStatus = null,
    Object? isPremiumGuide = null,
    Object? hiddenReason = freezed,
    Object? publishedAt = freezed,
    Object? visibility = null,
    Object? weatherAtVisit = freezed,
    Object? mood = freezed,
    Object? tags = null,
    Object? reactions = null,
    Object? coAuthors = null,
    Object? tripStartDate = freezed,
    Object? tripEndDate = freezed,
  }) {
    return _then(_$TripLogImpl(
      tripId: null == tripId
          ? _value.tripId
          : tripId // ignore: cast_nullable_to_non_nullable
              as String,
      authorId: null == authorId
          ? _value.authorId
          : authorId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      blocks: null == blocks
          ? _value._blocks
          : blocks // ignore: cast_nullable_to_non_nullable
              as List<TripBlock>,
      routePoints: null == routePoints
          ? _value._routePoints
          : routePoints // ignore: cast_nullable_to_non_nullable
              as List<GeoCoordinate>,
      costItems: null == costItems
          ? _value._costItems
          : costItems // ignore: cast_nullable_to_non_nullable
              as List<CostItem>,
      locationPinId: null == locationPinId
          ? _value.locationPinId
          : locationPinId // ignore: cast_nullable_to_non_nullable
              as String,
      trustScore: null == trustScore
          ? _value.trustScore
          : trustScore // ignore: cast_nullable_to_non_nullable
              as int,
      helpfulVotes: null == helpfulVotes
          ? _value.helpfulVotes
          : helpfulVotes // ignore: cast_nullable_to_non_nullable
              as int,
      lastConfirmed: null == lastConfirmed
          ? _value.lastConfirmed
          : lastConfirmed // ignore: cast_nullable_to_non_nullable
              as DateTime,
      division: null == division
          ? _value.division
          : division // ignore: cast_nullable_to_non_nullable
              as String,
      district: null == district
          ? _value.district
          : district // ignore: cast_nullable_to_non_nullable
              as String,
      hidden: null == hidden
          ? _value.hidden
          : hidden // ignore: cast_nullable_to_non_nullable
              as bool,
      tier: null == tier
          ? _value.tier
          : tier // ignore: cast_nullable_to_non_nullable
              as TrustTier,
      syncStatus: null == syncStatus
          ? _value.syncStatus
          : syncStatus // ignore: cast_nullable_to_non_nullable
              as SyncStatus,
      isPremiumGuide: null == isPremiumGuide
          ? _value.isPremiumGuide
          : isPremiumGuide // ignore: cast_nullable_to_non_nullable
              as bool,
      hiddenReason: freezed == hiddenReason
          ? _value.hiddenReason
          : hiddenReason // ignore: cast_nullable_to_non_nullable
              as String?,
      publishedAt: freezed == publishedAt
          ? _value.publishedAt
          : publishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      visibility: null == visibility
          ? _value.visibility
          : visibility // ignore: cast_nullable_to_non_nullable
              as DiaryVisibility,
      weatherAtVisit: freezed == weatherAtVisit
          ? _value.weatherAtVisit
          : weatherAtVisit // ignore: cast_nullable_to_non_nullable
              as WeatherSnapshot?,
      mood: freezed == mood
          ? _value.mood
          : mood // ignore: cast_nullable_to_non_nullable
              as TripMood?,
      tags: null == tags
          ? _value._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      reactions: null == reactions
          ? _value._reactions
          : reactions // ignore: cast_nullable_to_non_nullable
              as Map<String, int>,
      coAuthors: null == coAuthors
          ? _value._coAuthors
          : coAuthors // ignore: cast_nullable_to_non_nullable
              as List<String>,
      tripStartDate: freezed == tripStartDate
          ? _value.tripStartDate
          : tripStartDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      tripEndDate: freezed == tripEndDate
          ? _value.tripEndDate
          : tripEndDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TripLogImpl implements _TripLog {
  const _$TripLogImpl(
      {required this.tripId,
      required this.authorId,
      required this.title,
      required final List<TripBlock> blocks,
      required final List<GeoCoordinate> routePoints,
      required final List<CostItem> costItems,
      required this.locationPinId,
      required this.trustScore,
      required this.helpfulVotes,
      @DateTimeConverter() required this.lastConfirmed,
      required this.division,
      required this.district,
      this.hidden = false,
      this.tier = TrustTier.unverified,
      this.syncStatus = SyncStatus.synced,
      this.isPremiumGuide = false,
      this.hiddenReason,
      @NullableDateTimeConverter() this.publishedAt,
      this.visibility = DiaryVisibility.community,
      this.weatherAtVisit,
      this.mood,
      final List<String> tags = const [],
      final Map<String, int> reactions = const {},
      final List<String> coAuthors = const [],
      @NullableDateTimeConverter() this.tripStartDate,
      @NullableDateTimeConverter() this.tripEndDate})
      : _blocks = blocks,
        _routePoints = routePoints,
        _costItems = costItems,
        _tags = tags,
        _reactions = reactions,
        _coAuthors = coAuthors;

  factory _$TripLogImpl.fromJson(Map<String, dynamic> json) =>
      _$$TripLogImplFromJson(json);

  @override
  final String tripId;
  @override
  final String authorId;
  @override
  final String title;
  final List<TripBlock> _blocks;
  @override
  List<TripBlock> get blocks {
    if (_blocks is EqualUnmodifiableListView) return _blocks;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_blocks);
  }

  final List<GeoCoordinate> _routePoints;
  @override
  List<GeoCoordinate> get routePoints {
    if (_routePoints is EqualUnmodifiableListView) return _routePoints;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_routePoints);
  }

  final List<CostItem> _costItems;
  @override
  List<CostItem> get costItems {
    if (_costItems is EqualUnmodifiableListView) return _costItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_costItems);
  }

  @override
  final String locationPinId;
  @override
  final int trustScore;
  @override
  final int helpfulVotes;
  @override
  @DateTimeConverter()
  final DateTime lastConfirmed;
  @override
  final String division;
  @override
  final String district;
  @override
  @JsonKey()
  final bool hidden;
  @override
  @JsonKey()
  final TrustTier tier;
  @override
  @JsonKey()
  final SyncStatus syncStatus;
  @override
  @JsonKey()
  final bool isPremiumGuide;
  @override
  final String? hiddenReason;
  @override
  @NullableDateTimeConverter()
  final DateTime? publishedAt;
// ── Travel Diary fields ──────────────────────────────────────────────────
  /// Who can see this entry: private | friends | community
  @override
  @JsonKey()
  final DiaryVisibility visibility;

  /// Auto-stamped weather at time of first save
  @override
  final WeatherSnapshot? weatherAtVisit;

  /// Emotional tone of the trip
  @override
  final TripMood? mood;

  /// Travel-style tags (solo, family, nature, heritage, etc.)
  final List<String> _tags;

  /// Travel-style tags (solo, family, nature, heritage, etc.)
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  /// Reaction counts: {'wantToGo': 5, 'beenHere': 12, 'learned': 3, 'beautiful': 8}
  final Map<String, int> _reactions;

  /// Reaction counts: {'wantToGo': 5, 'beenHere': 12, 'learned': 3, 'beautiful': 8}
  @override
  @JsonKey()
  Map<String, int> get reactions {
    if (_reactions is EqualUnmodifiableMapView) return _reactions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_reactions);
  }

  /// Co-author UIDs who contributed blocks to this diary entry
  final List<String> _coAuthors;

  /// Co-author UIDs who contributed blocks to this diary entry
  @override
  @JsonKey()
  List<String> get coAuthors {
    if (_coAuthors is EqualUnmodifiableListView) return _coAuthors;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_coAuthors);
  }

  /// When the actual trip started (separate from publishedAt)
  @override
  @NullableDateTimeConverter()
  final DateTime? tripStartDate;

  /// When the actual trip ended
  @override
  @NullableDateTimeConverter()
  final DateTime? tripEndDate;

  @override
  String toString() {
    return 'TripLog(tripId: $tripId, authorId: $authorId, title: $title, blocks: $blocks, routePoints: $routePoints, costItems: $costItems, locationPinId: $locationPinId, trustScore: $trustScore, helpfulVotes: $helpfulVotes, lastConfirmed: $lastConfirmed, division: $division, district: $district, hidden: $hidden, tier: $tier, syncStatus: $syncStatus, isPremiumGuide: $isPremiumGuide, hiddenReason: $hiddenReason, publishedAt: $publishedAt, visibility: $visibility, weatherAtVisit: $weatherAtVisit, mood: $mood, tags: $tags, reactions: $reactions, coAuthors: $coAuthors, tripStartDate: $tripStartDate, tripEndDate: $tripEndDate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TripLogImpl &&
            (identical(other.tripId, tripId) || other.tripId == tripId) &&
            (identical(other.authorId, authorId) ||
                other.authorId == authorId) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality().equals(other._blocks, _blocks) &&
            const DeepCollectionEquality()
                .equals(other._routePoints, _routePoints) &&
            const DeepCollectionEquality()
                .equals(other._costItems, _costItems) &&
            (identical(other.locationPinId, locationPinId) ||
                other.locationPinId == locationPinId) &&
            (identical(other.trustScore, trustScore) ||
                other.trustScore == trustScore) &&
            (identical(other.helpfulVotes, helpfulVotes) ||
                other.helpfulVotes == helpfulVotes) &&
            (identical(other.lastConfirmed, lastConfirmed) ||
                other.lastConfirmed == lastConfirmed) &&
            (identical(other.division, division) ||
                other.division == division) &&
            (identical(other.district, district) ||
                other.district == district) &&
            (identical(other.hidden, hidden) || other.hidden == hidden) &&
            (identical(other.tier, tier) || other.tier == tier) &&
            (identical(other.syncStatus, syncStatus) ||
                other.syncStatus == syncStatus) &&
            (identical(other.isPremiumGuide, isPremiumGuide) ||
                other.isPremiumGuide == isPremiumGuide) &&
            (identical(other.hiddenReason, hiddenReason) ||
                other.hiddenReason == hiddenReason) &&
            (identical(other.publishedAt, publishedAt) ||
                other.publishedAt == publishedAt) &&
            (identical(other.visibility, visibility) ||
                other.visibility == visibility) &&
            (identical(other.weatherAtVisit, weatherAtVisit) ||
                other.weatherAtVisit == weatherAtVisit) &&
            (identical(other.mood, mood) || other.mood == mood) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            const DeepCollectionEquality()
                .equals(other._reactions, _reactions) &&
            const DeepCollectionEquality()
                .equals(other._coAuthors, _coAuthors) &&
            (identical(other.tripStartDate, tripStartDate) ||
                other.tripStartDate == tripStartDate) &&
            (identical(other.tripEndDate, tripEndDate) ||
                other.tripEndDate == tripEndDate));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        tripId,
        authorId,
        title,
        const DeepCollectionEquality().hash(_blocks),
        const DeepCollectionEquality().hash(_routePoints),
        const DeepCollectionEquality().hash(_costItems),
        locationPinId,
        trustScore,
        helpfulVotes,
        lastConfirmed,
        division,
        district,
        hidden,
        tier,
        syncStatus,
        isPremiumGuide,
        hiddenReason,
        publishedAt,
        visibility,
        weatherAtVisit,
        mood,
        const DeepCollectionEquality().hash(_tags),
        const DeepCollectionEquality().hash(_reactions),
        const DeepCollectionEquality().hash(_coAuthors),
        tripStartDate,
        tripEndDate
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TripLogImplCopyWith<_$TripLogImpl> get copyWith =>
      __$$TripLogImplCopyWithImpl<_$TripLogImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TripLogImplToJson(
      this,
    );
  }
}

abstract class _TripLog implements TripLog {
  const factory _TripLog(
          {required final String tripId,
          required final String authorId,
          required final String title,
          required final List<TripBlock> blocks,
          required final List<GeoCoordinate> routePoints,
          required final List<CostItem> costItems,
          required final String locationPinId,
          required final int trustScore,
          required final int helpfulVotes,
          @DateTimeConverter() required final DateTime lastConfirmed,
          required final String division,
          required final String district,
          final bool hidden,
          final TrustTier tier,
          final SyncStatus syncStatus,
          final bool isPremiumGuide,
          final String? hiddenReason,
          @NullableDateTimeConverter() final DateTime? publishedAt,
          final DiaryVisibility visibility,
          final WeatherSnapshot? weatherAtVisit,
          final TripMood? mood,
          final List<String> tags,
          final Map<String, int> reactions,
          final List<String> coAuthors,
          @NullableDateTimeConverter() final DateTime? tripStartDate,
          @NullableDateTimeConverter() final DateTime? tripEndDate}) =
      _$TripLogImpl;

  factory _TripLog.fromJson(Map<String, dynamic> json) = _$TripLogImpl.fromJson;

  @override
  String get tripId;
  @override
  String get authorId;
  @override
  String get title;
  @override
  List<TripBlock> get blocks;
  @override
  List<GeoCoordinate> get routePoints;
  @override
  List<CostItem> get costItems;
  @override
  String get locationPinId;
  @override
  int get trustScore;
  @override
  int get helpfulVotes;
  @override
  @DateTimeConverter()
  DateTime get lastConfirmed;
  @override
  String get division;
  @override
  String get district;
  @override
  bool get hidden;
  @override
  TrustTier get tier;
  @override
  SyncStatus get syncStatus;
  @override
  bool get isPremiumGuide;
  @override
  String? get hiddenReason;
  @override
  @NullableDateTimeConverter()
  DateTime? get publishedAt;
  @override // ── Travel Diary fields ──────────────────────────────────────────────────
  /// Who can see this entry: private | friends | community
  DiaryVisibility get visibility;
  @override

  /// Auto-stamped weather at time of first save
  WeatherSnapshot? get weatherAtVisit;
  @override

  /// Emotional tone of the trip
  TripMood? get mood;
  @override

  /// Travel-style tags (solo, family, nature, heritage, etc.)
  List<String> get tags;
  @override

  /// Reaction counts: {'wantToGo': 5, 'beenHere': 12, 'learned': 3, 'beautiful': 8}
  Map<String, int> get reactions;
  @override

  /// Co-author UIDs who contributed blocks to this diary entry
  List<String> get coAuthors;
  @override

  /// When the actual trip started (separate from publishedAt)
  @NullableDateTimeConverter()
  DateTime? get tripStartDate;
  @override

  /// When the actual trip ended
  @NullableDateTimeConverter()
  DateTime? get tripEndDate;
  @override
  @JsonKey(ignore: true)
  _$$TripLogImplCopyWith<_$TripLogImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
