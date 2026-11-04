import 'package:bhromon/features/tour_group/data/journey_alarm_scheduler.dart';
import 'package:bhromon/features/tour_group/domain/services/hub_alert_engine.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_alert_presentation.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_geometry.dart';
import 'package:bhromon/features/tour_group/domain/services/trip_alarm_plan.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the scheduler asks the device to do.
class _FakePort implements JourneyNotificationPort {
  final List<String> log = [];
  final Map<int, String> titles = {};

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required JourneyChannel channel,
    required bool rings,
  }) async {
    log.add('schedule $id ${fireAt.toUtc().toIso8601String()} '
        '${rings ? 'rings' : 'notify'} ${channel.name}');
    titles[id] = title;
  }

  @override
  Future<void> cancel(int id) async {
    log.add('cancel $id');
    titles.remove(id);
  }
}

final _now = DateTime.utc(2027, 1, 13, 20);

List<TripAlarm> _plan({DateTime? eta}) {
  return buildTripAlarmPlan(
    tripId: 'trip-1',
    stops: const [],
    finalDestination: const AlertTarget(
      id: 'F',
      name: 'Sajek',
      point: GeoPoint(23.3, 92.3),
      kind: AlertTargetKind.finalDestination,
    ),
    settings: const JourneyAlarmSettings(),
    now: _now,
    finalEta: eta,
  );
}

/// The id of the trip's ETA alarm. The plan also holds the destination's
/// geofence alarms, so the ETA alarm has to be picked out by kind.
int _etaAlarmId(DateTime eta) {
  return _plan(eta: eta)
      .firstWhere((alarm) => alarm.kind == TripAlarmKind.etaFallback)
      .id;
}

JourneyAlarmText _text(TripAlarm alarm) {
  return JourneyAlarmText(title: 'Wake up', body: alarm.kind.name);
}

void main() {
  group('JourneyAlarmScheduler', () {
    test('schedules the time alarm once, as a ringing alarm', () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);
      final eta = _now.add(const Duration(hours: 2));

      await scheduler.sync(plan: _plan(eta: eta), textFor: _text);

      expect(port.log, hasLength(1));
      expect(
        port.log.single,
        startsWith('schedule '),
      );
      expect(port.log.single, endsWith('rings alarm'));
      expect(
        port.log.single,
        contains(eta
            .subtract(const Duration(minutes: 25))
            .toUtc()
            .toIso8601String()),
      );
      expect(port.titles.values.single, 'Wake up');
    });

    test('a second sync with the same plan changes nothing', () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);
      final plan = _plan(eta: _now.add(const Duration(hours: 2)));
      await scheduler.sync(plan: plan, textFor: _text);
      port.log.clear();

      await scheduler.sync(plan: plan, textFor: _text);

      expect(port.log, isEmpty);
    });

    test('an ETA that moves by less than five minutes keeps its time',
        () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);
      await scheduler.sync(
        plan: _plan(eta: _now.add(const Duration(hours: 2))),
        textFor: _text,
      );
      port.log.clear();

      await scheduler.sync(
        plan: _plan(eta: _now.add(const Duration(hours: 2, minutes: 3))),
        textFor: _text,
      );

      expect(port.log, isEmpty);
    });

    test('an ETA that moves by more than five minutes is rescheduled',
        () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);
      final id = _etaAlarmId(_now.add(const Duration(hours: 2)));
      await scheduler.sync(
        plan: _plan(eta: _now.add(const Duration(hours: 2))),
        textFor: _text,
      );
      port.log.clear();

      await scheduler.sync(
        plan: _plan(eta: _now.add(const Duration(hours: 2, minutes: 20))),
        textFor: _text,
      );

      expect(port.log, hasLength(1));
      expect(port.log.single, startsWith('schedule $id '));
    });

    test('an alarm that leaves the plan is cancelled', () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);
      final id = _etaAlarmId(_now.add(const Duration(hours: 2)));
      await scheduler.sync(
        plan: _plan(eta: _now.add(const Duration(hours: 2))),
        textFor: _text,
      );
      port.log.clear();

      await scheduler.sync(plan: _plan(), textFor: _text);

      expect(port.log, ['cancel $id']);
      expect(scheduler.scheduledIds, isEmpty);
    });

    test('cancelAll cancels every scheduled alarm', () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);
      await scheduler.sync(
        plan: _plan(eta: _now.add(const Duration(hours: 2))),
        textFor: _text,
      );

      await scheduler.cancelAll();

      expect(scheduler.scheduledIds, isEmpty);
      expect(port.log.last, startsWith('cancel '));
    });

    test('geofence alarms are never scheduled by time', () async {
      final port = _FakePort();
      final scheduler = JourneyAlarmScheduler(port: port);

      await scheduler.sync(plan: _plan(), textFor: _text);

      expect(port.log, isEmpty);
      expect(scheduler.scheduledIds, isEmpty);
    });
  });

  group('notification details', () {
    test(
        'an alarm rings on the alarm usage, full screen, time-sensitive on iOS',
        () {
      final details = journeyNotificationDetails(
        channel: JourneyChannel.alarm,
        rings: true,
      );
      final android = details.android!;
      expect(android.channelId, kJourneyAlarmChannelId);
      expect(android.category, AndroidNotificationCategory.alarm);
      expect(android.audioAttributesUsage, AudioAttributesUsage.alarm);
      expect(android.fullScreenIntent, isTrue);
      expect(android.importance, Importance.max);
      expect(details.iOS!.interruptionLevel, InterruptionLevel.timeSensitive);
    });

    test('a stop notice notifies without taking the screen', () {
      final details = journeyNotificationDetails(
        channel: JourneyChannel.stop,
        rings: false,
      );
      final android = details.android!;
      expect(android.channelId, kJourneyStopChannelId);
      expect(android.category, AndroidNotificationCategory.reminder);
      expect(android.fullScreenIntent, isFalse);
      expect(android.importance, Importance.high);
      expect(details.iOS!.interruptionLevel, InterruptionLevel.active);
    });
  });
}
