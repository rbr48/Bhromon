// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NotificationPayloadImpl _$$NotificationPayloadImplFromJson(Map json) =>
    _$NotificationPayloadImpl(
      title: json['title'] as String,
      body: json['body'] as String,
      action: json['action'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
    );

Map<String, dynamic> _$$NotificationPayloadImplToJson(
        _$NotificationPayloadImpl instance) =>
    <String, dynamic>{
      'title': instance.title,
      'body': instance.body,
      'action': instance.action,
      'data': instance.data,
    };
