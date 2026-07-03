// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OutboxEntryImpl _$$OutboxEntryImplFromJson(Map json) => _$OutboxEntryImpl(
      id: json['id'] as String,
      operation: json['operation'] as String,
      collectionPath: json['collectionPath'] as String,
      documentId: json['documentId'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      enqueuedAt: DateTime.parse(json['enqueuedAt'] as String),
      retryCount: (json['retryCount'] as num).toInt(),
      status: json['status'] as String,
      serverConflictPayload: (json['serverConflictPayload'] as Map?)?.map(
        (k, e) => MapEntry(k as String, e),
      ),
    );

Map<String, dynamic> _$$OutboxEntryImplToJson(_$OutboxEntryImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'operation': instance.operation,
      'collectionPath': instance.collectionPath,
      'documentId': instance.documentId,
      'payload': instance.payload,
      'enqueuedAt': instance.enqueuedAt.toIso8601String(),
      'retryCount': instance.retryCount,
      'status': instance.status,
      'serverConflictPayload': instance.serverConflictPayload,
    };
