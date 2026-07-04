import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/value_objects/freshness_age.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../repositories/i_feed_repository.dart';

@injectable
class GetSmartFeedUseCase implements UseCase<List<TripLog>, ExplorerProfile> {
  final IFeedRepository _repository;
  final HiveEncryptionService _encryptionService;

  GetSmartFeedUseCase(this._repository, this._encryptionService);

  @override
  Future<Either<Failure, List<TripLog>>> call(ExplorerProfile params) async {
    final result = await _repository.getFeedItems(params);

    // Load local search history & preferences for personalized ranking
    List<String> searchHistory = [];
    Map<String, dynamic> preferences = {};
    try {
      final historyBox = await _encryptionService
          .openEncryptedBox<dynamic>('user_search_history');
      searchHistory = historyBox.values.cast<String>().toList();

      final prefsBox = await _encryptionService
          .openEncryptedBox<dynamic>('user_preferences');
      preferences = Map<String, dynamic>.from(prefsBox.toMap());
    } catch (_) {}

    // Load followed user IDs if the user is authenticated
    List<String> followedUids = [];
    if (params.uid.isNotEmpty && params.uid != 'explorer_user') {
      try {
        final followsSnapshot = await FirebaseFirestore.instance
            .collection('follows')
            .where('followerId', isEqualTo: params.uid)
            .get(const GetOptions(source: Source.serverAndCache));
        followedUids = followsSnapshot.docs
            .map((doc) => doc.data()['followedId']?.toString() ?? '')
            .where((uid) => uid.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    return result.map((logs) {
      final rankedLogs = List<TripLog>.from(logs);

      rankedLogs.sort((a, b) {
        final scoreA =
            _rankScore(a, params, searchHistory, preferences, followedUids);
        final scoreB =
            _rankScore(b, params, searchHistory, preferences, followedUids);
        return scoreB.compareTo(scoreA); // Descending order
      });

      return rankedLogs;
    });
  }

  double _rankScore(
    TripLog item,
    ExplorerProfile viewer,
    List<String> searchHistory,
    Map<String, dynamic> preferences,
    List<String> followedUids,
  ) {
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

      for (final keyword in searchHistory) {
        final kwLower = keyword.toLowerCase();
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
