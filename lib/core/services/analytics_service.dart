import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

class AnalyticsService {
  static final _analytics = FirebaseAnalytics.instance;

  // ── Trip & Content Events ─────────────────────────────────────────────────

  static Future<void> logTripLogPublished({
    required String division,
    required String district,
    required bool isPremiumGuide,
  }) async {
    await _safeLog(
      'trip_log_published',
      parameters: {
        'division': division,
        'district': district,
        'is_premium_guide': isPremiumGuide,
      },
    );
  }

  static Future<void> logPinVisited({
    required String pinId,
    required String pinName,
  }) async {
    await _safeLog(
      'pin_visited',
      parameters: {
        'pin_id': pinId,
        'pin_name': pinName,
      },
    );
  }

  static Future<void> logFeedItemEngaged({
    required String tripLogId,
    required String engagementType,
  }) async {
    await _safeLog(
      'feed_item_engaged',
      parameters: {
        'trip_log_id': tripLogId,
        'engagement_type': engagementType,
      },
    );
  }

  // ── Trust & Moderation Events ─────────────────────────────────────────────

  static Future<void> logTrustTierChanged({
    required String uid,
    required String oldTier,
    required String newTier,
  }) async {
    await _safeLog(
      'trust_tier_changed',
      parameters: {
        'uid': uid,
        'old_tier': oldTier,
        'new_tier': newTier,
      },
    );
  }

  static Future<void> logContentFlagged({
    required String targetType,
    required String flagType,
  }) async {
    await _safeLog(
      'content_flagged',
      parameters: {
        'target_type': targetType,
        'flag_type': flagType,
      },
    );
  }

  // ── Auth Events ───────────────────────────────────────────────────────────

  static Future<void> logSignIn({required String method}) async {
    await _safeLog('sign_in', parameters: {'method': method});
  }

  static Future<void> logSignOut() async {
    await _safeLog('sign_out');
  }

  // ── Offline Vault Events ──────────────────────────────────────────────────

  static Future<void> logOfflineVaultDownloaded({
    required String division,
  }) async {
    await _safeLog(
      'offline_vault_downloaded',
      parameters: {'division': division},
    );
  }

  // ── Premium Guide Events ──────────────────────────────────────────────────

  static Future<void> logPremiumGuideViewed({
    required String guideId,
  }) async {
    await _safeLog(
      'premium_guide_viewed',
      parameters: {'guide_id': guideId},
    );
  }

  // ── Search Events ─────────────────────────────────────────────────────────

  static Future<void> logSearchPerformed({required String query}) async {
    await _safeLog(
      'search_performed',
      parameters: {'query': query},
    );
  }

  // ── Generic fallback ──────────────────────────────────────────────────────

  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
  }) async {
    await _safeLog(name, parameters: parameters);
  }

  // ── Private helper ────────────────────────────────────────────────────────

  static Future<void> _safeLog(
    String name, {
    Map<String, dynamic>? parameters,
  }) async {
    if (kIsWeb) return; // Firebase Analytics not available on web for Flutter
    try {
      await _analytics.logEvent(
        name: name,
        parameters: parameters?.map(
          (k, v) => MapEntry(k, (v is bool ? (v ? 1 : 0) : v) as Object),
        ),
      );
      logDebug('📊 [Analytics] $name ${parameters ?? ''}');
    } catch (e, stack) {
      logWarning('📊 [Analytics] Failed to log $name', e, stack);
    }
  }
}
