import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
    } catch (e) {
      debugPrint('[GameAnalyticsService] Hive load error: $e');
      _current = PlayerGameAnalytics.empty();
    }
    _initialized = true;
    _streamCtrl.add(_current);
  }

  Future<void> recordMatch({
    required OnlineGameType gameType,
    required bool won,
    int score = 0,
  }) async {
    if (!_initialized) {
      await init();
    }
    _current = _current.withResult(
      gameType: gameType,
      won: won,
      score: score,
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
      } catch (e) {
        debugPrint('[GameAnalyticsService] Hive save error: $e');
      }
    }

    // 2. Best-effort Firestore sync if signed in
    try {
      if (Firebase.apps.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('game_zone')
              .doc('stats')
              .set(
            {
              ..._current.toMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
    } catch (e) {
      debugPrint('[GameAnalyticsService] Firestore sync error: $e');
    }
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
