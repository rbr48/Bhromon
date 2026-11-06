import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/call_summary.dart';

/// Sends call figures to Crashlytics. The stage key says what the call was
/// doing when the app failed. The summary keys say how the last call went. A
/// crash report carries both, so a call problem can be told apart from an
/// unrelated crash. Aggregated call metrics need a store, which is a later step.
///
/// Nothing here holds a name, an email or message text. Web has no Crashlytics,
/// so every call does nothing there.
class CallTelemetry {
  CallTelemetry._();

  /// The call's current stage, such as ringing, connecting, connected or ended.
  static Future<void> stage(String stage) async {
    if (kIsWeb) return;
    try {
      await FirebaseCrashlytics.instance.setCustomKey('call_stage', stage);
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// The summary of a call that has ended, one per call on each side.
  static Future<void> summary(CallSummary summary) async {
    if (kIsWeb) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      for (final entry in summary.toKeys().entries) {
        await crashlytics.setCustomKey(entry.key, entry.value);
      }
      await crashlytics.log(
          'call ${summary.endReason.name}: connected ${summary.connectedSeconds}s, '
          'path ${summary.pathType ?? 'none'}, reconnects ${summary.reconnects}');
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// How the loudspeaker route stood once a call connected: `ok` when it held,
  /// `retry_ok` when it held after one more apply, `failed` when it did not, or
  /// `unknown` when the phone could not say. `systemCall` tells whether the phone's own
  /// call system holds the call. [detail] is the route as it was found, without names.
  static Future<void> speakerRoute({
    required String outcome,
    required bool systemCall,
    String? detail,
  }) async {
    if (kIsWeb) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCustomKey('call_speaker', outcome);
      await crashlytics.setCustomKey('call_system', systemCall ? 'yes' : 'no');
      if (detail != null) {
        await crashlytics.setCustomKey('call_speaker_route', detail);
      }
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }

  /// wifi, cellular, ethernet, none or other. Null when the platform cannot say,
  /// or after a second, so a call never waits for it.
  static Future<String?> networkType() async {
    if (kIsWeb) return null;
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 1));
      if (results.contains(ConnectivityResult.wifi)) return 'wifi';
      if (results.contains(ConnectivityResult.mobile)) return 'cellular';
      if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
      if (results.every((r) => r == ConnectivityResult.none)) return 'none';
      return 'other';
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
      return null;
    }
  }
}
