import 'hub_alert_engine.dart';
import 'trip_alarm_plan.dart';

/// Which notification channel an alert uses. The alarm channel rings. The stop
/// channel notifies.
enum JourneyChannel { stop, alarm }

/// A message to translate: a key and its values. The UI layer translates it, so
/// this layer does not depend on the app's localisation.
class JourneyText {
  const JourneyText(this.key, [this.args = const {}]);

  final String key;
  final Map<String, String> args;

  @override
  bool operator ==(Object other) {
    if (other is! JourneyText || other.key != key) return false;
    if (other.args.length != args.length) return false;
    for (final entry in args.entries) {
      if (other.args[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(key, args.length);

  @override
  String toString() => 'JourneyText($key, $args)';
}

/// How one alert is shown. The caller translates the two texts.
class JourneyPresentation {
  const JourneyPresentation({
    required this.id,
    required this.channel,
    required this.rings,
    required this.title,
    required this.body,
  });

  /// Stable across runs, so a shown alarm can be replaced or cancelled.
  final int id;

  final JourneyChannel channel;

  /// True for the wake-up alarm: alarm volume, full screen, repeating.
  final bool rings;

  final JourneyText title;
  final JourneyText body;
}

/// The alarm kind an alert belongs to. The final destination has its own kinds,
/// because only it has the wake-up alarm.
TripAlarmKind alarmKindFor(HubAlert alert, AlertTargetKind targetKind) {
  final isDestination = targetKind == AlertTargetKind.finalDestination;
  switch (alert.kind) {
    case HubAlertKind.approach:
      return isDestination
          ? TripAlarmKind.finalApproach
          : TripAlarmKind.hubApproach;
    case HubAlertKind.arrive:
      return isDestination
          ? TripAlarmKind.finalArrive
          : TripAlarmKind.hubArrive;
    case HubAlertKind.overshoot:
      return TripAlarmKind.overshoot;
  }
}

/// How [alert] is shown on trip [tripId]. [placeName] is the stop or the
/// destination. [kmText] is the distance still to go, already formatted in the
/// user's numerals. Only approach alerts show it.
JourneyPresentation presentAlert({
  required String tripId,
  required HubAlert alert,
  required AlertTargetKind targetKind,
  required String placeName,
  String kmText = '',
}) {
  final kind = alarmKindFor(alert, targetKind);
  final id = tripAlarmId(
    tripId,
    kind,
    alert.targetId,
    thresholdM: alert.thresholdM,
  );
  final place = {'place': placeName};
  switch (kind) {
    case TripAlarmKind.hubApproach:
    case TripAlarmKind.finalApproach:
      return JourneyPresentation(
        id: id,
        channel: JourneyChannel.stop,
        rings: false,
        title: JourneyText('alarm_title_approach', place),
        body: JourneyText('alarm_body_distance', {'km': kmText}),
      );
    case TripAlarmKind.hubArrive:
      return JourneyPresentation(
        id: id,
        channel: JourneyChannel.stop,
        rings: false,
        title: JourneyText('alarm_title_arrive', place),
        body: const JourneyText('alarm_body_arrived'),
      );
    case TripAlarmKind.finalArrive:
    case TripAlarmKind.etaFallback:
      return JourneyPresentation(
        id: id,
        channel: JourneyChannel.alarm,
        rings: true,
        title: const JourneyText('alarm_title_final'),
        body: JourneyText('alarm_body_place', place),
      );
    case TripAlarmKind.overshoot:
      return JourneyPresentation(
        id: id,
        channel: JourneyChannel.alarm,
        rings: true,
        title: const JourneyText('alarm_title_overshoot'),
        body: JourneyText('alarm_body_place', place),
      );
  }
}
