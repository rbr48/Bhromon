import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/explorer_profile.dart';

/// Number of trip logs fetched per feed page.
const int kFeedPageSize = 30;

/// Opaque position in a paged feed query. Only the repository that issued it
/// knows what [token] is (a Firestore document snapshot for the live feed).
class FeedCursor {
  final Object token;
  const FeedCursor(this.token);
}

/// One page of trip logs plus where to continue from.
class FeedPage {
  final List<TripLog> logs;
  final FeedCursor? next;

  const FeedPage({required this.logs, this.next});

  bool get hasMore => next != null;
}

/// Per-viewer data the feed needs for filtering and ranking. Loaded once per
/// refresh and reused for every following page.
class FeedViewerContext {
  final Set<String> blockedUids;
  final Set<String> followedUids;

  const FeedViewerContext({
    this.blockedUids = const {},
    this.followedUids = const {},
  });

  static const empty = FeedViewerContext();
}

abstract class IFeedRepository {
  /// Blocked and followed accounts for [viewerProfile]. Guests get
  /// [FeedViewerContext.empty].
  Future<FeedViewerContext> loadViewerContext(ExplorerProfile viewerProfile);

  /// Newest live trip logs, [pageSize] at a time, starting after [after].
  Future<Either<Failure, FeedPage>> getFeedPage(
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext, {
    int pageSize = kFeedPageSize,
    FeedCursor? after,
  });

  /// Trip logs moved to the `archived_trip_logs` collection, paged the same
  /// way as [getFeedPage].
  Future<Either<Failure, FeedPage>> getArchivedPage(
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext, {
    int pageSize = kFeedPageSize,
    FeedCursor? after,
  });

  /// Specific trip logs (live or archived) by id, for the Saved tab.
  Future<Either<Failure, List<TripLog>>> getTripLogsByIds(
    ExplorerProfile viewerProfile,
    FeedViewerContext viewerContext,
    List<String> tripIds,
  );
}
