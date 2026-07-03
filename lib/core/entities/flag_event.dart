import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/flag_type.dart';

part 'flag_event.freezed.dart';
part 'flag_event.g.dart';

@freezed
class FlagEvent with _$FlagEvent {
  const factory FlagEvent({
    required String eventId,
    required String targetId,
    required String targetType, // 'trip_log' | 'pro_tip'
    required FlagType flagType,
    required String actorId,
    required DateTime timestamp,
    String? reason,
  }) = _FlagEvent;

  factory FlagEvent.fromJson(Map<String, dynamic> json) =>
      _$FlagEventFromJson(json);
}
