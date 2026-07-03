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
  }) = FeedLoaded;
  const factory FeedState.error(String message) = FeedError;
}
