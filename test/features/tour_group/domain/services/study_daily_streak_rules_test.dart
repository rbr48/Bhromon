import 'package:bhromon/features/tour_group/domain/models/study_streak_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_daily_streak_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudyDailyStreakRules - computeDailyStreak', () {
    final today = DateTime(2026, 11, 10); // Tuesday

    test('empty active dates returns zero streak with no active today', () {
      final result = StudyDailyStreakRules.computeDailyStreak([], today: today);

      expect(result.currentStreak, 0);
      expect(result.bestStreak, 0);
      expect(result.isActiveToday, isFalse);
      expect(result.hasUsedFreeze, isFalse);
      expect(result.tier, StudyStreakTier.none);
      expect(result.weekDaysActive,
          equals([false, false, false, false, false, false, false]));
    });

    test('active today only gives 1-day streak and spark tier', () {
      final result = StudyDailyStreakRules.computeDailyStreak(
        [today],
        today: today,
      );

      expect(result.currentStreak, 1);
      expect(result.bestStreak, 1);
      expect(result.isActiveToday, isTrue);
      expect(result.hasUsedFreeze, isFalse);
      expect(result.tier, StudyStreakTier.spark);
      // Tuesday is index 1
      expect(result.weekDaysActive[1], isTrue);
      expect(result.weekDaysActive[0], isFalse);
    });

    test('consecutive 5-day active sequence gives 5-day streak and flame tier',
        () {
      final dates = [
        today,
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
        today.subtract(const Duration(days: 3)),
        today.subtract(const Duration(days: 4)),
      ];

      final result = StudyDailyStreakRules.computeDailyStreak(
        dates,
        today: today,
      );

      expect(result.currentStreak, 5);
      expect(result.bestStreak, 5);
      expect(result.isActiveToday, isTrue);
      expect(result.tier, StudyStreakTier.flame);
    });

    test('active yesterday but not today maintains streak as action needed',
        () {
      final dates = [
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 2)),
        today.subtract(const Duration(days: 3)),
      ];

      final result = StudyDailyStreakRules.computeDailyStreak(
        dates,
        today: today,
      );

      expect(result.currentStreak, 3);
      expect(result.isActiveToday, isFalse);
      expect(result.hasUsedFreeze, isFalse);
    });

    test('freeze pass protects streak when yesterday was missed', () {
      final dates = [
        // Missed yesterday (Nov 9)
        today.subtract(const Duration(days: 2)), // Nov 8
        today.subtract(const Duration(days: 3)), // Nov 7
      ];

      final result = StudyDailyStreakRules.computeDailyStreak(
        dates,
        today: today,
        availableFreezePasses: 1,
      );

      expect(result.currentStreak, 2);
      expect(result.hasUsedFreeze, isTrue);
      expect(result.freezePassesAvailable, 0);
    });

    test('streak breaks to 0 if gap exceeds freeze pass protection', () {
      final dates = [
        today.subtract(const Duration(days: 5)),
        today.subtract(const Duration(days: 6)),
      ];

      final result = StudyDailyStreakRules.computeDailyStreak(
        dates,
        today: today,
        availableFreezePasses: 1,
      );

      expect(result.currentStreak, 0);
      expect(result.bestStreak, 2);
    });

    test('motivational tiers scale with streak milestones', () {
      // 8 days -> blaze
      final blazeDates = [
        for (int i = 0; i < 8; i++) today.subtract(Duration(days: i))
      ];
      final blaze =
          StudyDailyStreakRules.computeDailyStreak(blazeDates, today: today);
      expect(blaze.tier, StudyStreakTier.blaze);
      expect(blaze.flameIcon, '⚡');

      // 15 days -> inferno
      final infernoDates = [
        for (int i = 0; i < 15; i++) today.subtract(Duration(days: i))
      ];
      final inferno =
          StudyDailyStreakRules.computeDailyStreak(infernoDates, today: today);
      expect(inferno.tier, StudyStreakTier.inferno);
      expect(inferno.flameIcon, '🏆');

      // 32 days -> legendary
      final legendaryDates = [
        for (int i = 0; i < 32; i++) today.subtract(Duration(days: i))
      ];
      final legendary = StudyDailyStreakRules.computeDailyStreak(legendaryDates,
          today: today);
      expect(legendary.tier, StudyStreakTier.legendary);
      expect(legendary.flameIcon, '👑');
    });
  });

  group('StudyDailyStreakRules - Standings & Accountability', () {
    test('rankStandings orders by streak, then chapters, then mock exams', () {
      final unranked = [
        const BranchStudyStanding(
          email: 'b@bank.org',
          displayName: 'B',
          bankName: 'Bank 2',
          branchName: 'Branch B',
          streakDays: 5,
          chaptersRead: 3,
          mockExamsAttempted: 1,
        ),
        const BranchStudyStanding(
          email: 'a@bank.org',
          displayName: 'A',
          bankName: 'Bank 1',
          branchName: 'Branch A',
          streakDays: 10,
          chaptersRead: 6,
          mockExamsAttempted: 2,
        ),
        const BranchStudyStanding(
          email: 'c@bank.org',
          displayName: 'C',
          bankName: 'Bank 3',
          branchName: 'Branch C',
          streakDays: 5,
          chaptersRead: 4,
          mockExamsAttempted: 1,
        ),
      ];

      final ranked = StudyDailyStreakRules.rankStandings(unranked);

      expect(ranked[0].email, 'a@bank.org');
      expect(ranked[0].rank, 1);
      expect(ranked[1].email,
          'c@bank.org'); // 5 streak, 4 chapters beats 3 chapters
      expect(ranked[1].rank, 2);
      expect(ranked[2].email, 'b@bank.org');
      expect(ranked[2].rank, 3);
    });

    test('fallbackStandings provides peer group and includes user', () {
      final peers = StudyDailyStreakRules.fallbackStandings(
        myEmail: 'candidate@bank.org',
        myName: 'Izhaan',
        myStreak: 9,
        myChapters: 5,
        myExams: 3,
      );

      expect(peers.length, greaterThanOrEqualTo(6));
      final me = peers.firstWhere((p) => p.isCurrentUser);
      expect(me.displayName, 'Izhaan');
      expect(me.streakDays, 9);
      expect(me.chaptersRead, 5);
      expect(me.rank, greaterThan(0));
    });

    test('computeSummary aggregates actions, counts, and top branch', () {
      final peers = StudyDailyStreakRules.fallbackStandings(
        myEmail: 'user@bank.org',
        myName: 'User',
      );

      final summary = StudyDailyStreakRules.computeSummary(peers);

      expect(summary.activeBankersCount, peers.length);
      expect(summary.totalStudyActions, greaterThan(10));
      expect(summary.averageStreakDays, greaterThan(0));
      expect(summary.topBranchName.isNotEmpty, isTrue);
    });
  });
}
