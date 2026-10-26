import 'package:freezed_annotation/freezed_annotation.dart';
import 'trip_block.dart';
import '../value_objects/geo_coordinate.dart';
import 'cost_item.dart';
import '../value_objects/trust_tier.dart';
import '../value_objects/sync_status.dart';
import '../value_objects/diary_visibility.dart';
import '../value_objects/weather_snapshot.dart';
import '../value_objects/trip_mood.dart';
import '../utils/datetime_converter.dart';

part 'trip_log.freezed.dart';
part 'trip_log.g.dart';

@freezed
class TripLog with _$TripLog {
  const factory TripLog({
    required String tripId,
    required String authorId,
    required String title,
    required List<TripBlock> blocks,
    required List<GeoCoordinate> routePoints,
    required List<CostItem> costItems,
    required String locationPinId,
    required int trustScore,
    required int helpfulVotes,
    @DateTimeConverter() required DateTime lastConfirmed,
    required String division,
    required String district,
    @Default(false) bool hidden,
    @Default(TrustTier.unverified) TrustTier tier,
    @Default(SyncStatus.synced) SyncStatus syncStatus,
    String? hiddenReason,
    @NullableDateTimeConverter() DateTime? publishedAt,

    // ── Travel Diary fields ──────────────────────────────────────────────────
    /// Who can see this entry: private | friends | community
    @Default(DiaryVisibility.community) DiaryVisibility visibility,

    /// Auto-stamped weather at time of first save
    WeatherSnapshot? weatherAtVisit,

    /// Emotional tone of the trip
    TripMood? mood,

    /// Travel-style tags (solo, family, nature, heritage, etc.)
    @Default([]) List<String> tags,

    /// Reaction counts: {'wantToGo': 5, 'beenHere': 12, 'learned': 3, 'beautiful': 8}
    @Default({}) Map<String, int> reactions,

    /// Co-author UIDs who contributed blocks to this diary entry
    @Default([]) List<String> coAuthors,

    /// When the actual trip started (separate from publishedAt)
    @NullableDateTimeConverter() DateTime? tripStartDate,

    /// When the actual trip ended
    @NullableDateTimeConverter() DateTime? tripEndDate,
    // ─────────────────────────────────────────────────────────────────────────
  }) = _TripLog;

  factory TripLog.fromJson(Map<String, dynamic> json) =>
      _$TripLogFromJson(json);
}

extension TripLogArchiveExt on TripLog {
  bool get isArchived {
    final date = publishedAt ?? lastConfirmed;
    return DateTime.now().difference(date).inDays > 365;
  }

  /// Number of days the trip lasted (null if dates not set)
  int? get tripDays {
    if (tripStartDate == null || tripEndDate == null) return null;
    return tripEndDate!.difference(tripStartDate!).inDays + 1;
  }

  /// Total BDT spent on this trip (sum of all CostEntry blocks)
  double get totalSpentBDT {
    double total = 0;
    for (final item in costItems) {
      total += item.amountBDT;
    }
    return total;
  }

  /// Whether this entry is visible to a given viewer
  bool isVisibleTo({required String viewerUid, required bool isFollowing}) {
    if (viewerUid == authorId) return true;
    return switch (visibility) {
      DiaryVisibility.private => false,
      DiaryVisibility.friends => isFollowing,
      DiaryVisibility.community => !hidden,
    };
  }
}
