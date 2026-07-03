import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:injectable/injectable.dart';
import '../utils/app_logger.dart';

@lazySingleton
class FeatureFlags {
  final FirebaseRemoteConfig _config;

  FeatureFlags(this._config);

  static const _defaults = <String, dynamic>{
    'chat_enabled': true,
    'premium_guide_enabled': true,
    'feed_v2_enabled': false,
    'map_clustering_enabled': true,
    'offline_vault_enabled': true,
    'trust_system_enabled': true,
    'analytics_enabled': true,
  };

  Future<void> initialize() async {
    try {
      await _config.setDefaults(_defaults);
      await _config.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await _config.fetchAndActivate();
      logInfo('[FeatureFlags] Remote config fetched and activated');
    } catch (e, stack) {
      logWarning('Remote config fetch failed, using defaults', e, stack);
    }
  }

  // ── Feature Getters ───────────────────────────────────────────────────────

  bool get chatEnabled => _config.getBool('chat_enabled');
  bool get premiumGuideEnabled => _config.getBool('premium_guide_enabled');
  bool get feedV2Enabled => _config.getBool('feed_v2_enabled');
  bool get mapClusteringEnabled => _config.getBool('map_clustering_enabled');
  bool get offlineVaultEnabled => _config.getBool('offline_vault_enabled');
  bool get trustSystemEnabled => _config.getBool('trust_system_enabled');
  bool get analyticsEnabled => _config.getBool('analytics_enabled');
}
