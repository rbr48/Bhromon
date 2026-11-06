import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/services/journey_alert_presentation.dart';
import 'journey_alarm_scheduler.dart';
import 'live_journey_session.dart';

/// Shows journey notices now, on the same plugin that schedules the alarms.
class FlutterJourneyNoticePort implements JourneyNoticePort {
  FlutterJourneyNoticePort(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required JourneyChannel channel,
    required bool rings,
    required String payload,
  }) {
    return _plugin.show(
      id,
      title,
      body,
      journeyNotificationDetails(channel: channel, rings: rings),
      payload: payload,
    );
  }
}
