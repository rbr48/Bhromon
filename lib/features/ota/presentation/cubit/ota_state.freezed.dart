// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ota_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$OtaState {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() checking,
    required TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)
        updateAvailable,
    required TResult Function() upToDate,
    required TResult Function(String message) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? checking,
    TResult? Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult? Function()? upToDate,
    TResult? Function(String message)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? checking,
    TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult Function()? upToDate,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OtaInitial value) initial,
    required TResult Function(OtaChecking value) checking,
    required TResult Function(OtaUpdateAvailable value) updateAvailable,
    required TResult Function(OtaUpToDate value) upToDate,
    required TResult Function(OtaError value) error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OtaInitial value)? initial,
    TResult? Function(OtaChecking value)? checking,
    TResult? Function(OtaUpdateAvailable value)? updateAvailable,
    TResult? Function(OtaUpToDate value)? upToDate,
    TResult? Function(OtaError value)? error,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OtaInitial value)? initial,
    TResult Function(OtaChecking value)? checking,
    TResult Function(OtaUpdateAvailable value)? updateAvailable,
    TResult Function(OtaUpToDate value)? upToDate,
    TResult Function(OtaError value)? error,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OtaStateCopyWith<$Res> {
  factory $OtaStateCopyWith(OtaState value, $Res Function(OtaState) then) =
      _$OtaStateCopyWithImpl<$Res, OtaState>;
}

/// @nodoc
class _$OtaStateCopyWithImpl<$Res, $Val extends OtaState>
    implements $OtaStateCopyWith<$Res> {
  _$OtaStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$OtaInitialImplCopyWith<$Res> {
  factory _$$OtaInitialImplCopyWith(
          _$OtaInitialImpl value, $Res Function(_$OtaInitialImpl) then) =
      __$$OtaInitialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$OtaInitialImplCopyWithImpl<$Res>
    extends _$OtaStateCopyWithImpl<$Res, _$OtaInitialImpl>
    implements _$$OtaInitialImplCopyWith<$Res> {
  __$$OtaInitialImplCopyWithImpl(
      _$OtaInitialImpl _value, $Res Function(_$OtaInitialImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$OtaInitialImpl implements OtaInitial {
  const _$OtaInitialImpl();

  @override
  String toString() {
    return 'OtaState.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$OtaInitialImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() checking,
    required TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)
        updateAvailable,
    required TResult Function() upToDate,
    required TResult Function(String message) error,
  }) {
    return initial();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? checking,
    TResult? Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult? Function()? upToDate,
    TResult? Function(String message)? error,
  }) {
    return initial?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? checking,
    TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult Function()? upToDate,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OtaInitial value) initial,
    required TResult Function(OtaChecking value) checking,
    required TResult Function(OtaUpdateAvailable value) updateAvailable,
    required TResult Function(OtaUpToDate value) upToDate,
    required TResult Function(OtaError value) error,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OtaInitial value)? initial,
    TResult? Function(OtaChecking value)? checking,
    TResult? Function(OtaUpdateAvailable value)? updateAvailable,
    TResult? Function(OtaUpToDate value)? upToDate,
    TResult? Function(OtaError value)? error,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OtaInitial value)? initial,
    TResult Function(OtaChecking value)? checking,
    TResult Function(OtaUpdateAvailable value)? updateAvailable,
    TResult Function(OtaUpToDate value)? upToDate,
    TResult Function(OtaError value)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class OtaInitial implements OtaState {
  const factory OtaInitial() = _$OtaInitialImpl;
}

/// @nodoc
abstract class _$$OtaCheckingImplCopyWith<$Res> {
  factory _$$OtaCheckingImplCopyWith(
          _$OtaCheckingImpl value, $Res Function(_$OtaCheckingImpl) then) =
      __$$OtaCheckingImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$OtaCheckingImplCopyWithImpl<$Res>
    extends _$OtaStateCopyWithImpl<$Res, _$OtaCheckingImpl>
    implements _$$OtaCheckingImplCopyWith<$Res> {
  __$$OtaCheckingImplCopyWithImpl(
      _$OtaCheckingImpl _value, $Res Function(_$OtaCheckingImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$OtaCheckingImpl implements OtaChecking {
  const _$OtaCheckingImpl();

  @override
  String toString() {
    return 'OtaState.checking()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$OtaCheckingImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() checking,
    required TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)
        updateAvailable,
    required TResult Function() upToDate,
    required TResult Function(String message) error,
  }) {
    return checking();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? checking,
    TResult? Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult? Function()? upToDate,
    TResult? Function(String message)? error,
  }) {
    return checking?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? checking,
    TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult Function()? upToDate,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (checking != null) {
      return checking();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OtaInitial value) initial,
    required TResult Function(OtaChecking value) checking,
    required TResult Function(OtaUpdateAvailable value) updateAvailable,
    required TResult Function(OtaUpToDate value) upToDate,
    required TResult Function(OtaError value) error,
  }) {
    return checking(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OtaInitial value)? initial,
    TResult? Function(OtaChecking value)? checking,
    TResult? Function(OtaUpdateAvailable value)? updateAvailable,
    TResult? Function(OtaUpToDate value)? upToDate,
    TResult? Function(OtaError value)? error,
  }) {
    return checking?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OtaInitial value)? initial,
    TResult Function(OtaChecking value)? checking,
    TResult Function(OtaUpdateAvailable value)? updateAvailable,
    TResult Function(OtaUpToDate value)? upToDate,
    TResult Function(OtaError value)? error,
    required TResult orElse(),
  }) {
    if (checking != null) {
      return checking(this);
    }
    return orElse();
  }
}

abstract class OtaChecking implements OtaState {
  const factory OtaChecking() = _$OtaCheckingImpl;
}

/// @nodoc
abstract class _$$OtaUpdateAvailableImplCopyWith<$Res> {
  factory _$$OtaUpdateAvailableImplCopyWith(_$OtaUpdateAvailableImpl value,
          $Res Function(_$OtaUpdateAvailableImpl) then) =
      __$$OtaUpdateAvailableImplCopyWithImpl<$Res>;
  @useResult
  $Res call({AppVersionInfo info, double downloadProgress, bool isDownloading});
}

/// @nodoc
class __$$OtaUpdateAvailableImplCopyWithImpl<$Res>
    extends _$OtaStateCopyWithImpl<$Res, _$OtaUpdateAvailableImpl>
    implements _$$OtaUpdateAvailableImplCopyWith<$Res> {
  __$$OtaUpdateAvailableImplCopyWithImpl(_$OtaUpdateAvailableImpl _value,
      $Res Function(_$OtaUpdateAvailableImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? info = null,
    Object? downloadProgress = null,
    Object? isDownloading = null,
  }) {
    return _then(_$OtaUpdateAvailableImpl(
      info: null == info
          ? _value.info
          : info // ignore: cast_nullable_to_non_nullable
              as AppVersionInfo,
      downloadProgress: null == downloadProgress
          ? _value.downloadProgress
          : downloadProgress // ignore: cast_nullable_to_non_nullable
              as double,
      isDownloading: null == isDownloading
          ? _value.isDownloading
          : isDownloading // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$OtaUpdateAvailableImpl implements OtaUpdateAvailable {
  const _$OtaUpdateAvailableImpl(
      {required this.info,
      this.downloadProgress = 0.0,
      this.isDownloading = false});

  @override
  final AppVersionInfo info;
  @override
  @JsonKey()
  final double downloadProgress;
  @override
  @JsonKey()
  final bool isDownloading;

  @override
  String toString() {
    return 'OtaState.updateAvailable(info: $info, downloadProgress: $downloadProgress, isDownloading: $isDownloading)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OtaUpdateAvailableImpl &&
            (identical(other.info, info) || other.info == info) &&
            (identical(other.downloadProgress, downloadProgress) ||
                other.downloadProgress == downloadProgress) &&
            (identical(other.isDownloading, isDownloading) ||
                other.isDownloading == isDownloading));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, info, downloadProgress, isDownloading);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OtaUpdateAvailableImplCopyWith<_$OtaUpdateAvailableImpl> get copyWith =>
      __$$OtaUpdateAvailableImplCopyWithImpl<_$OtaUpdateAvailableImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() checking,
    required TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)
        updateAvailable,
    required TResult Function() upToDate,
    required TResult Function(String message) error,
  }) {
    return updateAvailable(info, downloadProgress, isDownloading);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? checking,
    TResult? Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult? Function()? upToDate,
    TResult? Function(String message)? error,
  }) {
    return updateAvailable?.call(info, downloadProgress, isDownloading);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? checking,
    TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult Function()? upToDate,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (updateAvailable != null) {
      return updateAvailable(info, downloadProgress, isDownloading);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OtaInitial value) initial,
    required TResult Function(OtaChecking value) checking,
    required TResult Function(OtaUpdateAvailable value) updateAvailable,
    required TResult Function(OtaUpToDate value) upToDate,
    required TResult Function(OtaError value) error,
  }) {
    return updateAvailable(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OtaInitial value)? initial,
    TResult? Function(OtaChecking value)? checking,
    TResult? Function(OtaUpdateAvailable value)? updateAvailable,
    TResult? Function(OtaUpToDate value)? upToDate,
    TResult? Function(OtaError value)? error,
  }) {
    return updateAvailable?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OtaInitial value)? initial,
    TResult Function(OtaChecking value)? checking,
    TResult Function(OtaUpdateAvailable value)? updateAvailable,
    TResult Function(OtaUpToDate value)? upToDate,
    TResult Function(OtaError value)? error,
    required TResult orElse(),
  }) {
    if (updateAvailable != null) {
      return updateAvailable(this);
    }
    return orElse();
  }
}

abstract class OtaUpdateAvailable implements OtaState {
  const factory OtaUpdateAvailable(
      {required final AppVersionInfo info,
      final double downloadProgress,
      final bool isDownloading}) = _$OtaUpdateAvailableImpl;

  AppVersionInfo get info;
  double get downloadProgress;
  bool get isDownloading;
  @JsonKey(ignore: true)
  _$$OtaUpdateAvailableImplCopyWith<_$OtaUpdateAvailableImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$OtaUpToDateImplCopyWith<$Res> {
  factory _$$OtaUpToDateImplCopyWith(
          _$OtaUpToDateImpl value, $Res Function(_$OtaUpToDateImpl) then) =
      __$$OtaUpToDateImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$OtaUpToDateImplCopyWithImpl<$Res>
    extends _$OtaStateCopyWithImpl<$Res, _$OtaUpToDateImpl>
    implements _$$OtaUpToDateImplCopyWith<$Res> {
  __$$OtaUpToDateImplCopyWithImpl(
      _$OtaUpToDateImpl _value, $Res Function(_$OtaUpToDateImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$OtaUpToDateImpl implements OtaUpToDate {
  const _$OtaUpToDateImpl();

  @override
  String toString() {
    return 'OtaState.upToDate()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$OtaUpToDateImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() checking,
    required TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)
        updateAvailable,
    required TResult Function() upToDate,
    required TResult Function(String message) error,
  }) {
    return upToDate();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? checking,
    TResult? Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult? Function()? upToDate,
    TResult? Function(String message)? error,
  }) {
    return upToDate?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? checking,
    TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult Function()? upToDate,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (upToDate != null) {
      return upToDate();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OtaInitial value) initial,
    required TResult Function(OtaChecking value) checking,
    required TResult Function(OtaUpdateAvailable value) updateAvailable,
    required TResult Function(OtaUpToDate value) upToDate,
    required TResult Function(OtaError value) error,
  }) {
    return upToDate(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OtaInitial value)? initial,
    TResult? Function(OtaChecking value)? checking,
    TResult? Function(OtaUpdateAvailable value)? updateAvailable,
    TResult? Function(OtaUpToDate value)? upToDate,
    TResult? Function(OtaError value)? error,
  }) {
    return upToDate?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OtaInitial value)? initial,
    TResult Function(OtaChecking value)? checking,
    TResult Function(OtaUpdateAvailable value)? updateAvailable,
    TResult Function(OtaUpToDate value)? upToDate,
    TResult Function(OtaError value)? error,
    required TResult orElse(),
  }) {
    if (upToDate != null) {
      return upToDate(this);
    }
    return orElse();
  }
}

abstract class OtaUpToDate implements OtaState {
  const factory OtaUpToDate() = _$OtaUpToDateImpl;
}

/// @nodoc
abstract class _$$OtaErrorImplCopyWith<$Res> {
  factory _$$OtaErrorImplCopyWith(
          _$OtaErrorImpl value, $Res Function(_$OtaErrorImpl) then) =
      __$$OtaErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$OtaErrorImplCopyWithImpl<$Res>
    extends _$OtaStateCopyWithImpl<$Res, _$OtaErrorImpl>
    implements _$$OtaErrorImplCopyWith<$Res> {
  __$$OtaErrorImplCopyWithImpl(
      _$OtaErrorImpl _value, $Res Function(_$OtaErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$OtaErrorImpl(
      null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$OtaErrorImpl implements OtaError {
  const _$OtaErrorImpl(this.message);

  @override
  final String message;

  @override
  String toString() {
    return 'OtaState.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OtaErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OtaErrorImplCopyWith<_$OtaErrorImpl> get copyWith =>
      __$$OtaErrorImplCopyWithImpl<_$OtaErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() checking,
    required TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)
        updateAvailable,
    required TResult Function() upToDate,
    required TResult Function(String message) error,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? checking,
    TResult? Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult? Function()? upToDate,
    TResult? Function(String message)? error,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? checking,
    TResult Function(
            AppVersionInfo info, double downloadProgress, bool isDownloading)?
        updateAvailable,
    TResult Function()? upToDate,
    TResult Function(String message)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(OtaInitial value) initial,
    required TResult Function(OtaChecking value) checking,
    required TResult Function(OtaUpdateAvailable value) updateAvailable,
    required TResult Function(OtaUpToDate value) upToDate,
    required TResult Function(OtaError value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(OtaInitial value)? initial,
    TResult? Function(OtaChecking value)? checking,
    TResult? Function(OtaUpdateAvailable value)? updateAvailable,
    TResult? Function(OtaUpToDate value)? upToDate,
    TResult? Function(OtaError value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(OtaInitial value)? initial,
    TResult Function(OtaChecking value)? checking,
    TResult Function(OtaUpdateAvailable value)? updateAvailable,
    TResult Function(OtaUpToDate value)? upToDate,
    TResult Function(OtaError value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class OtaError implements OtaState {
  const factory OtaError(final String message) = _$OtaErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$OtaErrorImplCopyWith<_$OtaErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
