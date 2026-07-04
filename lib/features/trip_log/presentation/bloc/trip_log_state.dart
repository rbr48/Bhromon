import 'package:equatable/equatable.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/value_objects/diary_visibility.dart';
import '../../../../core/value_objects/trip_mood.dart';
import '../../../../core/value_objects/weather_snapshot.dart';
import '../../../../core/services/trip_log_quality_scorer.dart';

enum EditorStatus { idle, loading, saving, publishing, success, error }

class TripLogState extends Equatable {
  final String? tripId;
  final String pinId;
  final String title;
  final List<TripBlock> blocks;
  final EditorStatus status;
  final String? errorMessage;
  final List<String> validationErrors;

  // ── Travel Diary fields ───────────────────────────────────────────────────
  final DiaryVisibility visibility;
  final TripMood? mood;
  final List<String> tags;
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final WeatherSnapshot? weatherSnapshot;
  final QualityResult? qualityResult;
  // ──────────────────────────────────────────────────────────────────────────

  const TripLogState({
    this.tripId,
    required this.pinId,
    this.title = '',
    this.blocks = const [],
    this.status = EditorStatus.idle,
    this.errorMessage,
    this.validationErrors = const [],
    this.visibility = DiaryVisibility.community,
    this.mood,
    this.tags = const [],
    this.tripStartDate,
    this.tripEndDate,
    this.weatherSnapshot,
    this.qualityResult,
  });

  bool get isComplete {
    if (visibility == DiaryVisibility.private) {
      return true; // Self-posting mode: no requirements
    }
    return title.isNotEmpty &&
        hasImage &&
        hasSafetyNote &&
        hasCostEntry &&
        hasRoute;
  }

  bool get hasImage => blocks.any((b) => b.when(
        text: (_, __, ___) => false,
        image: (_, __, ___, ____) => true,
        video: (_, __, ___, ____) => true,
        costEntry: (_, __, ___) => false,
        route: (_, __, ___) => false,
        safetyNote: (_, __, ___) => false,
        voiceNote: (_, __, ___, ____, _____) => false,
      ));

  bool get hasSafetyNote => blocks.any((b) => b.when(
        text: (_, __, ___) => false,
        image: (_, __, ___, ____) => false,
        video: (_, __, ___, ____) => false,
        costEntry: (_, __, ___) => false,
        route: (_, __, ___) => false,
        safetyNote: (_, __, ___) => true,
        voiceNote: (_, __, ___, ____, _____) => false,
      ));

  bool get hasCostEntry => blocks.any((b) => b.when(
        text: (_, __, ___) => false,
        image: (_, __, ___, ____) => false,
        video: (_, __, ___, ____) => false,
        costEntry: (_, __, ___) => true,
        route: (_, __, ___) => false,
        safetyNote: (_, __, ___) => false,
        voiceNote: (_, __, ___, ____, _____) => false,
      ));

  bool get hasRoute => blocks.any((b) => b.when(
        text: (_, __, ___) => false,
        image: (_, __, ___, ____) => false,
        video: (_, __, ___, ____) => false,
        costEntry: (_, __, ___) => false,
        route: (_, __, ___) => true,
        safetyNote: (_, __, ___) => false,
        voiceNote: (_, __, ___, ____, _____) => false,
      ));

  /// Number of days for the trip (null if dates not set)
  int? get tripDays {
    if (tripStartDate == null || tripEndDate == null) return null;
    return tripEndDate!.difference(tripStartDate!).inDays + 1;
  }

  List<String> getMissingRequirements() {
    if (visibility == DiaryVisibility.private) {
      return const [];
    }
    final List<String> missing = [];
    if (title.isEmpty) missing.add('শিরোনাম দিন');
    if (!hasImage) missing.add('কমপক্ষে একটি ছবি বা ভিডিও যোগ করুন');
    if (!hasSafetyNote) missing.add('একটি সেফটি নোট যোগ করুন');
    if (!hasCostEntry) missing.add('খরচের বিবরণ যোগ করুন');
    if (!hasRoute) missing.add('রুট ম্যাপ আঁকুন');
    return missing;
  }

  TripLogState copyWith({
    String? tripId,
    String? pinId,
    String? title,
    List<TripBlock>? blocks,
    EditorStatus? status,
    String? errorMessage,
    List<String>? validationErrors,
    DiaryVisibility? visibility,
    TripMood? mood,
    bool clearMood = false,
    List<String>? tags,
    DateTime? tripStartDate,
    DateTime? tripEndDate,
    bool clearStartDate = false,
    bool clearEndDate = false,
    WeatherSnapshot? weatherSnapshot,
    QualityResult? qualityResult,
  }) {
    return TripLogState(
      tripId: tripId ?? this.tripId,
      pinId: pinId ?? this.pinId,
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      validationErrors: validationErrors ?? this.validationErrors,
      visibility: visibility ?? this.visibility,
      mood: clearMood ? null : (mood ?? this.mood),
      tags: tags ?? this.tags,
      tripStartDate:
          clearStartDate ? null : (tripStartDate ?? this.tripStartDate),
      tripEndDate: clearEndDate ? null : (tripEndDate ?? this.tripEndDate),
      weatherSnapshot: weatherSnapshot ?? this.weatherSnapshot,
      qualityResult: qualityResult ?? this.qualityResult,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tripId': tripId,
      'pinId': pinId,
      'title': title,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'status': status.name,
      'visibility': visibility.name,
      'mood': mood?.name,
      'tags': tags,
      'tripStartDate': tripStartDate?.toIso8601String(),
      'tripEndDate': tripEndDate?.toIso8601String(),
      'weatherSnapshot': weatherSnapshot?.toJson(),
    };
  }

  factory TripLogState.fromJson(Map<String, dynamic> json) {
    return TripLogState(
      tripId: json['tripId'] as String?,
      pinId: json['pinId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      blocks: (json['blocks'] as List? ?? [])
          .map((b) => TripBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      status: EditorStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => EditorStatus.idle,
      ),
      visibility: DiaryVisibility.values.firstWhere(
        (v) => v.name == json['visibility'],
        orElse: () => DiaryVisibility.community,
      ),
      mood: json['mood'] != null
          ? TripMood.values.firstWhere(
              (m) => m.name == json['mood'],
              orElse: () => TripMood.adventure,
            )
          : null,
      tags: (json['tags'] as List? ?? []).map((t) => t.toString()).toList(),
      tripStartDate: json['tripStartDate'] != null
          ? DateTime.tryParse(json['tripStartDate'] as String)
          : null,
      tripEndDate: json['tripEndDate'] != null
          ? DateTime.tryParse(json['tripEndDate'] as String)
          : null,
      weatherSnapshot: json['weatherSnapshot'] != null
          ? WeatherSnapshot.fromJson(
              json['weatherSnapshot'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        tripId,
        pinId,
        title,
        blocks,
        status,
        errorMessage,
        validationErrors,
        visibility,
        mood,
        tags,
        tripStartDate,
        tripEndDate,
        weatherSnapshot,
        qualityResult,
      ];
}
