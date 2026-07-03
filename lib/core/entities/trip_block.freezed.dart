// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trip_block.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TripBlock _$TripBlockFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'text':
      return TextBlock.fromJson(json);
    case 'image':
      return ImageBlock.fromJson(json);
    case 'video':
      return VideoBlock.fromJson(json);
    case 'costEntry':
      return CostEntryBlock.fromJson(json);
    case 'route':
      return RouteBlock.fromJson(json);
    case 'safetyNote':
      return SafetyNoteBlock.fromJson(json);
    case 'voiceNote':
      return VoiceNoteBlock.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'TripBlock',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$TripBlock {
  String get id => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TripBlockCopyWith<TripBlock> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TripBlockCopyWith<$Res> {
  factory $TripBlockCopyWith(TripBlock value, $Res Function(TripBlock) then) =
      _$TripBlockCopyWithImpl<$Res, TripBlock>;
  @useResult
  $Res call({String id});
}

/// @nodoc
class _$TripBlockCopyWithImpl<$Res, $Val extends TripBlock>
    implements $TripBlockCopyWith<$Res> {
  _$TripBlockCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TextBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$TextBlockImplCopyWith(
          _$TextBlockImpl value, $Res Function(_$TextBlockImpl) then) =
      __$$TextBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String content, bool isBold});
}

/// @nodoc
class __$$TextBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$TextBlockImpl>
    implements _$$TextBlockImplCopyWith<$Res> {
  __$$TextBlockImplCopyWithImpl(
      _$TextBlockImpl _value, $Res Function(_$TextBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? isBold = null,
  }) {
    return _then(_$TextBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      isBold: null == isBold
          ? _value.isBold
          : isBold // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TextBlockImpl implements TextBlock {
  const _$TextBlockImpl(
      {required this.id,
      required this.content,
      this.isBold = false,
      final String? $type})
      : $type = $type ?? 'text';

  factory _$TextBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$TextBlockImplFromJson(json);

  @override
  final String id;
  @override
  final String content;
  @override
  @JsonKey()
  final bool isBold;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.text(id: $id, content: $content, isBold: $isBold)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TextBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.isBold, isBold) || other.isBold == isBold));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, content, isBold);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TextBlockImplCopyWith<_$TextBlockImpl> get copyWith =>
      __$$TextBlockImplCopyWithImpl<_$TextBlockImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return text(id, content, isBold);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return text?.call(id, content, isBold);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(id, content, isBold);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return text(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return text?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$TextBlockImplToJson(
      this,
    );
  }
}

abstract class TextBlock implements TripBlock {
  const factory TextBlock(
      {required final String id,
      required final String content,
      final bool isBold}) = _$TextBlockImpl;

  factory TextBlock.fromJson(Map<String, dynamic> json) =
      _$TextBlockImpl.fromJson;

  @override
  String get id;
  String get content;
  bool get isBold;
  @override
  @JsonKey(ignore: true)
  _$$TextBlockImplCopyWith<_$TextBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ImageBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$ImageBlockImplCopyWith(
          _$ImageBlockImpl value, $Res Function(_$ImageBlockImpl) then) =
      __$$ImageBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String storageUrl, String caption, String? localPath});
}

/// @nodoc
class __$$ImageBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$ImageBlockImpl>
    implements _$$ImageBlockImplCopyWith<$Res> {
  __$$ImageBlockImplCopyWithImpl(
      _$ImageBlockImpl _value, $Res Function(_$ImageBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? storageUrl = null,
    Object? caption = null,
    Object? localPath = freezed,
  }) {
    return _then(_$ImageBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      storageUrl: null == storageUrl
          ? _value.storageUrl
          : storageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      caption: null == caption
          ? _value.caption
          : caption // ignore: cast_nullable_to_non_nullable
              as String,
      localPath: freezed == localPath
          ? _value.localPath
          : localPath // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ImageBlockImpl implements ImageBlock {
  const _$ImageBlockImpl(
      {required this.id,
      required this.storageUrl,
      required this.caption,
      this.localPath,
      final String? $type})
      : $type = $type ?? 'image';

  factory _$ImageBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$ImageBlockImplFromJson(json);

  @override
  final String id;
  @override
  final String storageUrl;
  @override
  final String caption;
  @override
  final String? localPath;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.image(id: $id, storageUrl: $storageUrl, caption: $caption, localPath: $localPath)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImageBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.storageUrl, storageUrl) ||
                other.storageUrl == storageUrl) &&
            (identical(other.caption, caption) || other.caption == caption) &&
            (identical(other.localPath, localPath) ||
                other.localPath == localPath));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, storageUrl, caption, localPath);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ImageBlockImplCopyWith<_$ImageBlockImpl> get copyWith =>
      __$$ImageBlockImplCopyWithImpl<_$ImageBlockImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return image(id, storageUrl, caption, localPath);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return image?.call(id, storageUrl, caption, localPath);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(id, storageUrl, caption, localPath);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return image(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return image?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ImageBlockImplToJson(
      this,
    );
  }
}

abstract class ImageBlock implements TripBlock {
  const factory ImageBlock(
      {required final String id,
      required final String storageUrl,
      required final String caption,
      final String? localPath}) = _$ImageBlockImpl;

  factory ImageBlock.fromJson(Map<String, dynamic> json) =
      _$ImageBlockImpl.fromJson;

  @override
  String get id;
  String get storageUrl;
  String get caption;
  String? get localPath;
  @override
  @JsonKey(ignore: true)
  _$$ImageBlockImplCopyWith<_$ImageBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VideoBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$VideoBlockImplCopyWith(
          _$VideoBlockImpl value, $Res Function(_$VideoBlockImpl) then) =
      __$$VideoBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String storageUrl, String caption, String? localPath});
}

/// @nodoc
class __$$VideoBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$VideoBlockImpl>
    implements _$$VideoBlockImplCopyWith<$Res> {
  __$$VideoBlockImplCopyWithImpl(
      _$VideoBlockImpl _value, $Res Function(_$VideoBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? storageUrl = null,
    Object? caption = null,
    Object? localPath = freezed,
  }) {
    return _then(_$VideoBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      storageUrl: null == storageUrl
          ? _value.storageUrl
          : storageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      caption: null == caption
          ? _value.caption
          : caption // ignore: cast_nullable_to_non_nullable
              as String,
      localPath: freezed == localPath
          ? _value.localPath
          : localPath // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$VideoBlockImpl implements VideoBlock {
  const _$VideoBlockImpl(
      {required this.id,
      required this.storageUrl,
      required this.caption,
      this.localPath,
      final String? $type})
      : $type = $type ?? 'video';

  factory _$VideoBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$VideoBlockImplFromJson(json);

  @override
  final String id;
  @override
  final String storageUrl;
  @override
  final String caption;
  @override
  final String? localPath;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.video(id: $id, storageUrl: $storageUrl, caption: $caption, localPath: $localPath)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VideoBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.storageUrl, storageUrl) ||
                other.storageUrl == storageUrl) &&
            (identical(other.caption, caption) || other.caption == caption) &&
            (identical(other.localPath, localPath) ||
                other.localPath == localPath));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, storageUrl, caption, localPath);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$VideoBlockImplCopyWith<_$VideoBlockImpl> get copyWith =>
      __$$VideoBlockImplCopyWithImpl<_$VideoBlockImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return video(id, storageUrl, caption, localPath);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return video?.call(id, storageUrl, caption, localPath);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (video != null) {
      return video(id, storageUrl, caption, localPath);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return video(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return video?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (video != null) {
      return video(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$VideoBlockImplToJson(
      this,
    );
  }
}

abstract class VideoBlock implements TripBlock {
  const factory VideoBlock(
      {required final String id,
      required final String storageUrl,
      required final String caption,
      final String? localPath}) = _$VideoBlockImpl;

  factory VideoBlock.fromJson(Map<String, dynamic> json) =
      _$VideoBlockImpl.fromJson;

  @override
  String get id;
  String get storageUrl;
  String get caption;
  String? get localPath;
  @override
  @JsonKey(ignore: true)
  _$$VideoBlockImplCopyWith<_$VideoBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$CostEntryBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$CostEntryBlockImplCopyWith(_$CostEntryBlockImpl value,
          $Res Function(_$CostEntryBlockImpl) then) =
      __$$CostEntryBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, List<CostItem> items, String currency});
}

/// @nodoc
class __$$CostEntryBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$CostEntryBlockImpl>
    implements _$$CostEntryBlockImplCopyWith<$Res> {
  __$$CostEntryBlockImplCopyWithImpl(
      _$CostEntryBlockImpl _value, $Res Function(_$CostEntryBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? items = null,
    Object? currency = null,
  }) {
    return _then(_$CostEntryBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<CostItem>,
      currency: null == currency
          ? _value.currency
          : currency // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CostEntryBlockImpl implements CostEntryBlock {
  const _$CostEntryBlockImpl(
      {required this.id,
      required final List<CostItem> items,
      required this.currency,
      final String? $type})
      : _items = items,
        $type = $type ?? 'costEntry';

  factory _$CostEntryBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$CostEntryBlockImplFromJson(json);

  @override
  final String id;
  final List<CostItem> _items;
  @override
  List<CostItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final String currency;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.costEntry(id: $id, items: $items, currency: $currency)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CostEntryBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.currency, currency) ||
                other.currency == currency));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, const DeepCollectionEquality().hash(_items), currency);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CostEntryBlockImplCopyWith<_$CostEntryBlockImpl> get copyWith =>
      __$$CostEntryBlockImplCopyWithImpl<_$CostEntryBlockImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return costEntry(id, items, currency);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return costEntry?.call(id, items, currency);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (costEntry != null) {
      return costEntry(id, items, currency);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return costEntry(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return costEntry?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (costEntry != null) {
      return costEntry(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$CostEntryBlockImplToJson(
      this,
    );
  }
}

abstract class CostEntryBlock implements TripBlock {
  const factory CostEntryBlock(
      {required final String id,
      required final List<CostItem> items,
      required final String currency}) = _$CostEntryBlockImpl;

  factory CostEntryBlock.fromJson(Map<String, dynamic> json) =
      _$CostEntryBlockImpl.fromJson;

  @override
  String get id;
  List<CostItem> get items;
  String get currency;
  @override
  @JsonKey(ignore: true)
  _$$CostEntryBlockImplCopyWith<_$CostEntryBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$RouteBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$RouteBlockImplCopyWith(
          _$RouteBlockImpl value, $Res Function(_$RouteBlockImpl) then) =
      __$$RouteBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, List<GeoCoordinate> points, String? description});
}

/// @nodoc
class __$$RouteBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$RouteBlockImpl>
    implements _$$RouteBlockImplCopyWith<$Res> {
  __$$RouteBlockImplCopyWithImpl(
      _$RouteBlockImpl _value, $Res Function(_$RouteBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? points = null,
    Object? description = freezed,
  }) {
    return _then(_$RouteBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      points: null == points
          ? _value._points
          : points // ignore: cast_nullable_to_non_nullable
              as List<GeoCoordinate>,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RouteBlockImpl implements RouteBlock {
  const _$RouteBlockImpl(
      {required this.id,
      required final List<GeoCoordinate> points,
      this.description,
      final String? $type})
      : _points = points,
        $type = $type ?? 'route';

  factory _$RouteBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$RouteBlockImplFromJson(json);

  @override
  final String id;
  final List<GeoCoordinate> _points;
  @override
  List<GeoCoordinate> get points {
    if (_points is EqualUnmodifiableListView) return _points;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_points);
  }

  @override
  final String? description;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.route(id: $id, points: $points, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RouteBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            const DeepCollectionEquality().equals(other._points, _points) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id,
      const DeepCollectionEquality().hash(_points), description);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$RouteBlockImplCopyWith<_$RouteBlockImpl> get copyWith =>
      __$$RouteBlockImplCopyWithImpl<_$RouteBlockImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return route(id, points, description);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return route?.call(id, points, description);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (route != null) {
      return route(id, points, description);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return route(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return route?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (route != null) {
      return route(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$RouteBlockImplToJson(
      this,
    );
  }
}

abstract class RouteBlock implements TripBlock {
  const factory RouteBlock(
      {required final String id,
      required final List<GeoCoordinate> points,
      final String? description}) = _$RouteBlockImpl;

  factory RouteBlock.fromJson(Map<String, dynamic> json) =
      _$RouteBlockImpl.fromJson;

  @override
  String get id;
  List<GeoCoordinate> get points;
  String? get description;
  @override
  @JsonKey(ignore: true)
  _$$RouteBlockImplCopyWith<_$RouteBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SafetyNoteBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$SafetyNoteBlockImplCopyWith(_$SafetyNoteBlockImpl value,
          $Res Function(_$SafetyNoteBlockImpl) then) =
      __$$SafetyNoteBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String text, String level});
}

/// @nodoc
class __$$SafetyNoteBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$SafetyNoteBlockImpl>
    implements _$$SafetyNoteBlockImplCopyWith<$Res> {
  __$$SafetyNoteBlockImplCopyWithImpl(
      _$SafetyNoteBlockImpl _value, $Res Function(_$SafetyNoteBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? level = null,
  }) {
    return _then(_$SafetyNoteBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SafetyNoteBlockImpl implements SafetyNoteBlock {
  const _$SafetyNoteBlockImpl(
      {required this.id,
      required this.text,
      required this.level,
      final String? $type})
      : $type = $type ?? 'safetyNote';

  factory _$SafetyNoteBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$SafetyNoteBlockImplFromJson(json);

  @override
  final String id;
  @override
  final String text;
  @override
  final String level;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.safetyNote(id: $id, text: $text, level: $level)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SafetyNoteBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.level, level) || other.level == level));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, text, level);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SafetyNoteBlockImplCopyWith<_$SafetyNoteBlockImpl> get copyWith =>
      __$$SafetyNoteBlockImplCopyWithImpl<_$SafetyNoteBlockImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return safetyNote(id, this.text, level);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return safetyNote?.call(id, this.text, level);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (safetyNote != null) {
      return safetyNote(id, this.text, level);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return safetyNote(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return safetyNote?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (safetyNote != null) {
      return safetyNote(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$SafetyNoteBlockImplToJson(
      this,
    );
  }
}

abstract class SafetyNoteBlock implements TripBlock {
  const factory SafetyNoteBlock(
      {required final String id,
      required final String text,
      required final String level}) = _$SafetyNoteBlockImpl;

  factory SafetyNoteBlock.fromJson(Map<String, dynamic> json) =
      _$SafetyNoteBlockImpl.fromJson;

  @override
  String get id;
  String get text;
  String get level;
  @override
  @JsonKey(ignore: true)
  _$$SafetyNoteBlockImplCopyWith<_$SafetyNoteBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$VoiceNoteBlockImplCopyWith<$Res>
    implements $TripBlockCopyWith<$Res> {
  factory _$$VoiceNoteBlockImplCopyWith(_$VoiceNoteBlockImpl value,
          $Res Function(_$VoiceNoteBlockImpl) then) =
      __$$VoiceNoteBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String storageUrl,
      int durationSeconds,
      String? localPath,
      String? transcript});
}

/// @nodoc
class __$$VoiceNoteBlockImplCopyWithImpl<$Res>
    extends _$TripBlockCopyWithImpl<$Res, _$VoiceNoteBlockImpl>
    implements _$$VoiceNoteBlockImplCopyWith<$Res> {
  __$$VoiceNoteBlockImplCopyWithImpl(
      _$VoiceNoteBlockImpl _value, $Res Function(_$VoiceNoteBlockImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? storageUrl = null,
    Object? durationSeconds = null,
    Object? localPath = freezed,
    Object? transcript = freezed,
  }) {
    return _then(_$VoiceNoteBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      storageUrl: null == storageUrl
          ? _value.storageUrl
          : storageUrl // ignore: cast_nullable_to_non_nullable
              as String,
      durationSeconds: null == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      localPath: freezed == localPath
          ? _value.localPath
          : localPath // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: freezed == transcript
          ? _value.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$VoiceNoteBlockImpl implements VoiceNoteBlock {
  const _$VoiceNoteBlockImpl(
      {required this.id,
      this.storageUrl = '',
      required this.durationSeconds,
      this.localPath,
      this.transcript,
      final String? $type})
      : $type = $type ?? 'voiceNote';

  factory _$VoiceNoteBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$VoiceNoteBlockImplFromJson(json);

  @override
  final String id;

  /// Firebase Storage URL (empty string when only stored locally)
  @override
  @JsonKey()
  final String storageUrl;

  /// Duration in seconds
  @override
  final int durationSeconds;

  /// Local file path (non-null when recorded offline)
  @override
  final String? localPath;

  /// Optional auto-transcription text
  @override
  final String? transcript;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'TripBlock.voiceNote(id: $id, storageUrl: $storageUrl, durationSeconds: $durationSeconds, localPath: $localPath, transcript: $transcript)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VoiceNoteBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.storageUrl, storageUrl) ||
                other.storageUrl == storageUrl) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.localPath, localPath) ||
                other.localPath == localPath) &&
            (identical(other.transcript, transcript) ||
                other.transcript == transcript));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, storageUrl, durationSeconds, localPath, transcript);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$VoiceNoteBlockImplCopyWith<_$VoiceNoteBlockImpl> get copyWith =>
      __$$VoiceNoteBlockImplCopyWithImpl<_$VoiceNoteBlockImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String content, bool isBold) text,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        image,
    required TResult Function(
            String id, String storageUrl, String caption, String? localPath)
        video,
    required TResult Function(String id, List<CostItem> items, String currency)
        costEntry,
    required TResult Function(
            String id, List<GeoCoordinate> points, String? description)
        route,
    required TResult Function(String id, String text, String level) safetyNote,
    required TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)
        voiceNote,
  }) {
    return voiceNote(id, storageUrl, durationSeconds, localPath, transcript);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String content, bool isBold)? text,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult? Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult? Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult? Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult? Function(String id, String text, String level)? safetyNote,
    TResult? Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
  }) {
    return voiceNote?.call(
        id, storageUrl, durationSeconds, localPath, transcript);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String content, bool isBold)? text,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        image,
    TResult Function(
            String id, String storageUrl, String caption, String? localPath)?
        video,
    TResult Function(String id, List<CostItem> items, String currency)?
        costEntry,
    TResult Function(
            String id, List<GeoCoordinate> points, String? description)?
        route,
    TResult Function(String id, String text, String level)? safetyNote,
    TResult Function(String id, String storageUrl, int durationSeconds,
            String? localPath, String? transcript)?
        voiceNote,
    required TResult orElse(),
  }) {
    if (voiceNote != null) {
      return voiceNote(id, storageUrl, durationSeconds, localPath, transcript);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextBlock value) text,
    required TResult Function(ImageBlock value) image,
    required TResult Function(VideoBlock value) video,
    required TResult Function(CostEntryBlock value) costEntry,
    required TResult Function(RouteBlock value) route,
    required TResult Function(SafetyNoteBlock value) safetyNote,
    required TResult Function(VoiceNoteBlock value) voiceNote,
  }) {
    return voiceNote(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextBlock value)? text,
    TResult? Function(ImageBlock value)? image,
    TResult? Function(VideoBlock value)? video,
    TResult? Function(CostEntryBlock value)? costEntry,
    TResult? Function(RouteBlock value)? route,
    TResult? Function(SafetyNoteBlock value)? safetyNote,
    TResult? Function(VoiceNoteBlock value)? voiceNote,
  }) {
    return voiceNote?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextBlock value)? text,
    TResult Function(ImageBlock value)? image,
    TResult Function(VideoBlock value)? video,
    TResult Function(CostEntryBlock value)? costEntry,
    TResult Function(RouteBlock value)? route,
    TResult Function(SafetyNoteBlock value)? safetyNote,
    TResult Function(VoiceNoteBlock value)? voiceNote,
    required TResult orElse(),
  }) {
    if (voiceNote != null) {
      return voiceNote(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$VoiceNoteBlockImplToJson(
      this,
    );
  }
}

abstract class VoiceNoteBlock implements TripBlock {
  const factory VoiceNoteBlock(
      {required final String id,
      final String storageUrl,
      required final int durationSeconds,
      final String? localPath,
      final String? transcript}) = _$VoiceNoteBlockImpl;

  factory VoiceNoteBlock.fromJson(Map<String, dynamic> json) =
      _$VoiceNoteBlockImpl.fromJson;

  @override
  String get id;

  /// Firebase Storage URL (empty string when only stored locally)
  String get storageUrl;

  /// Duration in seconds
  int get durationSeconds;

  /// Local file path (non-null when recorded offline)
  String? get localPath;

  /// Optional auto-transcription text
  String? get transcript;
  @override
  @JsonKey(ignore: true)
  _$$VoiceNoteBlockImplCopyWith<_$VoiceNoteBlockImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
