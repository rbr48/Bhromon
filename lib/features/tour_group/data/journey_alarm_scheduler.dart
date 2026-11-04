import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/services/journey_alert_presentation.dart';
import '../domain/services/trip_alarm_plan.dart';

/// Channel ids for the two journey channels. Android keeps a channel's settings
/// once it exists, so these ids are never reused for another purpose.
const String kJourneyStopChannelId = 'journey_stop';
const String kJourneyAlarmChannelId = 'journey_alarm';

/// The channel names the system shows in its settings.
const String kJourneyStopChannelName = 'Journey stops';
const String kJourneyAlarmChannelName = 'Journey alarms';

/// Creates the two journey channels on Android. Calling it again is harmless.
Future<void> createJourneyChannels(
  AndroidFlutterLocalNotificationsPlugin android,
) async {
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kJourneyStopChannelId,
      kJourneyStopChannelName,
      description: 'Approaching and arriving at stops on your trip',
      importance: Importance.high,
    ),
  );
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kJourneyAlarmChannelId,
      kJourneyAlarmChannelName,
      description: 'The wake-up alarm for your destination',
      importance: Importance.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      playSound: true,
    ),
  );
}

/// The notification details for one kind of journey alert (roadmap D-1, D-3).
///
/// An alarm uses the alarm audio usage, so it sounds on the alarm volume, and it
/// opens full screen. A stop notice is a normal high-priority notification.
NotificationDetails journeyNotificationDetails({
  required JourneyChannel channel,
  required bool rings,
}) {
  final isAlarm = channel == JourneyChannel.alarm;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      isAlarm ? kJourneyAlarmChannelId : kJourneyStopChannelId,
      isAlarm ? kJourneyAlarmChannelName : kJourneyStopChannelName,
      importance: isAlarm ? Importance.max : Importance.high,
      priority: isAlarm ? Priority.max : Priority.high,
      category: isAlarm
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      fullScreenIntent: rings,
      audioAttributesUsage: isAlarm
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      autoCancel: !rings,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel:
          rings ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
    ),
  );
}

/// The notification calls the scheduler needs. The app uses
/// [FlutterJourneyNotificationPort]. Tests use a fake.
abstract class JourneyNotificationPort {
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required JourneyChannel channel,
    required bool rings,
  });

  Future<void> cancel(int id);
}

/// The title and body of one scheduled alarm, already translated.
class JourneyAlarmText {
  const JourneyAlarmText({required this.title, required this.body});

  final String title;
  final String body;
}

/// Keeps the device's time-based alarms in step with a trip's plan (roadmap
/// LJ-3.2).
///
/// Only alarms with a fixed time are scheduled here. The geofence alarms are
/// raised by the live tracker when they fire. A scheduled alarm whose time moved
/// by less than [moveTolerance] keeps its current time, so small ETA changes do
/// not reschedule it. An alarm no longer in the plan is cancelled.
class JourneyAlarmScheduler {
  JourneyAlarmScheduler({
    required this.port,
    this.moveTolerance = const Duration(minutes: 5),
  });

  final JourneyNotificationPort port;

  /// How far a time-based alarm may move before it is rescheduled.
  final Duration moveTolerance;

  final Map<int, DateTime> _scheduled = {};

  /// The ids currently scheduled on the device.
  Set<int> get scheduledIds => Set.unmodifiable(_scheduled.keys);

  /// Makes the device match [plan]. [textFor] gives the translated text of each
  /// alarm it schedules.
  Future<void> sync({
    required List<TripAlarm> plan,
    required JourneyAlarmText Function(TripAlarm alarm) textFor,
  }) async {
    final wanted = <int, TripAlarm>{
      for (final alarm in plan)
        if (alarm.fireAt != null) alarm.id: alarm,
    };
    for (final id in _scheduled.keys.toList()) {
      if (!wanted.containsKey(id)) await cancel(id);
    }
    for (final alarm in wanted.values) {
      final fireAt = alarm.fireAt!;
      final current = _scheduled[alarm.id];
      if (current != null &&
          current.difference(fireAt).abs() <= moveTolerance) {
        continue;
      }
      final text = textFor(alarm);
      await port.schedule(
        id: alarm.id,
        title: text.title,
        body: text.body,
        fireAt: fireAt,
        channel: JourneyChannel.alarm,
        rings: alarm.rings,
      );
      _scheduled[alarm.id] = fireAt;
    }
  }

  /// Cancels one scheduled alarm, such as the time alarm once the group arrives.
  Future<void> cancel(int id) async {
    _scheduled.remove(id);
    await port.cancel(id);
  }

  /// Cancels every scheduled alarm, such as when the trip ends.
  Future<void> cancelAll() async {
    for (final id in _scheduled.keys.toList()) {
      await cancel(id);
    }
  }
}

/// The real port, on flutter_local_notifications.
///
/// The fire time is an absolute instant. It is converted to UTC, so the alarm
/// rings at the right moment in any time zone, and no time-zone plugin is needed
/// to schedule it (roadmap D-5). The schedule uses the alarm clock mode, which
/// needs no exact-alarm permission (roadmap D-3).
class FlutterJourneyNotificationPort implements JourneyNotificationPort {
  FlutterJourneyNotificationPort(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required JourneyChannel channel,
    required bool rings,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(fireAt.toUtc(), tz.UTC),
      journeyNotificationDetails(channel: channel, rings: rings),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.alarmClock,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);
}
