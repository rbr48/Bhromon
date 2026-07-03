// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_block.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$TextBlockImpl _$$TextBlockImplFromJson(Map json) => _$TextBlockImpl(
      id: json['id'] as String,
      content: json['content'] as String,
      isBold: json['isBold'] as bool? ?? false,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$TextBlockImplToJson(_$TextBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'content': instance.content,
      'isBold': instance.isBold,
      'runtimeType': instance.$type,
    };

_$ImageBlockImpl _$$ImageBlockImplFromJson(Map json) => _$ImageBlockImpl(
      id: json['id'] as String,
      storageUrl: json['storageUrl'] as String,
      caption: json['caption'] as String,
      localPath: json['localPath'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ImageBlockImplToJson(_$ImageBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'storageUrl': instance.storageUrl,
      'caption': instance.caption,
      'localPath': instance.localPath,
      'runtimeType': instance.$type,
    };

_$VideoBlockImpl _$$VideoBlockImplFromJson(Map json) => _$VideoBlockImpl(
      id: json['id'] as String,
      storageUrl: json['storageUrl'] as String,
      caption: json['caption'] as String,
      localPath: json['localPath'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$VideoBlockImplToJson(_$VideoBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'storageUrl': instance.storageUrl,
      'caption': instance.caption,
      'localPath': instance.localPath,
      'runtimeType': instance.$type,
    };

_$CostEntryBlockImpl _$$CostEntryBlockImplFromJson(Map json) =>
    _$CostEntryBlockImpl(
      id: json['id'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => CostItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      currency: json['currency'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$CostEntryBlockImplToJson(
        _$CostEntryBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'items': instance.items.map((e) => e.toJson()).toList(),
      'currency': instance.currency,
      'runtimeType': instance.$type,
    };

_$RouteBlockImpl _$$RouteBlockImplFromJson(Map json) => _$RouteBlockImpl(
      id: json['id'] as String,
      points: (json['points'] as List<dynamic>)
          .map((e) =>
              GeoCoordinate.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      description: json['description'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$RouteBlockImplToJson(_$RouteBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'points': instance.points.map((e) => e.toJson()).toList(),
      'description': instance.description,
      'runtimeType': instance.$type,
    };

_$SafetyNoteBlockImpl _$$SafetyNoteBlockImplFromJson(Map json) =>
    _$SafetyNoteBlockImpl(
      id: json['id'] as String,
      text: json['text'] as String,
      level: json['level'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$SafetyNoteBlockImplToJson(
        _$SafetyNoteBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'level': instance.level,
      'runtimeType': instance.$type,
    };

_$VoiceNoteBlockImpl _$$VoiceNoteBlockImplFromJson(Map json) =>
    _$VoiceNoteBlockImpl(
      id: json['id'] as String,
      storageUrl: json['storageUrl'] as String? ?? '',
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      localPath: json['localPath'] as String?,
      transcript: json['transcript'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$VoiceNoteBlockImplToJson(
        _$VoiceNoteBlockImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'storageUrl': instance.storageUrl,
      'durationSeconds': instance.durationSeconds,
      'localPath': instance.localPath,
      'transcript': instance.transcript,
      'runtimeType': instance.$type,
    };
