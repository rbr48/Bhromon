import 'package:equatable/equatable.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/value_objects/diary_visibility.dart';
import '../../../../core/value_objects/trip_mood.dart';
import '../../../../core/value_objects/weather_snapshot.dart';

abstract class TripLogEvent extends Equatable {
  const TripLogEvent();
  @override
  List<Object?> get props => [];
}

class LoadDraftEvent extends TripLogEvent {
  final String pinId;
  const LoadDraftEvent(this.pinId);
  @override
  List<Object?> get props => [pinId];
}

class AddBlockEvent extends TripLogEvent {
  final TripBlock block;
  const AddBlockEvent(this.block);
  @override
  List<Object?> get props => [block];
}

class UpdateBlockEvent extends TripLogEvent {
  final int index;
  final TripBlock block;
  const UpdateBlockEvent(this.index, this.block);
  @override
  List<Object?> get props => [index, block];
}

class DeleteBlockEvent extends TripLogEvent {
  final int index;
  const DeleteBlockEvent(this.index);
  @override
  List<Object?> get props => [index];
}

class AutoSaveDraftEvent extends TripLogEvent {}

class UpdateTitleEvent extends TripLogEvent {
  final String title;
  const UpdateTitleEvent(this.title);
  @override
  List<Object?> get props => [title];
}

class PublishTripLogEvent extends TripLogEvent {
  final String title;
  const PublishTripLogEvent(this.title);
  @override
  List<Object?> get props => [title];
}

class ReorderBlocksEvent extends TripLogEvent {
  final List<TripBlock> blocks;
  const ReorderBlocksEvent(this.blocks);
  @override
  List<Object?> get props => [blocks];
}

class LoadExistingTripLogEvent extends TripLogEvent {
  final TripLog tripLog;
  const LoadExistingTripLogEvent(this.tripLog);
  @override
  List<Object?> get props => [tripLog];
}

// ── Travel Diary events ──────────────────────────────────────────────────────

/// Change who can see this diary entry.
class UpdateVisibilityEvent extends TripLogEvent {
  final DiaryVisibility visibility;
  const UpdateVisibilityEvent(this.visibility);
  @override
  List<Object?> get props => [visibility];
}

/// Set the emotional mood/tone of the trip.
class UpdateMoodEvent extends TripLogEvent {
  final TripMood? mood;
  const UpdateMoodEvent(this.mood);
  @override
  List<Object?> get props => [mood];
}

/// Update travel-style tags (solo, family, nature, etc.)
class UpdateTagsEvent extends TripLogEvent {
  final List<String> tags;
  const UpdateTagsEvent(this.tags);
  @override
  List<Object?> get props => [tags];
}

/// Set when the actual trip started and ended (separate from publish date).
class UpdateTripDatesEvent extends TripLogEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const UpdateTripDatesEvent({this.startDate, this.endDate});
  @override
  List<Object?> get props => [startDate, endDate];
}

/// Stamp the weather at the time of diary creation.
class StampWeatherEvent extends TripLogEvent {
  final WeatherSnapshot weather;
  const StampWeatherEvent(this.weather);
  @override
  List<Object?> get props => [weather];
}
// ─────────────────────────────────────────────────────────────────────────────
