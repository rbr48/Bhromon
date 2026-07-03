import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/explorer_score.dart';
import '../value_objects/trust_tier.dart';
import '../utils/datetime_converter.dart';

part 'explorer_profile.freezed.dart';
part 'explorer_profile.g.dart';

@freezed
class ExplorerProfile with _$ExplorerProfile {
  const factory ExplorerProfile({
    required String uid,
    required String displayName,
    required ExplorerScore explorerScore,
    required TrustTier tier,
    required List<String> badges,
    required String division,
    @DateTimeConverter() required DateTime createdAt,
    @Default(false) bool isPioneer,
    @Default(false) bool isRegionExpert,
    String? avatarUrl,
    String? bio,
    String? coverUrl,

    // ── Travel Diary stats ───────────────────────────────────────────────────
    /// District names where the user has saved diary entries
    @Default([]) List<String> districtsDiaryLogged,

    /// Trip log IDs the user has bookmarked (saved diaries)
    @Default([]) List<String> savedTripLogIds,

    /// Total number of travel days logged across all diary entries
    @Default(0) int totalTripDays,

    /// Total BDT spent across all diary entries
    @Default(0.0) double totalSpentBDT,
    // ─────────────────────────────────────────────────────────────────────────
  }) = _ExplorerProfile;

  factory ExplorerProfile.fromJson(Map<String, dynamic> json) =>
      _$ExplorerProfileFromJson(json);
}

extension ExplorerProfileDiaryExt on ExplorerProfile {
  /// Number of unique districts the user has visited
  int get districtsCount => districtsDiaryLogged.length;

  /// Whether the user has completed all 8 divisions (all 64 districts)
  bool get hasExploredBangladesh => districtsCount >= 64;

  /// Percentage of Bangladesh explored (0.0 – 1.0)
  double get bangladeshCompletionRate => (districtsCount / 64.0).clamp(0.0, 1.0);

  /// Display string for stats
  String get statsDisplay =>
      '$districtsCount জেলা · $totalTripDays দিন · ৳${totalSpentBDT.toStringAsFixed(0)}';
}

