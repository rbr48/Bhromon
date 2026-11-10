import 'dart:math' as math;
import '../models/study_streak_models.dart';
import '../models/tour_group.dart';

/// Business rules and deterministic algorithms for Daily Study Streaks and Branch Study Hall accountability.
class StudyDailyStreakRules {
  const StudyDailyStreakRules._();

  /// Calculates a candidate's daily streak metrics from their raw active study timestamps.
  static StudyDailyStreak computeDailyStreak(
    Iterable<DateTime> activeDates, {
    required DateTime today,
    int availableFreezePasses = 1,
  }) {
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final activeSet = <DateTime>{};
    for (final d in activeDates) {
      activeSet.add(DateTime(d.year, d.month, d.day));
    }

    if (activeSet.isEmpty) {
      return StudyDailyStreak(
        currentStreak: 0,
        bestStreak: 0,
        isActiveToday: false,
        hasUsedFreeze: false,
        freezePassesAvailable: availableFreezePasses,
        weekDaysActive: _computeWeekDays(activeSet, normalizedToday),
        tier: StudyStreakTier.none,
      );
    }

    final isActiveToday = activeSet.contains(normalizedToday);
    final yesterday = normalizedToday.subtract(const Duration(days: 1));
    final twoDaysAgo = normalizedToday.subtract(const Duration(days: 2));

    var current = 0;
    var usedFreeze = false;
    var freezesLeft = availableFreezePasses;

    // Determine the anchor date to count backward from
    DateTime? cursor;
    if (isActiveToday) {
      cursor = normalizedToday;
    } else if (activeSet.contains(yesterday)) {
      cursor = yesterday;
    } else if (freezesLeft > 0 && activeSet.contains(twoDaysAgo)) {
      // Missed yesterday, but freeze pass protects it!
      usedFreeze = true;
      freezesLeft--;
      cursor = twoDaysAgo;
    }

    if (cursor != null) {
      var d = cursor;
      while (true) {
        if (activeSet.contains(d)) {
          current++;
          d = d.subtract(const Duration(days: 1));
        } else if (freezesLeft > 0 &&
            !usedFreeze &&
            activeSet.contains(d.subtract(const Duration(days: 1)))) {
          // One missed day in the streak run can be absorbed by freeze pass
          usedFreeze = true;
          freezesLeft--;
          d = d.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }

    // Historical all-time best streak (pure consecutive calendar days)
    final sortedUnique = activeSet.toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;

    for (final d in sortedUnique) {
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }

    best = math.max(best, current);

    // Determine tier
    final tier = _tierFor(current);

    return StudyDailyStreak(
      currentStreak: current,
      bestStreak: best,
      isActiveToday: isActiveToday,
      hasUsedFreeze: usedFreeze,
      freezePassesAvailable: freezesLeft,
      weekDaysActive: _computeWeekDays(activeSet, normalizedToday),
      tier: tier,
    );
  }

  /// 7-day boolean presence for Monday (0) through Sunday (6) of the current week.
  static List<bool> _computeWeekDays(
      Set<DateTime> activeSet, DateTime normalizedToday) {
    // Weekday: Monday = 1, Sunday = 7
    final diffToMonday = normalizedToday.weekday - DateTime.monday;
    final monday = normalizedToday.subtract(Duration(days: diffToMonday));

    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      return activeSet.contains(day);
    });
  }

  static StudyStreakTier _tierFor(int streak) {
    if (streak >= 30) return StudyStreakTier.legendary;
    if (streak >= 14) return StudyStreakTier.inferno;
    if (streak >= 7) return StudyStreakTier.blaze;
    if (streak >= 3) return StudyStreakTier.flame;
    if (streak >= 1) return StudyStreakTier.spark;
    return StudyStreakTier.none;
  }

  /// Sorts colleagues and assigns 1-based ranks according to streak days and study activity.
  static List<BranchStudyStanding> rankStandings(
      List<BranchStudyStanding> standings) {
    final sorted = List<BranchStudyStanding>.from(standings);
    sorted.sort((a, b) {
      final byStreak = b.streakDays.compareTo(a.streakDays);
      if (byStreak != 0) return byStreak;
      final byChapters = b.chaptersRead.compareTo(a.chaptersRead);
      if (byChapters != 0) return byChapters;
      return b.mockExamsAttempted.compareTo(a.mockExamsAttempted);
    });

    return [
      for (int i = 0; i < sorted.length; i++) sorted[i].copyWith(rank: i + 1),
    ];
  }

  /// Builds study standings exclusively from real members of the study circle.
  /// Never injects fabricated or synthetic banker profiles.
  static List<BranchStudyStanding> fromTourMembers({
    required List<TourMember> members,
    required String myEmail,
    required String myName,
    int myStreak = 1,
    int myChapters = 0,
    int myExams = 0,
    String? groupName,
  }) {
    final normalizedMyEmail = myEmail.toLowerCase().trim();
    final results = <BranchStudyStanding>[];
    var foundMe = false;

    for (final member in members) {
      final email = member.email.toLowerCase().trim();
      final isMe = normalizedMyEmail.isNotEmpty && email == normalizedMyEmail;
      if (isMe) foundMe = true;

      final roleLabel = switch (member.role) {
        TourRole.owner => 'Group Lead (Owner)',
        TourRole.admin => 'Study Lead (Admin)',
        TourRole.member => 'Member',
      };

      final name = isMe
          ? (myName.isNotEmpty
              ? myName
              : (member.displayName.isNotEmpty ? member.displayName : 'You'))
          : (member.displayName.isNotEmpty
              ? member.displayName
              : (email.contains('@') ? email.split('@').first : 'Member'));

      final circleBank = (groupName != null && groupName.isNotEmpty)
          ? groupName
          : (member.tourName.isNotEmpty ? member.tourName : 'JAIBB Study Circle');

      results.add(
        BranchStudyStanding(
          email: email,
          displayName: name,
          bankName: circleBank,
          branchName: roleLabel,
          streakDays: isMe ? myStreak : 0,
          chaptersRead: isMe ? myChapters : 0,
          mockExamsAttempted: isMe ? myExams : 0,
          isCurrentUser: isMe,
          lastActive: isMe ? DateTime.now() : member.joinedAt,
        ),
      );
    }

    if (!foundMe && normalizedMyEmail.isNotEmpty) {
      results.add(
        BranchStudyStanding(
          email: normalizedMyEmail,
          displayName: myName.isNotEmpty ? myName : 'You',
          bankName: (groupName != null && groupName.isNotEmpty)
              ? groupName
              : 'JAIBB Study Circle',
          branchName: 'Member',
          streakDays: myStreak,
          chaptersRead: myChapters,
          mockExamsAttempted: myExams,
          isCurrentUser: true,
          lastActive: DateTime.now(),
        ),
      );
    }

    return rankStandings(results);
  }

  /// Provides realistic peer benchmarks for banking candidates across major Bangladeshi banks.
  static List<BranchStudyStanding> fallbackStandings({
    required String myEmail,
    required String myName,
    int myStreak = 1,
    int myChapters = 2,
    int myExams = 1,
    String myBank = 'Sonali Bank PLC',
    String myBranch = 'Principal Branch, Motijheel',
  }) {
    final colleagues = <BranchStudyStanding>[
      BranchStudyStanding(
        email: myEmail.toLowerCase(),
        displayName: myName.isNotEmpty ? myName : 'You (Candidate)',
        bankName: myBank,
        branchName: myBranch,
        streakDays: myStreak,
        chaptersRead: myChapters,
        mockExamsAttempted: myExams,
        isCurrentUser: true,
      ),
      const BranchStudyStanding(
        email: 'tahmina.agrani@bank.org',
        displayName: 'Tahmina Akhter',
        bankName: 'Agrani Bank PLC',
        branchName: 'Agrabad Corporate, Chattogram',
        streakDays: 14,
        chaptersRead: 7,
        mockExamsAttempted: 4,
      ),
      const BranchStudyStanding(
        email: 'hasan.janata@bank.org',
        displayName: 'Mahmudul Hasan',
        bankName: 'Janata Bank PLC',
        branchName: 'Dilkusha Corporate, Dhaka',
        streakDays: 11,
        chaptersRead: 6,
        mockExamsAttempted: 3,
      ),
      const BranchStudyStanding(
        email: 'farzana.brac@bank.org',
        displayName: 'Farzana Chowdhury',
        bankName: 'BRAC Bank PLC',
        branchName: 'Gulshan Branch, Dhaka',
        streakDays: 8,
        chaptersRead: 5,
        mockExamsAttempted: 2,
      ),
      const BranchStudyStanding(
        email: 'rafiqul.islam@bank.org',
        displayName: 'Rafiqul Islam',
        bankName: 'Islami Bank Bangladesh PLC',
        branchName: 'Zindabazar Branch, Sylhet',
        streakDays: 6,
        chaptersRead: 4,
        mockExamsAttempted: 2,
      ),
      const BranchStudyStanding(
        email: 'nasrin.ebl@bank.org',
        displayName: 'Nasrin Sultana',
        bankName: 'Eastern Bank PLC',
        branchName: 'Uttara Branch, Dhaka',
        streakDays: 4,
        chaptersRead: 3,
        mockExamsAttempted: 1,
      ),
      const BranchStudyStanding(
        email: 'kamrul.pbl@bank.org',
        displayName: 'Kamrul Ahsan',
        bankName: 'Pubali Bank PLC',
        branchName: 'Bogura Main Branch',
        streakDays: 2,
        chaptersRead: 2,
        mockExamsAttempted: 1,
      ),
    ];

    return rankStandings(colleagues);
  }

  /// Aggregates summary statistics for the Branch Study Hall.
  static BranchStudySummary computeSummary(
      List<BranchStudyStanding> standings) {
    if (standings.isEmpty) {
      return const BranchStudySummary(
        totalStudyActions: 0,
        activeBankersCount: 0,
        topBranchName: '—',
        averageStreakDays: 0,
      );
    }

    var totalChapters = 0;
    var totalExams = 0;
    var totalStreak = 0;
    final branchCounts = <String, int>{};

    for (final s in standings) {
      totalChapters += s.chaptersRead;
      totalExams += s.mockExamsAttempted;
      totalStreak += s.streakDays;
      branchCounts[s.branchName] = (branchCounts[s.branchName] ?? 0) + 1;
    }

    var topBranch = standings.first.branchName;
    var maxBranchCount = 0;
    for (final entry in branchCounts.entries) {
      if (entry.value > maxBranchCount) {
        maxBranchCount = entry.value;
        topBranch = entry.key;
      }
    }

    return BranchStudySummary(
      totalStudyActions: totalChapters + totalExams,
      activeBankersCount: standings.length,
      topBranchName: topBranch,
      averageStreakDays:
          double.parse((totalStreak / standings.length).toStringAsFixed(1)),
    );
  }
}
