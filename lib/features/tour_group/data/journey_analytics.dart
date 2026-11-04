import 'package:firebase_analytics/firebase_analytics.dart';

import '../../../core/utils/app_logger.dart';

/// Usage counts for the live journey (roadmap LJ-6.4). The events carry no
/// position, no stop name and no person's name. The caller checks the remote
/// switch first.
class JourneyAnalytics {
  const JourneyAnalytics._();

  static Future<void> log(
    String name, {
    Map<String, Object> parameters = const {},
  }) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (error, stackTrace) {
      logSkipped(error, stackTrace);
    }
  }
}
