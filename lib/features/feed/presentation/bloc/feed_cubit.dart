import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/pro_tip.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/repositories/i_feed_repository.dart';
import '../../domain/usecases/get_saved_trip_logs_usecase.dart';
import '../../domain/usecases/get_smart_feed_usecase.dart';
import '../../../pro_tip/domain/usecases/get_latest_tips_usecase.dart';
import '../../../explorer/domain/usecases/get_top_explorers_usecase.dart';
import 'feed_state.dart';

@injectable
class FeedCubit extends Cubit<FeedState> {
  final GetSmartFeedUseCase _getSmartFeed;
  final GetLatestTipsUseCase _getLatestTips;
  final GetTopExplorersUseCase _getTopExplorers;
  final GetSavedTripLogsUseCase _getSavedTripLogs;

  FeedCubit(
    this._getSmartFeed,
    this._getLatestTips,
    this._getTopExplorers,
    this._getSavedTripLogs,
  ) : super(const FeedInitial());

  /// Bumped by every [loadFeed]; results from an older generation are dropped
  /// so a slow earlier load can't overwrite a newer one.
  int _generation = 0;
  ExplorerProfile? _viewer;
  FeedViewerContext? _viewerContext;
  FeedCursor? _next;
  FeedCursor? _archivedNext;

  ExplorerProfile? get viewer => _viewer;

  Future<void> loadFeed(ExplorerProfile viewerProfile) async {
    final generation = ++_generation;
    _viewer = viewerProfile;
    _viewerContext = null;
    _next = null;
    _archivedNext = null;
    emit(const FeedLoading());

    final results = await Future.wait([
      _getSmartFeed(SmartFeedRequest(viewer: viewerProfile)),
      _getLatestTips(20),
      _getTopExplorers(10),
    ]);
    if (generation != _generation || isClosed) return;

    final pageRes = results[0] as Either<Failure, SmartFeedPage>;
    final tipsRes = results[1] as Either<Failure, List<ProTip>>;
    final explorersRes = results[2] as Either<Failure, List<ExplorerProfile>>;

    pageRes.fold(
      (failure) => emit(FeedError(failure.message)),
      (page) {
        tipsRes.fold(
          (failure) => emit(FeedError(failure.message)),
          (tips) {
            explorersRes.fold(
              (failure) => emit(FeedError(failure.message)),
              (explorers) {
                _viewerContext = page.viewerContext;
                _next = page.next;
                emit(FeedLoaded(
                  logs: page.logs,
                  tips: tips,
                  explorers: explorers,
                  hasMore: page.hasMore,
                ));
              },
            );
          },
        );
      },
    );
  }

  /// Appends the next page of the live feed.
  Future<void> loadMore() async {
    final current = state;
    final viewer = _viewer;
    if (current is! FeedLoaded ||
        viewer == null ||
        !current.hasMore ||
        current.isLoadingMore) {
      return;
    }
    final generation = _generation;
    emit(current.copyWith(isLoadingMore: true));

    final result = await _getSmartFeed(SmartFeedRequest(
      viewer: viewer,
      viewerContext: _viewerContext,
      after: _next,
    ));
    final latest = state;
    if (generation != _generation || isClosed || latest is! FeedLoaded) return;

    result.fold(
      (_) => emit(latest.copyWith(isLoadingMore: false)),
      (page) {
        _next = page.next;
        emit(latest.copyWith(
          logs: _appendNew(latest.logs, page.logs),
          hasMore: page.hasMore,
          isLoadingMore: false,
        ));
      },
    );
  }

  /// Fetches the first archive page, or the next one when [more] is true.
  Future<void> loadArchived({bool more = false}) async {
    final current = state;
    final viewer = _viewer;
    if (current is! FeedLoaded || viewer == null || current.isLoadingArchived) {
      return;
    }
    if (more ? !current.archivedHasMore : current.archivedLoaded) return;

    final generation = _generation;
    emit(current.copyWith(isLoadingArchived: true));

    final result = await _getSmartFeed(SmartFeedRequest(
      viewer: viewer,
      viewerContext: _viewerContext,
      after: more ? _archivedNext : null,
      source: FeedSource.archived,
    ));
    final latest = state;
    if (generation != _generation || isClosed || latest is! FeedLoaded) return;

    result.fold(
      (_) => emit(latest.copyWith(
        isLoadingArchived: false,
        archivedLoaded: true,
      )),
      (page) {
        _archivedNext = page.next;
        emit(latest.copyWith(
          archivedLogs: _appendNew(latest.archivedLogs, page.logs),
          archivedLoaded: true,
          archivedHasMore: page.hasMore,
          isLoadingArchived: false,
        ));
      },
    );
  }

  /// Resolves [tripIds] (most recently saved first) to logs, fetching only
  /// the ones not already loaded.
  Future<void> loadSaved(List<String> tripIds) async {
    final current = state;
    final viewer = _viewer;
    if (current is! FeedLoaded || viewer == null) return;

    final known = {
      for (final log in [
        ...current.logs,
        ...current.archivedLogs,
        ...current.savedLogs,
      ])
        log.tripId: log,
    };
    final missing = tripIds.where((id) => !known.containsKey(id)).toList();

    final generation = _generation;
    if (missing.isNotEmpty) {
      final result = await _getSavedTripLogs(SavedTripLogsRequest(
        viewer: viewer,
        viewerContext: _viewerContext ?? FeedViewerContext.empty,
        tripIds: missing,
      ));
      if (generation != _generation || isClosed) return;
      result.fold((_) {}, (logs) {
        for (final log in logs) {
          known[log.tripId] = log;
        }
      });
    }

    final latest = state;
    if (latest is! FeedLoaded) return;
    emit(latest.copyWith(savedLogs: [
      for (final id in tripIds)
        if (known[id] != null) known[id]!,
    ]));
  }

  static List<TripLog> _appendNew(List<TripLog> existing, List<TripLog> page) {
    final seen = existing.map((log) => log.tripId).toSet();
    return [
      ...existing,
      for (final log in page)
        if (seen.add(log.tripId)) log,
    ];
  }
}
