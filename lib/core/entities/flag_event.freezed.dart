// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flag_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

FlagEvent _$FlagEventFromJson(Map<String, dynamic> json) {
  return _FlagEvent.fromJson(json);
}

/// @nodoc
mixin _$FlagEvent {
  String get eventId => throw _privateConstructorUsedError;
  String get targetId => throw _privateConstructorUsedError;
  String get targetType =>
      throw _privateConstructorUsedError; // 'trip_log' | 'pro_tip'
  FlagType get flagType => throw _privateConstructorUsedError;
  String get actorId => throw _privateConstructorUsedError;
  DateTime get timestamp => throw _privateConstructorUsedError;
  String? get reason => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FlagEventCopyWith<FlagEvent> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FlagEventCopyWith<$Res> {
  factory $FlagEventCopyWith(FlagEvent value, $Res Function(FlagEvent) then) =
      _$FlagEventCopyWithImpl<$Res, FlagEvent>;
  @useResult
  $Res call(
      {String eventId,
      String targetId,
      String targetType,
      FlagType flagType,
      String actorId,
      DateTime timestamp,
      String? reason});
}

/// @nodoc
class _$FlagEventCopyWithImpl<$Res, $Val extends FlagEvent>
    implements $FlagEventCopyWith<$Res> {
  _$FlagEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? eventId = null,
    Object? targetId = null,
    Object? targetType = null,
    Object? flagType = null,
    Object? actorId = null,
    Object? timestamp = null,
    Object? reason = freezed,
  }) {
    return _then(_value.copyWith(
      eventId: null == eventId
          ? _value.eventId
          : eventId // ignore: cast_nullable_to_non_nullable
              as String,
      targetId: null == targetId
          ? _value.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as String,
      targetType: null == targetType
          ? _value.targetType
          : targetType // ignore: cast_nullable_to_non_nullable
              as String,
      flagType: null == flagType
          ? _value.flagType
          : flagType // ignore: cast_nullable_to_non_nullable
              as FlagType,
      actorId: null == actorId
          ? _value.actorId
          : actorId // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      reason: freezed == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FlagEventImplCopyWith<$Res>
    implements $FlagEventCopyWith<$Res> {
  factory _$$FlagEventImplCopyWith(
          _$FlagEventImpl value, $Res Function(_$FlagEventImpl) then) =
      __$$FlagEventImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String eventId,
      String targetId,
      String targetType,
      FlagType flagType,
      String actorId,
      DateTime timestamp,
      String? reason});
}

/// @nodoc
class __$$FlagEventImplCopyWithImpl<$Res>
    extends _$FlagEventCopyWithImpl<$Res, _$FlagEventImpl>
    implements _$$FlagEventImplCopyWith<$Res> {
  __$$FlagEventImplCopyWithImpl(
      _$FlagEventImpl _value, $Res Function(_$FlagEventImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? eventId = null,
    Object? targetId = null,
    Object? targetType = null,
    Object? flagType = null,
    Object? actorId = null,
    Object? timestamp = null,
    Object? reason = freezed,
  }) {
    return _then(_$FlagEventImpl(
      eventId: null == eventId
          ? _value.eventId
          : eventId // ignore: cast_nullable_to_non_nullable
              as String,
      targetId: null == targetId
          ? _value.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as String,
      targetType: null == targetType
          ? _value.targetType
          : targetType // ignore: cast_nullable_to_non_nullable
              as String,
      flagType: null == flagType
          ? _value.flagType
          : flagType // ignore: cast_nullable_to_non_nullable
              as FlagType,
      actorId: null == actorId
          ? _value.actorId
          : actorId // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      reason: freezed == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FlagEventImpl implements _FlagEvent {
  const _$FlagEventImpl(
      {required this.eventId,
      required this.targetId,
      required this.targetType,
      required this.flagType,
      required this.actorId,
      required this.timestamp,
      this.reason});

  factory _$FlagEventImpl.fromJson(Map<String, dynamic> json) =>
      _$$FlagEventImplFromJson(json);

  @override
  final String eventId;
  @override
  final String targetId;
  @override
  final String targetType;
// 'trip_log' | 'pro_tip'
  @override
  final FlagType flagType;
  @override
  final String actorId;
  @override
  final DateTime timestamp;
  @override
  final String? reason;

  @override
  String toString() {
    return 'FlagEvent(eventId: $eventId, targetId: $targetId, targetType: $targetType, flagType: $flagType, actorId: $actorId, timestamp: $timestamp, reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FlagEventImpl &&
            (identical(other.eventId, eventId) || other.eventId == eventId) &&
            (identical(other.targetId, targetId) ||
                other.targetId == targetId) &&
            (identical(other.targetType, targetType) ||
                other.targetType == targetType) &&
            (identical(other.flagType, flagType) ||
                other.flagType == flagType) &&
            (identical(other.actorId, actorId) || other.actorId == actorId) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, eventId, targetId, targetType,
      flagType, actorId, timestamp, reason);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FlagEventImplCopyWith<_$FlagEventImpl> get copyWith =>
      __$$FlagEventImplCopyWithImpl<_$FlagEventImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FlagEventImplToJson(
      this,
    );
  }
}

abstract class _FlagEvent implements FlagEvent {
  const factory _FlagEvent(
      {required final String eventId,
      required final String targetId,
      required final String targetType,
      required final FlagType flagType,
      required final String actorId,
      required final DateTime timestamp,
      final String? reason}) = _$FlagEventImpl;

  factory _FlagEvent.fromJson(Map<String, dynamic> json) =
      _$FlagEventImpl.fromJson;

  @override
  String get eventId;
  @override
  String get targetId;
  @override
  String get targetType;
  @override // 'trip_log' | 'pro_tip'
  FlagType get flagType;
  @override
  String get actorId;
  @override
  DateTime get timestamp;
  @override
  String? get reason;
  @override
  @JsonKey(ignore: true)
  _$$FlagEventImplCopyWith<_$FlagEventImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
