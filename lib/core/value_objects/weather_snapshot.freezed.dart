// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'weather_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WeatherSnapshot _$WeatherSnapshotFromJson(Map<String, dynamic> json) {
  return _WeatherSnapshot.fromJson(json);
}

/// @nodoc
mixin _$WeatherSnapshot {
  double get tempC => throw _privateConstructorUsedError;
  String get emoji => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  double get precipMm => throw _privateConstructorUsedError;
  double get windKph => throw _privateConstructorUsedError;
  int get weatherCode => throw _privateConstructorUsedError;
  bool get isSafeToVisit => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WeatherSnapshotCopyWith<WeatherSnapshot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WeatherSnapshotCopyWith<$Res> {
  factory $WeatherSnapshotCopyWith(
          WeatherSnapshot value, $Res Function(WeatherSnapshot) then) =
      _$WeatherSnapshotCopyWithImpl<$Res, WeatherSnapshot>;
  @useResult
  $Res call(
      {double tempC,
      String emoji,
      String description,
      double precipMm,
      double windKph,
      int weatherCode,
      bool isSafeToVisit});
}

/// @nodoc
class _$WeatherSnapshotCopyWithImpl<$Res, $Val extends WeatherSnapshot>
    implements $WeatherSnapshotCopyWith<$Res> {
  _$WeatherSnapshotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tempC = null,
    Object? emoji = null,
    Object? description = null,
    Object? precipMm = null,
    Object? windKph = null,
    Object? weatherCode = null,
    Object? isSafeToVisit = null,
  }) {
    return _then(_value.copyWith(
      tempC: null == tempC
          ? _value.tempC
          : tempC // ignore: cast_nullable_to_non_nullable
              as double,
      emoji: null == emoji
          ? _value.emoji
          : emoji // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      precipMm: null == precipMm
          ? _value.precipMm
          : precipMm // ignore: cast_nullable_to_non_nullable
              as double,
      windKph: null == windKph
          ? _value.windKph
          : windKph // ignore: cast_nullable_to_non_nullable
              as double,
      weatherCode: null == weatherCode
          ? _value.weatherCode
          : weatherCode // ignore: cast_nullable_to_non_nullable
              as int,
      isSafeToVisit: null == isSafeToVisit
          ? _value.isSafeToVisit
          : isSafeToVisit // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WeatherSnapshotImplCopyWith<$Res>
    implements $WeatherSnapshotCopyWith<$Res> {
  factory _$$WeatherSnapshotImplCopyWith(_$WeatherSnapshotImpl value,
          $Res Function(_$WeatherSnapshotImpl) then) =
      __$$WeatherSnapshotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double tempC,
      String emoji,
      String description,
      double precipMm,
      double windKph,
      int weatherCode,
      bool isSafeToVisit});
}

/// @nodoc
class __$$WeatherSnapshotImplCopyWithImpl<$Res>
    extends _$WeatherSnapshotCopyWithImpl<$Res, _$WeatherSnapshotImpl>
    implements _$$WeatherSnapshotImplCopyWith<$Res> {
  __$$WeatherSnapshotImplCopyWithImpl(
      _$WeatherSnapshotImpl _value, $Res Function(_$WeatherSnapshotImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? tempC = null,
    Object? emoji = null,
    Object? description = null,
    Object? precipMm = null,
    Object? windKph = null,
    Object? weatherCode = null,
    Object? isSafeToVisit = null,
  }) {
    return _then(_$WeatherSnapshotImpl(
      tempC: null == tempC
          ? _value.tempC
          : tempC // ignore: cast_nullable_to_non_nullable
              as double,
      emoji: null == emoji
          ? _value.emoji
          : emoji // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      precipMm: null == precipMm
          ? _value.precipMm
          : precipMm // ignore: cast_nullable_to_non_nullable
              as double,
      windKph: null == windKph
          ? _value.windKph
          : windKph // ignore: cast_nullable_to_non_nullable
              as double,
      weatherCode: null == weatherCode
          ? _value.weatherCode
          : weatherCode // ignore: cast_nullable_to_non_nullable
              as int,
      isSafeToVisit: null == isSafeToVisit
          ? _value.isSafeToVisit
          : isSafeToVisit // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WeatherSnapshotImpl implements _WeatherSnapshot {
  const _$WeatherSnapshotImpl(
      {required this.tempC,
      required this.emoji,
      required this.description,
      required this.precipMm,
      required this.windKph,
      required this.weatherCode,
      this.isSafeToVisit = false});

  factory _$WeatherSnapshotImpl.fromJson(Map<String, dynamic> json) =>
      _$$WeatherSnapshotImplFromJson(json);

  @override
  final double tempC;
  @override
  final String emoji;
  @override
  final String description;
  @override
  final double precipMm;
  @override
  final double windKph;
  @override
  final int weatherCode;
  @override
  @JsonKey()
  final bool isSafeToVisit;

  @override
  String toString() {
    return 'WeatherSnapshot(tempC: $tempC, emoji: $emoji, description: $description, precipMm: $precipMm, windKph: $windKph, weatherCode: $weatherCode, isSafeToVisit: $isSafeToVisit)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WeatherSnapshotImpl &&
            (identical(other.tempC, tempC) || other.tempC == tempC) &&
            (identical(other.emoji, emoji) || other.emoji == emoji) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.precipMm, precipMm) ||
                other.precipMm == precipMm) &&
            (identical(other.windKph, windKph) || other.windKph == windKph) &&
            (identical(other.weatherCode, weatherCode) ||
                other.weatherCode == weatherCode) &&
            (identical(other.isSafeToVisit, isSafeToVisit) ||
                other.isSafeToVisit == isSafeToVisit));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, tempC, emoji, description,
      precipMm, windKph, weatherCode, isSafeToVisit);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WeatherSnapshotImplCopyWith<_$WeatherSnapshotImpl> get copyWith =>
      __$$WeatherSnapshotImplCopyWithImpl<_$WeatherSnapshotImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WeatherSnapshotImplToJson(
      this,
    );
  }
}

abstract class _WeatherSnapshot implements WeatherSnapshot {
  const factory _WeatherSnapshot(
      {required final double tempC,
      required final String emoji,
      required final String description,
      required final double precipMm,
      required final double windKph,
      required final int weatherCode,
      final bool isSafeToVisit}) = _$WeatherSnapshotImpl;

  factory _WeatherSnapshot.fromJson(Map<String, dynamic> json) =
      _$WeatherSnapshotImpl.fromJson;

  @override
  double get tempC;
  @override
  String get emoji;
  @override
  String get description;
  @override
  double get precipMm;
  @override
  double get windKph;
  @override
  int get weatherCode;
  @override
  bool get isSafeToVisit;
  @override
  @JsonKey(ignore: true)
  _$$WeatherSnapshotImplCopyWith<_$WeatherSnapshotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
