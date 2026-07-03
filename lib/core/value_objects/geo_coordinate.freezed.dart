// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'geo_coordinate.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

GeoCoordinate _$GeoCoordinateFromJson(Map<String, dynamic> json) {
  return _GeoCoordinate.fromJson(json);
}

/// @nodoc
mixin _$GeoCoordinate {
  double get latitude => throw _privateConstructorUsedError;
  double get longitude => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GeoCoordinateCopyWith<GeoCoordinate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GeoCoordinateCopyWith<$Res> {
  factory $GeoCoordinateCopyWith(
          GeoCoordinate value, $Res Function(GeoCoordinate) then) =
      _$GeoCoordinateCopyWithImpl<$Res, GeoCoordinate>;
  @useResult
  $Res call({double latitude, double longitude});
}

/// @nodoc
class _$GeoCoordinateCopyWithImpl<$Res, $Val extends GeoCoordinate>
    implements $GeoCoordinateCopyWith<$Res> {
  _$GeoCoordinateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? latitude = null,
    Object? longitude = null,
  }) {
    return _then(_value.copyWith(
      latitude: null == latitude
          ? _value.latitude
          : latitude // ignore: cast_nullable_to_non_nullable
              as double,
      longitude: null == longitude
          ? _value.longitude
          : longitude // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GeoCoordinateImplCopyWith<$Res>
    implements $GeoCoordinateCopyWith<$Res> {
  factory _$$GeoCoordinateImplCopyWith(
          _$GeoCoordinateImpl value, $Res Function(_$GeoCoordinateImpl) then) =
      __$$GeoCoordinateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double latitude, double longitude});
}

/// @nodoc
class __$$GeoCoordinateImplCopyWithImpl<$Res>
    extends _$GeoCoordinateCopyWithImpl<$Res, _$GeoCoordinateImpl>
    implements _$$GeoCoordinateImplCopyWith<$Res> {
  __$$GeoCoordinateImplCopyWithImpl(
      _$GeoCoordinateImpl _value, $Res Function(_$GeoCoordinateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? latitude = null,
    Object? longitude = null,
  }) {
    return _then(_$GeoCoordinateImpl(
      latitude: null == latitude
          ? _value.latitude
          : latitude // ignore: cast_nullable_to_non_nullable
              as double,
      longitude: null == longitude
          ? _value.longitude
          : longitude // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GeoCoordinateImpl extends _GeoCoordinate {
  const _$GeoCoordinateImpl({required this.latitude, required this.longitude})
      : super._();

  factory _$GeoCoordinateImpl.fromJson(Map<String, dynamic> json) =>
      _$$GeoCoordinateImplFromJson(json);

  @override
  final double latitude;
  @override
  final double longitude;

  @override
  String toString() {
    return 'GeoCoordinate(latitude: $latitude, longitude: $longitude)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GeoCoordinateImpl &&
            (identical(other.latitude, latitude) ||
                other.latitude == latitude) &&
            (identical(other.longitude, longitude) ||
                other.longitude == longitude));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, latitude, longitude);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GeoCoordinateImplCopyWith<_$GeoCoordinateImpl> get copyWith =>
      __$$GeoCoordinateImplCopyWithImpl<_$GeoCoordinateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GeoCoordinateImplToJson(
      this,
    );
  }
}

abstract class _GeoCoordinate extends GeoCoordinate {
  const factory _GeoCoordinate(
      {required final double latitude,
      required final double longitude}) = _$GeoCoordinateImpl;
  const _GeoCoordinate._() : super._();

  factory _GeoCoordinate.fromJson(Map<String, dynamic> json) =
      _$GeoCoordinateImpl.fromJson;

  @override
  double get latitude;
  @override
  double get longitude;
  @override
  @JsonKey(ignore: true)
  _$$GeoCoordinateImplCopyWith<_$GeoCoordinateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
