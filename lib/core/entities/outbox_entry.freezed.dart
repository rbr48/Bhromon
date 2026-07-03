// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'outbox_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

OutboxEntry _$OutboxEntryFromJson(Map<String, dynamic> json) {
  return _OutboxEntry.fromJson(json);
}

/// @nodoc
mixin _$OutboxEntry {
  String get id => throw _privateConstructorUsedError;
  String get operation => throw _privateConstructorUsedError;
  String get collectionPath => throw _privateConstructorUsedError;
  String get documentId => throw _privateConstructorUsedError;
  Map<String, dynamic> get payload => throw _privateConstructorUsedError;
  DateTime get enqueuedAt => throw _privateConstructorUsedError;
  int get retryCount => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  Map<String, dynamic>? get serverConflictPayload =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OutboxEntryCopyWith<OutboxEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OutboxEntryCopyWith<$Res> {
  factory $OutboxEntryCopyWith(
          OutboxEntry value, $Res Function(OutboxEntry) then) =
      _$OutboxEntryCopyWithImpl<$Res, OutboxEntry>;
  @useResult
  $Res call(
      {String id,
      String operation,
      String collectionPath,
      String documentId,
      Map<String, dynamic> payload,
      DateTime enqueuedAt,
      int retryCount,
      String status,
      Map<String, dynamic>? serverConflictPayload});
}

/// @nodoc
class _$OutboxEntryCopyWithImpl<$Res, $Val extends OutboxEntry>
    implements $OutboxEntryCopyWith<$Res> {
  _$OutboxEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? operation = null,
    Object? collectionPath = null,
    Object? documentId = null,
    Object? payload = null,
    Object? enqueuedAt = null,
    Object? retryCount = null,
    Object? status = null,
    Object? serverConflictPayload = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      collectionPath: null == collectionPath
          ? _value.collectionPath
          : collectionPath // ignore: cast_nullable_to_non_nullable
              as String,
      documentId: null == documentId
          ? _value.documentId
          : documentId // ignore: cast_nullable_to_non_nullable
              as String,
      payload: null == payload
          ? _value.payload
          : payload // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      enqueuedAt: null == enqueuedAt
          ? _value.enqueuedAt
          : enqueuedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      serverConflictPayload: freezed == serverConflictPayload
          ? _value.serverConflictPayload
          : serverConflictPayload // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OutboxEntryImplCopyWith<$Res>
    implements $OutboxEntryCopyWith<$Res> {
  factory _$$OutboxEntryImplCopyWith(
          _$OutboxEntryImpl value, $Res Function(_$OutboxEntryImpl) then) =
      __$$OutboxEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String operation,
      String collectionPath,
      String documentId,
      Map<String, dynamic> payload,
      DateTime enqueuedAt,
      int retryCount,
      String status,
      Map<String, dynamic>? serverConflictPayload});
}

/// @nodoc
class __$$OutboxEntryImplCopyWithImpl<$Res>
    extends _$OutboxEntryCopyWithImpl<$Res, _$OutboxEntryImpl>
    implements _$$OutboxEntryImplCopyWith<$Res> {
  __$$OutboxEntryImplCopyWithImpl(
      _$OutboxEntryImpl _value, $Res Function(_$OutboxEntryImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? operation = null,
    Object? collectionPath = null,
    Object? documentId = null,
    Object? payload = null,
    Object? enqueuedAt = null,
    Object? retryCount = null,
    Object? status = null,
    Object? serverConflictPayload = freezed,
  }) {
    return _then(_$OutboxEntryImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      operation: null == operation
          ? _value.operation
          : operation // ignore: cast_nullable_to_non_nullable
              as String,
      collectionPath: null == collectionPath
          ? _value.collectionPath
          : collectionPath // ignore: cast_nullable_to_non_nullable
              as String,
      documentId: null == documentId
          ? _value.documentId
          : documentId // ignore: cast_nullable_to_non_nullable
              as String,
      payload: null == payload
          ? _value._payload
          : payload // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      enqueuedAt: null == enqueuedAt
          ? _value.enqueuedAt
          : enqueuedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      serverConflictPayload: freezed == serverConflictPayload
          ? _value._serverConflictPayload
          : serverConflictPayload // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OutboxEntryImpl implements _OutboxEntry {
  const _$OutboxEntryImpl(
      {required this.id,
      required this.operation,
      required this.collectionPath,
      required this.documentId,
      required final Map<String, dynamic> payload,
      required this.enqueuedAt,
      required this.retryCount,
      required this.status,
      final Map<String, dynamic>? serverConflictPayload})
      : _payload = payload,
        _serverConflictPayload = serverConflictPayload;

  factory _$OutboxEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$OutboxEntryImplFromJson(json);

  @override
  final String id;
  @override
  final String operation;
  @override
  final String collectionPath;
  @override
  final String documentId;
  final Map<String, dynamic> _payload;
  @override
  Map<String, dynamic> get payload {
    if (_payload is EqualUnmodifiableMapView) return _payload;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_payload);
  }

  @override
  final DateTime enqueuedAt;
  @override
  final int retryCount;
  @override
  final String status;
  final Map<String, dynamic>? _serverConflictPayload;
  @override
  Map<String, dynamic>? get serverConflictPayload {
    final value = _serverConflictPayload;
    if (value == null) return null;
    if (_serverConflictPayload is EqualUnmodifiableMapView)
      return _serverConflictPayload;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'OutboxEntry(id: $id, operation: $operation, collectionPath: $collectionPath, documentId: $documentId, payload: $payload, enqueuedAt: $enqueuedAt, retryCount: $retryCount, status: $status, serverConflictPayload: $serverConflictPayload)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OutboxEntryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.operation, operation) ||
                other.operation == operation) &&
            (identical(other.collectionPath, collectionPath) ||
                other.collectionPath == collectionPath) &&
            (identical(other.documentId, documentId) ||
                other.documentId == documentId) &&
            const DeepCollectionEquality().equals(other._payload, _payload) &&
            (identical(other.enqueuedAt, enqueuedAt) ||
                other.enqueuedAt == enqueuedAt) &&
            (identical(other.retryCount, retryCount) ||
                other.retryCount == retryCount) &&
            (identical(other.status, status) || other.status == status) &&
            const DeepCollectionEquality()
                .equals(other._serverConflictPayload, _serverConflictPayload));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      operation,
      collectionPath,
      documentId,
      const DeepCollectionEquality().hash(_payload),
      enqueuedAt,
      retryCount,
      status,
      const DeepCollectionEquality().hash(_serverConflictPayload));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OutboxEntryImplCopyWith<_$OutboxEntryImpl> get copyWith =>
      __$$OutboxEntryImplCopyWithImpl<_$OutboxEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OutboxEntryImplToJson(
      this,
    );
  }
}

abstract class _OutboxEntry implements OutboxEntry {
  const factory _OutboxEntry(
      {required final String id,
      required final String operation,
      required final String collectionPath,
      required final String documentId,
      required final Map<String, dynamic> payload,
      required final DateTime enqueuedAt,
      required final int retryCount,
      required final String status,
      final Map<String, dynamic>? serverConflictPayload}) = _$OutboxEntryImpl;

  factory _OutboxEntry.fromJson(Map<String, dynamic> json) =
      _$OutboxEntryImpl.fromJson;

  @override
  String get id;
  @override
  String get operation;
  @override
  String get collectionPath;
  @override
  String get documentId;
  @override
  Map<String, dynamic> get payload;
  @override
  DateTime get enqueuedAt;
  @override
  int get retryCount;
  @override
  String get status;
  @override
  Map<String, dynamic>? get serverConflictPayload;
  @override
  @JsonKey(ignore: true)
  _$$OutboxEntryImplCopyWith<_$OutboxEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
