import 'package:freezed_annotation/freezed_annotation.dart';

enum SyncStatus {
  @JsonValue('synced')
  synced,
  @JsonValue('pendingUpload')
  pendingUpload,
  @JsonValue('conflict')
  conflict,
  @JsonValue('failed')
  failed;
}
