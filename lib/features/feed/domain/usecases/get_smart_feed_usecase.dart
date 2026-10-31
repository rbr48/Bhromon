import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/value_objects/freshness_age.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../repositories/i_feed_repository.dart';

/// Which feed collection a request pages through.
enum FeedSource { live, archived }

class SmartFeedRequest {
  final ExplorerProfile viewer;

  /// Reused from the previous page; loaded fresh when null (a refresh).
  final FeedViewerContext? viewerContext;
  final FeedCursor? after;
  final FeedSource source;
  final int pageSize;

  const SmartFeedRequest({
    required this.viewer,
    this.viewerContext,
    this.after,
    this.source = FeedSource.live,
    this.pageSize = kFeedPageSize,
  });
}

class SmartFeedPage {
  /// This page's logs, ranked for the viewer.
  final List<TripLog> logs;
  final FeedCursor? next;
  final FeedViewerContext viewerContext;

  const SmartFeedPage({
    required this.logs,
    required this.next,
    required this.viewerContext,
  });

  bool get hasMore => next != null;
}

/// The viewer's local personalisation signals.
class _RankSignals {
  /// Already lower-cased, so ranking doesn't redo it per log.
  final List<String> searchHistory;
  final Map<String, dynamic> preferences;
  final Set<String> followedUids;

  const _RankSignals(this.searchHistory, this.preferences, this.followedUids);
}

@injectable
class GetSmartFeedUseCase implements UseCase<SmartFeedPage, SmartFeedRequest> {
  final IFeedRepository _repository;
  final HiveEncryptionService _encryptionService;

  GetSmartFeedUseCase(this._repository, this._encryptionService);

  @override
  Future<Either<Failure, SmartFeedPage>> call(SmartFeedRequest request) async {
    final viewerContext = request.viewerContext ??
        await _repository.loadViewerContext(request.viewer);

    final pageResult = request.source == FeedSource.archived
        ? await _repository.getArchivedPage(request.viewer, viewerContext,
            pageSize: request.pageSize, after: request.after)
        : await _repository.getFeedPage(request.viewer, viewerContext,
            pageSize: request.pageSize, after: request.after);

    return pageResult.fold(
      (failure) async => Left(failure),
      (page) async {
        final signals = await _loadSignals(viewerContext);
        final ranked = rankLogs(
          page.logs,
          (log) => _rankScore(log, request.viewer, signals),
        );
        return Right(SmartFeedPage(
          logs: ranked,
          next: page.next,
          viewerContext: viewerContext,
        ));
      },
    );
  }

  Future<_RankSignals> _loadSignals(FeedViewerContext viewerContext) async {
    List<String> searchHistory = [];
    Map<String, dynamic> preferences = {};
    try {
      final historyBox = await _encryptionService
          .openEncryptedBox<dynamic>('user_search_history');
      searchHistory = historyBox.values
          .whereType<String>()
          .map((keyword) => keyword.toLowerCase())
          .toList();

      final prefsBox = await _encryptionService
          .openEncryptedBox<dynamic>('user_preferences');
      preferences = Map<String, dynamic>.from(prefsBox.toMap());
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
    return _RankSignals(searchHistory, preferences, viewerContext.followedUids);
  }

  /// Sorts [logs] by descending [score], calling [score] once per log.
  @visibleForTesting
  static List<TripLog> rankLogs(
      List<TripLog> logs, double Function(TripLog log) score) {
    final scored = [for (final log in logs) (log: log, score: score(log))];
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final entry in scored) entry.log];
  }

  double _rankScore(
    TripLog item,
    ExplorerProfile viewer,
    _RankSignals signals,
  ) {
    final searchHistory = signals.searchHistory;
    final preferences = signals.preferences;
    final followedUids = signals.followedUids;

    // 1. Freshness Factor (new posts are heavily favored)
    final referenceTime = item.publishedAt ?? item.lastConfirmed;
    final freshnessAge = FreshnessAge(referenceTime);
    final freshness = freshnessAge.decayFactor(); // 0.0 - 1.0

    // 2. Trust Level Weight
    final trust = item.tier.numericWeight; // 0.5 - 1.3

    // 3. Community Engagement (helpfulness ratio)
    final helpfulness = (item.helpfulVotes + 1.0) / (item.helpfulVotes + 10.0);

    // 4. Personalized Proximity / Location Check (High boost for same division)
    double locationBoost =
        item.division.toLowerCase() == viewer.division.toLowerCase()
            ? 1.5
            : 1.0;

    final preferredDivisions = preferences['preferred_divisions'];
    if (preferredDivisions is List &&
        preferredDivisions.contains(item.division)) {
      locationBoost *= 1.5; // Strong boost for explicitly selected division
    }

    // 5. Search History Personalized Boost
    double searchBoost = 1.0;
    if (searchHistory.isNotEmpty) {
      final titleLower = item.title.toLowerCase();
      final districtLower = item.district.toLowerCase();
      final divisionLower = item.division.toLowerCase();

      for (final kwLower in searchHistory) {
        if (titleLower.contains(kwLower) ||
            districtLower.contains(kwLower) ||
            divisionLower.contains(kwLower)) {
          searchBoost += 0.25; // Apply cumulative interest boost
        }
      }
    }

    // 6. Category Interest Boost
    double categoryBoost = 1.0;
    final preferredCategories = preferences['preferred_categories'];
    if (preferredCategories is List) {
      for (final block in item.blocks) {
        final blockTypeStr = switch (block) {
          TextBlock() => 'text',
          ImageBlock() => 'image',
          VideoBlock() => 'video',
          CostEntryBlock() => 'costEntry',
          RouteBlock() => 'route',
          SafetyNoteBlock() => 'safetyNote',
          VoiceNoteBlock() => 'voiceNote',
        };
        if (preferredCategories.contains(blockTypeStr)) {
          categoryBoost *= 1.25;
        }
      }
    }

    // 7. Implicit Engagement Boost (Division & Author clicks)
    double engagementBoost = 1.0;
    final divisionKey = 'interest_div_${item.division.toLowerCase()}';
    final authorKey = 'interest_author_${item.authorId}';
    final divClicks = preferences[divisionKey] as num? ?? 0;
    final authorClicks = preferences[authorKey] as num? ?? 0;

    engagementBoost += (divClicks * 0.1).clamp(0.0, 1.0);
    engagementBoost += (authorClicks * 0.15).clamp(0.0, 1.0);

    // 8. Follows Boost (High priority boost for followed creators)
    double followBoost = 1.0;
    if (followedUids.contains(item.authorId)) {
      followBoost = 2.5;
    }

    final verifiedBoost = item.tier.isVerifiedOrAbove ? 1.2 : 1.0;
    final safetyPenalty = item.hidden ? 0.0 : 1.0;

    return (freshness * freshness) *
        trust *
        helpfulness *
        locationBoost *
        searchBoost *
        categoryBoost *
        engagementBoost *
        followBoost *
        verifiedBoost *
        safetyPenalty;
  }
}
