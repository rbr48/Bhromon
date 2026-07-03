import 'package:freezed_annotation/freezed_annotation.dart';

part 'outbox_entry.freezed.dart';
part 'outbox_entry.g.dart';

@freezed
class OutboxEntry with _$OutboxEntry {
  const factory OutboxEntry({
    required String id,
    required String operation,
    required String collectionPath,
    required String documentId,
    required Map<String, dynamic> payload,
    required DateTime enqueuedAt,
    required int retryCount,
    required String status,
    Map<String, dynamic>? serverConflictPayload,
  }) = _OutboxEntry;

  factory OutboxEntry.fromJson(Map<String, dynamic> json) =>
      _$OutboxEntryFromJson(json);
}
