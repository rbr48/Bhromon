import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/utils/app_logger.dart';
import '../domain/models/game_analytics_models.dart';

/// Service managing persistent Game Zone analytics, match records, and win rates.
class GameAnalyticsService {
  static final GameAnalyticsService _instance =
      GameAnalyticsService._internal();
  factory GameAnalyticsService() => _instance;
  GameAnalyticsService._internal();

  static const String boxName = 'game_analytics_box';
  static const String statsKey = 'player_stats';

  /// Whether local Hive storage is initialized and enabled.
  static bool hasStorage = false;

  final StreamController<PlayerGameAnalytics> _streamCtrl =
      StreamController<PlayerGameAnalytics>.broadcast();

  PlayerGameAnalytics _current = PlayerGameAnalytics.empty();
  bool _initialized = false;

  Stream<PlayerGameAnalytics> get analyticsStream => _streamCtrl.stream;
  PlayerGameAnalytics get currentAnalytics => _current;

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (Hive.isBoxOpen(boxName)) {
        hasStorage = true;
        final box = Hive.box<dynamic>(boxName);
        final raw = box.get(statsKey);
        if (raw is Map) {
          _current =
              PlayerGameAnalytics.fromMap(Map<String, dynamic>.from(raw));
        }
      } else if (hasStorage) {
        final box = await Hive.openBox<dynamic>(boxName);
        final raw = box.get(statsKey);
        if (raw is Map) {
          _current =
              PlayerGameAnalytics.fromMap(Map<String, dynamic>.from(raw));
        }
      }
    } catch (e, st) {
      logWarning('[GameAnalyticsService] Hive load error', e, st);
      _current = PlayerGameAnalytics.empty();
    }
    _initialized = true;
    _streamCtrl.add(_current);
  }

  Future<void> recordMatch({
    required OnlineGameType gameType,
    required bool won,
    int score = 0,
    String mode = 'Online Table',
    String? details,
  }) async {
    if (!_initialized) {
      await init();
    }
    _current = _current.withResult(
      gameType: gameType,
      won: won,
      score: score,
      mode: mode,
      details: details,
    );
    _streamCtrl.add(_current);

    // 1. Save locally to Hive if enabled
    if (hasStorage) {
      try {
        if (Hive.isBoxOpen(boxName)) {
          final box = Hive.box<dynamic>(boxName);
          await box.put(statsKey, _current.toMap());
        } else {
          final box = await Hive.openBox<dynamic>(boxName);
          await box.put(statsKey, _current.toMap());
        }
      } catch (e, st) {
        logWarning('[GameAnalyticsService] Hive save error', e, st);
      }
    }

    // 2. Best-effort Firestore sync if signed in
    try {
      if (Firebase.apps.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          String displayName = user.displayName ?? 'Player';
          String? photoUrl = user.photoURL;
          try {
            if (Hive.isBoxOpen('auth_box')) {
              final raw = Hive.box<dynamic>('auth_box').get('profile');
              if (raw is Map) {
                final map = Map<String, dynamic>.from(raw);
                if (map['displayName'] is String &&
                    (map['displayName'] as String).trim().isNotEmpty) {
                  displayName = (map['displayName'] as String).trim();
                }
                if (map['avatarUrl'] is String &&
                    (map['avatarUrl'] as String).isNotEmpty) {
                  photoUrl = map['avatarUrl'] as String;
                }
              }
            }
          } catch (_) {}

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('game_zone')
              .doc('stats')
              .set(
            {
              ..._current.toMap(),
              'displayName': displayName,
              'photoUrl': photoUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
    } catch (e, st) {
      logWarning('[GameAnalyticsService] Firestore sync error', e, st);
    }
  }

  /// Fetches game statistics for a list of tour members and returns sorted
  /// leaderboard entries.
  Future<List<TourLeaderboardEntry>> fetchTourLeaderboard(
    List<String> userUids,
    Map<String, String> uidToName,
    Map<String, String?> uidToPhoto,
  ) async {
    if (Firebase.apps.isEmpty || userUids.isEmpty) {
      return [];
    }

    final entries = <TourLeaderboardEntry>[];
    for (final uid in userUids) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('game_zone')
            .doc('stats')
            .get();

        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          final entry = TourLeaderboardEntry.fromMap(uid, data);
          entries.add(entry);
        } else {
          // Member has no online game record yet
          entries.add(TourLeaderboardEntry(
            uid: uid,
            displayName: uidToName[uid] ?? 'Traveler',
            photoUrl: uidToPhoto[uid],
            totalWins: 0,
            totalMatches: 0,
            winRate: 0.0,
            rankBadge: 'Rookie',
          ));
        }
      } catch (e, st) {
        logWarning('[GameAnalyticsService] Failed to load member stats', e, st);
      }
    }

    // Sort by wins desc, then winRate desc
    entries.sort((a, b) {
      final winComp = b.totalWins.compareTo(a.totalWins);
      if (winComp != 0) return winComp;
      return b.winRate.compareTo(a.winRate);
    });

    return entries;
  }

  Future<void> resetStats() async {
    _current = PlayerGameAnalytics.empty();
    _streamCtrl.add(_current);
    try {
      if (Hive.isBoxOpen(boxName)) {
        final box = Hive.box<dynamic>(boxName);
        await box.delete(statsKey);
      }
    } catch (_) {}
  }
}
