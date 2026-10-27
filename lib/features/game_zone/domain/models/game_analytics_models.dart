import 'package:flutter/material.dart';
import 'online_game_session.dart';

export 'online_game_session.dart' show OnlineGameType;

/// Performance statistics for a single game type in the Game Zone.
class GameStatItem {
  final OnlineGameType gameType;
  final int matchesPlayed;
  final int matchesWon;
  final int currentStreak;
  final int bestStreak;
  final int highestScore;

  const GameStatItem({
    required this.gameType,
    this.matchesPlayed = 0,
    this.matchesWon = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.highestScore = 0,
  });

  double get winRate =>
      matchesPlayed > 0 ? (matchesWon / matchesPlayed) * 100 : 0.0;

  String get rankBadge {
    if (matchesWon >= 50) return 'Legend';
    if (matchesWon >= 25) return 'Grandmaster';
    if (matchesWon >= 10) return 'Master';
    if (matchesWon >= 3) return 'Contender';
    return 'Rookie';
  }

  IconData get rankIcon {
    if (matchesWon >= 50) return Icons.military_tech_rounded;
    if (matchesWon >= 25) return Icons.emoji_events_rounded;
    if (matchesWon >= 10) return Icons.workspace_premium_rounded;
    if (matchesWon >= 3) return Icons.stars_rounded;
    return Icons.shield_rounded;
  }

  GameStatItem recordOutcome({required bool won, int score = 0}) {
    final newMatches = matchesPlayed + 1;
    final newWins = won ? matchesWon + 1 : matchesWon;
    final newStreak = won ? currentStreak + 1 : 0;
    final newBestStreak = newStreak > bestStreak ? newStreak : bestStreak;
    final newHighScore = score > highestScore ? score : highestScore;

    return GameStatItem(
      gameType: gameType,
      matchesPlayed: newMatches,
      matchesWon: newWins,
      currentStreak: newStreak,
      bestStreak: newBestStreak,
      highestScore: newHighScore,
    );
  }

  Map<String, dynamic> toMap() => {
        'gameType': gameType.codeName,
        'matchesPlayed': matchesPlayed,
        'matchesWon': matchesWon,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
        'highestScore': highestScore,
      };

  factory GameStatItem.fromMap(Map<String, dynamic> map) {
    return GameStatItem(
      gameType: OnlineGameType.fromString(map['gameType'] as String?),
      matchesPlayed: (map['matchesPlayed'] as num?)?.toInt() ?? 0,
      matchesWon: (map['matchesWon'] as num?)?.toInt() ?? 0,
      currentStreak: (map['currentStreak'] as num?)?.toInt() ?? 0,
      bestStreak: (map['bestStreak'] as num?)?.toInt() ?? 0,
      highestScore: (map['highestScore'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single completed match record stored in the player's recent game history.
class GameMatchRecord {
  final String id;
  final OnlineGameType gameType;
  final bool won;
  final int score;
  final DateTime timestamp;
  final String mode;
  final String? details;

  const GameMatchRecord({
    required this.id,
    required this.gameType,
    required this.won,
    this.score = 0,
    required this.timestamp,
    this.mode = 'Online Table',
    this.details,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'gameType': gameType.codeName,
        'won': won,
        'score': score,
        'timestamp': timestamp.toIso8601String(),
        'mode': mode,
        if (details != null) 'details': details,
      };

  factory GameMatchRecord.fromMap(Map<String, dynamic> map) {
    return GameMatchRecord(
      id: map['id'] as String? ?? '',
      gameType: OnlineGameType.fromString(map['gameType'] as String?),
      won: map['won'] == true,
      score: (map['score'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.now(),
      mode: map['mode'] as String? ?? 'Online Table',
      details: map['details'] as String?,
    );
  }
}

/// Consolidated player game analytics across all Game Zone games.
class PlayerGameAnalytics {
  final Map<OnlineGameType, GameStatItem> gameStats;
  final List<GameMatchRecord> recentMatches;

  const PlayerGameAnalytics({
    required this.gameStats,
    this.recentMatches = const [],
  });

  factory PlayerGameAnalytics.empty() {
    return PlayerGameAnalytics(
      gameStats: {
        for (final type in OnlineGameType.values)
          type: GameStatItem(gameType: type),
      },
      recentMatches: const [],
    );
  }

  int get totalMatches =>
      gameStats.values.fold(0, (acc, item) => acc + item.matchesPlayed);

  int get totalWins =>
      gameStats.values.fold(0, (acc, item) => acc + item.matchesWon);

  double get overallWinRate =>
      totalMatches > 0 ? (totalWins / totalMatches) * 100 : 0.0;

  int get bestOverallStreak => gameStats.values
      .fold(0, (max, item) => item.bestStreak > max ? item.bestStreak : max);

  String get playerTitle {
    if (totalWins >= 100) return 'Game Zone Grandmaster';
    if (totalWins >= 50) return 'Tour Champion';
    if (totalWins >= 20) return 'Board Master';
    if (totalWins >= 5) return 'Active Contender';
    return 'Casual Explorer';
  }

  OnlineGameType? get favoriteGame {
    if (totalMatches == 0) return null;
    OnlineGameType? favorite;
    int maxPlayed = -1;
    for (final entry in gameStats.entries) {
      if (entry.value.matchesPlayed > maxPlayed) {
        maxPlayed = entry.value.matchesPlayed;
        favorite = entry.key;
      }
    }
    return favorite;
  }

  PlayerGameAnalytics withResult({
    required OnlineGameType gameType,
    required bool won,
    int score = 0,
    String mode = 'Online Table',
    String? details,
  }) {
    final current = gameStats[gameType] ?? GameStatItem(gameType: gameType);
    final updated = current.recordOutcome(won: won, score: score);
    final newMap = Map<OnlineGameType, GameStatItem>.from(gameStats);
    newMap[gameType] = updated;

    final newRecord = GameMatchRecord(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      gameType: gameType,
      won: won,
      score: score,
      timestamp: DateTime.now(),
      mode: mode,
      details: details,
    );
    final updatedMatches = [newRecord, ...recentMatches].take(20).toList();

    return PlayerGameAnalytics(
      gameStats: newMap,
      recentMatches: updatedMatches,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'gameStats': {
        for (final entry in gameStats.entries)
          entry.key.codeName: entry.value.toMap(),
      },
      'recentMatches': recentMatches.map((m) => m.toMap()).toList(),
    };
  }

  factory PlayerGameAnalytics.fromMap(Map<String, dynamic> map) {
    final rawStats = map['gameStats'] as Map<String, dynamic>? ?? {};
    final result = <OnlineGameType, GameStatItem>{};

    for (final type in OnlineGameType.values) {
      final itemMap = rawStats[type.codeName] as Map<String, dynamic>?;
      if (itemMap != null) {
        result[type] = GameStatItem.fromMap(itemMap);
      } else {
        result[type] = GameStatItem(gameType: type);
      }
    }

    final rawMatches = map['recentMatches'] as List<dynamic>? ?? [];
    final matches = rawMatches
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => GameMatchRecord.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    return PlayerGameAnalytics(
      gameStats: result,
      recentMatches: matches,
    );
  }
}

/// An entry in the Tour Group Leaderboard ranking members by total wins.
class TourLeaderboardEntry {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final int totalWins;
  final int totalMatches;
  final double winRate;
  final OnlineGameType? favoriteGame;
  final String rankBadge;

  const TourLeaderboardEntry({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    required this.totalWins,
    required this.totalMatches,
    required this.winRate,
    this.favoriteGame,
    required this.rankBadge,
  });

  factory TourLeaderboardEntry.fromMap(String uid, Map<String, dynamic> map) {
    final rawStats = map['gameStats'] as Map<String, dynamic>? ?? {};
    int wins = 0;
    int matches = 0;
    int maxPlayed = -1;
    OnlineGameType? favorite;

    for (final type in OnlineGameType.values) {
      final item = rawStats[type.codeName] as Map<String, dynamic>?;
      if (item != null) {
        final played = (item['matchesPlayed'] as num?)?.toInt() ?? 0;
        final w = (item['matchesWon'] as num?)?.toInt() ?? 0;
        wins += w;
        matches += played;
        if (played > maxPlayed) {
          maxPlayed = played;
          favorite = type;
        }
      }
    }

    final winRate = matches > 0 ? (wins / matches) * 100 : 0.0;
    String badge = 'Rookie';
    if (wins >= 50) {
      badge = 'Legend';
    } else if (wins >= 25) {
      badge = 'Grandmaster';
    } else if (wins >= 10) {
      badge = 'Master';
    } else if (wins >= 3) {
      badge = 'Contender';
    }

    return TourLeaderboardEntry(
      uid: uid,
      displayName: map['displayName'] as String? ?? 'Traveler',
      photoUrl: map['photoUrl'] as String?,
      totalWins: wins,
      totalMatches: matches,
      winRate: winRate,
      favoriteGame: favorite,
      rankBadge: badge,
    );
  }
}
