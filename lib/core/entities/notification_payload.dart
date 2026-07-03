import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_payload.freezed.dart';
part 'notification_payload.g.dart';

@freezed
class NotificationPayload with _$NotificationPayload {
  const factory NotificationPayload({
    required String title,
    required String body,
    required String action,
    required Map<String, dynamic> data,
  }) = _NotificationPayload;

  factory NotificationPayload.fromJson(Map<String, dynamic> json) =>
      _$NotificationPayloadFromJson(json);
}
