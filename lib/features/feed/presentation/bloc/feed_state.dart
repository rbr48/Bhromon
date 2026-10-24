import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/pro_tip.dart';
import '../../../../core/entities/explorer_profile.dart';

part 'feed_state.freezed.dart';

@freezed
class FeedState with _$FeedState {
  const factory FeedState.initial() = FeedInitial;
  const factory FeedState.loading() = FeedLoading;
  const factory FeedState.loaded({
    required List<TripLog> logs,
    required List<ProTip> tips,
    required List<ExplorerProfile> explorers,

    /// More live logs can be fetched with `loadMore`.
    @Default(false) bool hasMore,
    @Default(false) bool isLoadingMore,

    /// Logs from the archive collection, fetched when the Archive tab opens.
    @Default(<TripLog>[]) List<TripLog> archivedLogs,
    @Default(false) bool archivedLoaded,
    @Default(false) bool archivedHasMore,
    @Default(false) bool isLoadingArchived,

    /// Saved logs in the order they were saved, fetched for the Saved tab.
    @Default(<TripLog>[]) List<TripLog> savedLogs,
  }) = FeedLoaded;
  const factory FeedState.error(String message) = FeedError;
}
