import 'package:flutter/foundation.dart';

/// The motivational tier reached based on consecutive study streak days.
enum StudyStreakTier {
  none,
  spark,
  flame,
  blaze,
  inferno,
  legendary,
}

/// A candidate's daily study streak status.
@immutable
class StudyDailyStreak {
  final int currentStreak;
  final int bestStreak;
  final bool isActiveToday;
  final bool hasUsedFreeze;
  final int freezePassesAvailable;
  final List<bool>
      weekDaysActive; // 7 booleans: Monday (index 0) to Sunday (index 6)
  final StudyStreakTier tier;

  const StudyDailyStreak({
    required this.currentStreak,
    required this.bestStreak,
    required this.isActiveToday,
    this.hasUsedFreeze = false,
    this.freezePassesAvailable = 1,
    this.weekDaysActive = const [
      false,
      false,
      false,
      false,
      false,
      false,
      false
    ],
    this.tier = StudyStreakTier.none,
  });

  /// Empty default streak for a new member.
  static const StudyDailyStreak empty = StudyDailyStreak(
    currentStreak: 0,
    bestStreak: 0,
    isActiveToday: false,
    hasUsedFreeze: false,
    freezePassesAvailable: 1,
    weekDaysActive: [false, false, false, false, false, false, false],
    tier: StudyStreakTier.none,
  );

  /// Human-readable motivational title key for localization.
  String get tierKey {
    switch (tier) {
      case StudyStreakTier.spark:
        return 'study_tier_spark';
      case StudyStreakTier.flame:
        return 'study_tier_flame';
      case StudyStreakTier.blaze:
        return 'study_tier_blaze';
      case StudyStreakTier.inferno:
        return 'study_tier_inferno';
      case StudyStreakTier.legendary:
        return 'study_tier_legendary';
      case StudyStreakTier.none:
        return 'study_tier_spark';
    }
  }

  /// Flame emoji representation according to streak strength.
  String get flameIcon {
    if (currentStreak >= 30) return '👑';
    if (currentStreak >= 14) return '🏆';
    if (currentStreak >= 7) return '⚡';
    if (currentStreak >= 3) return '🔥';
    if (currentStreak >= 1) return '🌱';
    return '⏳';
  }
}

/// A colleague's standing in the Branch Study Hall accountability group.
@immutable
class BranchStudyStanding {
  final String email;
  final String displayName;
  final String bankName;
  final String branchName;
  final int streakDays;
  final int chaptersRead;
  final int mockExamsAttempted;
  final bool isCurrentUser;
  final DateTime? lastActive;
  final int rank;

  const BranchStudyStanding({
    required this.email,
    required this.displayName,
    required this.bankName,
    required this.branchName,
    required this.streakDays,
    required this.chaptersRead,
    required this.mockExamsAttempted,
    this.isCurrentUser = false,
    this.lastActive,
    this.rank = 1,
  });

  BranchStudyStanding copyWith({
    String? email,
    String? displayName,
    String? bankName,
    String? branchName,
    int? streakDays,
    int? chaptersRead,
    int? mockExamsAttempted,
    bool? isCurrentUser,
    DateTime? lastActive,
    int? rank,
  }) {
    return BranchStudyStanding(
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      bankName: bankName ?? this.bankName,
      branchName: branchName ?? this.branchName,
      streakDays: streakDays ?? this.streakDays,
      chaptersRead: chaptersRead ?? this.chaptersRead,
      mockExamsAttempted: mockExamsAttempted ?? this.mockExamsAttempted,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      lastActive: lastActive ?? this.lastActive,
      rank: rank ?? this.rank,
    );
  }
}

/// High-level summary metrics for a study circle's Branch Study Hall.
@immutable
class BranchStudySummary {
  final int totalStudyActions;
  final int activeBankersCount;
  final String topBranchName;
  final double averageStreakDays;

  const BranchStudySummary({
    required this.totalStudyActions,
    required this.activeBankersCount,
    required this.topBranchName,
    required this.averageStreakDays,
  });
}
