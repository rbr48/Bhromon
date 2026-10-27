import 'dart:io';
import 'package:bhromon/features/game_zone/data/game_analytics_service.dart';
import 'package:bhromon/features/game_zone/domain/models/game_analytics_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('bhromon_analytics_test_');
    Hive.init(tempDir.path);
  });
  group('GameStatItem', () {
    test('computes winRate and rankBadge correctly', () {
      const rookie = GameStatItem(
        gameType: OnlineGameType.chess,
        matchesPlayed: 2,
        matchesWon: 1,
      );
      expect(rookie.winRate, equals(50.0));
      expect(rookie.rankBadge, equals('Rookie'));

      const contender = GameStatItem(
        gameType: OnlineGameType.ludo,
        matchesPlayed: 10,
        matchesWon: 5,
      );
      expect(contender.winRate, equals(50.0));
      expect(contender.rankBadge, equals('Contender'));

      const master = GameStatItem(
        gameType: OnlineGameType.card29,
        matchesPlayed: 20,
        matchesWon: 15,
      );
      expect(master.rankBadge, equals('Master'));

      const grandmaster = GameStatItem(
        gameType: OnlineGameType.teenPatti,
        matchesPlayed: 40,
        matchesWon: 30,
      );
      expect(grandmaster.rankBadge, equals('Grandmaster'));

      const legend = GameStatItem(
        gameType: OnlineGameType.carrom,
        matchesPlayed: 80,
        matchesWon: 60,
      );
      expect(legend.rankBadge, equals('Legend'));
    });

    test('serializes and deserializes to and from Map accurately', () {
      const item = GameStatItem(
        gameType: OnlineGameType.card29,
        matchesPlayed: 12,
        matchesWon: 8,
        currentStreak: 3,
        bestStreak: 5,
        highestScore: 28,
      );

      final map = item.toMap();
      final restored = GameStatItem.fromMap(map);

      expect(restored.gameType, equals(OnlineGameType.card29));
      expect(restored.matchesPlayed, equals(12));
      expect(restored.matchesWon, equals(8));
      expect(restored.currentStreak, equals(3));
      expect(restored.bestStreak, equals(5));
      expect(restored.highestScore, equals(28));
    });
  });

  group('PlayerGameAnalytics', () {
    test('computes totals, win rate and player titles correctly', () {
      final initial = PlayerGameAnalytics.empty();
      expect(initial.totalMatches, equals(0));
      expect(initial.totalWins, equals(0));
      expect(initial.overallWinRate, equals(0.0));
      expect(initial.playerTitle, equals('Casual Explorer'));
      expect(initial.favoriteGame, isNull);

      final withWins = initial
          .withResult(
            gameType: OnlineGameType.chess,
            won: true,
            score: 10,
          )
          .withResult(
            gameType: OnlineGameType.chess,
            won: true,
            score: 20,
          );

      expect(withWins.totalMatches, equals(2));
      expect(withWins.totalWins, equals(2));
      expect(withWins.overallWinRate, equals(100.0));
      expect(withWins.playerTitle, equals('Casual Explorer')); // 2 wins is < 3
      expect(withWins.favoriteGame, equals(OnlineGameType.chess));

      PlayerGameAnalytics current = withWins;
      for (int i = 0; i < 3; i++) {
        current = current.withResult(
          gameType: OnlineGameType.chess,
          won: true,
        );
      }
      expect(current.totalWins, equals(5));
      expect(current.playerTitle, equals('Active Contender')); // >= 5 wins

      final chessStat = withWins.gameStats[OnlineGameType.chess]!;
      expect(chessStat.matchesPlayed, equals(2));
      expect(chessStat.matchesWon, equals(2));
      expect(chessStat.currentStreak, equals(2));
      expect(chessStat.bestStreak, equals(2));
      expect(chessStat.highestScore, equals(20));
    });

    test('resets streak on loss while preserving best streak and high score',
        () {
      var analytics = PlayerGameAnalytics.empty()
          .withResult(gameType: OnlineGameType.ludo, won: true, score: 100)
          .withResult(gameType: OnlineGameType.ludo, won: true, score: 150)
          .withResult(gameType: OnlineGameType.ludo, won: false, score: 50);

      final stat = analytics.gameStats[OnlineGameType.ludo]!;
      expect(stat.matchesPlayed, equals(3));
      expect(stat.matchesWon, equals(2));
      expect(stat.currentStreak, equals(0));
      expect(stat.bestStreak, equals(2));
      expect(stat.highestScore, equals(150));
      expect(stat.winRate, closeTo(66.66, 0.1));
    });
  });

  group('GameAnalyticsService', () {
    test('is a singleton and emits updates on recordMatch', () async {
      final service1 = GameAnalyticsService();
      final service2 = GameAnalyticsService();
      expect(identical(service1, service2), isTrue);

      final initialCount = service1.currentAnalytics.totalMatches;
      await service1.recordMatch(
        gameType: OnlineGameType.carrom,
        won: true,
        score: 12,
      );

      expect(service1.currentAnalytics.totalMatches, equals(initialCount + 1));
      final carromStat =
          service1.currentAnalytics.gameStats[OnlineGameType.carrom]!;
      expect(carromStat.highestScore, greaterThanOrEqualTo(12));
    });
  });
}
