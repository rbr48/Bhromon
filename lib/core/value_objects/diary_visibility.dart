import 'package:freezed_annotation/freezed_annotation.dart';

/// Controls who can see a travel diary entry.
/// - [private]   → Only the author (stored locally in Hive, never synced)
/// - [friends]   → Author + mutual followers (Firestore, rules-restricted)
/// - [community] → Everyone (public feed — existing default behaviour)
enum DiaryVisibility {
  @JsonValue('private')
  private,

  @JsonValue('friends')
  friends,

  @JsonValue('community')
  community;

  /// Bangla display label
  String get label => switch (this) {
        DiaryVisibility.private => 'শুধু আমি',
        DiaryVisibility.friends => 'বন্ধুরা',
        DiaryVisibility.community => 'সবাই',
      };

  /// English display label
  String get labelEn => switch (this) {
        DiaryVisibility.private => 'Only Me',
        DiaryVisibility.friends => 'Friends',
        DiaryVisibility.community => 'Everyone',
      };

  /// Icon for UI
  String get icon => switch (this) {
        DiaryVisibility.private => '🔒',
        DiaryVisibility.friends => '👥',
        DiaryVisibility.community => '🌍',
      };

  /// Whether this entry should be uploaded to Firestore
  bool get shouldSync => this != DiaryVisibility.private;

  /// Whether anyone other than the author can read this
  bool get isPubliclyReadable => this == DiaryVisibility.community;
}
