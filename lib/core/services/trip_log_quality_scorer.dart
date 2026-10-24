import 'package:flutter/foundation.dart';

/// Params bag passed into the background isolate.
class _QualityParams {
  final String title;
  final String bodyText;
  final int imageCount;
  final int videoCount;
  final int routePointCount;
  final int costItemCount;
  final int safetyNoteCount;

  const _QualityParams({
    required this.title,
    required this.bodyText,
    required this.imageCount,
    required this.videoCount,
    required this.routePointCount,
    required this.costItemCount,
    required this.safetyNoteCount,
  });
}

/// Scores a trip log's quality from 0–100.
/// Used to auto-award trust score bonuses on submission.
///
/// Heavy computation is offloaded to a background [Isolate] via [Flutter.compute]
/// so it never blocks the main UI thread.
class TripLogQualityScorer {
  /// Async version that runs scoring in a background isolate.
  /// Prefer this over [scoreSync] for production use.
  static Future<QualityResult> score({
    required String title,
    required String bodyText,
    required int imageCount,
    required int videoCount,
    required int routePointCount,
    required int costItemCount,
    required int safetyNoteCount,
  }) {
    final params = _QualityParams(
      title: title,
      bodyText: bodyText,
      imageCount: imageCount,
      videoCount: videoCount,
      routePointCount: routePointCount,
      costItemCount: costItemCount,
      safetyNoteCount: safetyNoteCount,
    );
    // Spawning an isolate costs far more than scoring a normal diary (the
    // editor scores on every edit), so only very long text goes off-thread.
    if (title.length + bodyText.length < isolateThreshold) {
      return Future.value(_scoreInIsolate(params));
    }
    return compute(_scoreInIsolate, params);
  }

  /// Text length at which scoring moves to a background isolate.
  static const int isolateThreshold = 50000;

  @visibleForTesting
  static Future<QualityResult> scoreInIsolate({
    required String title,
    required String bodyText,
  }) {
    return compute(
      _scoreInIsolate,
      _QualityParams(
        title: title,
        bodyText: bodyText,
        imageCount: 0,
        videoCount: 0,
        routePointCount: 0,
        costItemCount: 0,
        safetyNoteCount: 0,
      ),
    );
  }

  /// Synchronous scoring — only use in tests or when already off the main thread.
  static QualityResult scoreSync({
    required String title,
    required String bodyText,
    required int imageCount,
    required int videoCount,
    required int routePointCount,
    required int costItemCount,
    required int safetyNoteCount,
  }) {
    return _scoreInIsolate(
      _QualityParams(
        title: title,
        bodyText: bodyText,
        imageCount: imageCount,
        videoCount: videoCount,
        routePointCount: routePointCount,
        costItemCount: costItemCount,
        safetyNoteCount: safetyNoteCount,
      ),
    );
  }

  static int _trustBonus(int score) {
    if (score >= 90) return 15;
    if (score >= 70) return 10;
    if (score >= 50) return 5;
    if (score >= 30) return 2;
    return 0;
  }
}

/// Top-level function required by [compute] (must be static or free function).
QualityResult _scoreInIsolate(_QualityParams params) {
  int total = 0;
  final List<String> tips = [];
  final List<String> strengths = [];

  // Title quality (0-10)
  if (params.title.trim().length >= 10) {
    total += 10;
    strengths.add('✅ Good title');
  } else {
    tips.add('📝 Add a more descriptive title (10+ chars)');
  }

  // Body length (0-30)
  final words = params.bodyText.trim().split(RegExp(r'\s+')).length;
  if (words >= 200) {
    total += 30;
    strengths.add('✅ Detailed description');
  } else if (words >= 100) {
    total += 20;
    tips.add('📝 Add more detail to reach 200+ words for max score');
  } else if (words >= 50) {
    total += 10;
    tips.add('📝 Your description is a bit short — aim for 100+ words');
  } else {
    tips.add('📝 Add a description (50+ words recommended)');
  }

  // Images (0-20)
  if (params.imageCount >= 3) {
    total += 20;
    strengths.add('✅ Great photo coverage');
  } else if (params.imageCount >= 1) {
    total += 10;
    tips.add('📸 Add 2 more photos for a higher quality score');
  } else {
    tips.add('📸 Add at least one photo');
  }

  // Video (0-10)
  if (params.videoCount >= 1) {
    total += 10;
    strengths.add('✅ Has video content');
  } else {
    tips.add('🎬 Add a short video for bonus quality points');
  }

  // Route (0-15)
  if (params.routePointCount >= 3) {
    total += 15;
    strengths.add('✅ Route tracked');
  } else if (params.routePointCount >= 1) {
    total += 8;
  } else {
    tips.add('🗺️ Add route waypoints to help other explorers');
  }

  // Cost breakdown (0-10)
  if (params.costItemCount >= 2) {
    total += 10;
    strengths.add('✅ Cost breakdown included');
  } else if (params.costItemCount >= 1) {
    total += 5;
  } else {
    tips.add('💰 Add a cost breakdown (transport, food, entry fee)');
  }

  // Safety notes (0-5)
  if (params.safetyNoteCount >= 1) {
    total += 5;
    strengths.add('✅ Safety info shared');
  } else {
    tips.add('🛡️ Add a safety note for fellow explorers');
  }

  final clampedScore = total.clamp(0, 100);
  return QualityResult(
    score: clampedScore,
    tips: tips,
    strengths: strengths,
    trustBonus: TripLogQualityScorer._trustBonus(clampedScore),
  );
}

class QualityResult {
  final int score;
  final List<String> tips;
  final List<String> strengths;
  final int trustBonus;

  const QualityResult({
    required this.score,
    required this.tips,
    required this.strengths,
    required this.trustBonus,
  });

  String get grade {
    if (score >= 90) return 'S';
    if (score >= 70) return 'A';
    if (score >= 50) return 'B';
    if (score >= 30) return 'C';
    return 'D';
  }

  String get gradeLabel {
    if (score >= 90) return 'Outstanding';
    if (score >= 70) return 'Great';
    if (score >= 50) return 'Good';
    if (score >= 30) return 'Basic';
    return 'Needs Work';
  }
}
