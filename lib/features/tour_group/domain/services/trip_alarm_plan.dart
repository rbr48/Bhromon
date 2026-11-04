import 'hub_alert_engine.dart';

/// The kinds of alarm a trip can have.
enum TripAlarmKind {
  /// A notification as the group nears a stop.
  hubApproach,

  /// A notification when the group reaches a stop.
  hubArrive,

  /// A notification as the group nears the final destination.
  finalApproach,

  /// The wake-up alarm when the group reaches the final destination.
  finalArrive,

  /// The wake-up alarm when the group passes the final destination.
  overshoot,

  /// A time-based wake-up alarm, for when the GPS cannot be relied on.
  etaFallback,
}

/// One alarm a trip arms.
///
/// Geofence alarms fire when the [HubAlertEngine] raises the matching alert.
/// The ETA fallback has a fixed [fireAt] and is scheduled on the device, so it
/// rings even with no GPS.
class TripAlarm {
  const TripAlarm({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.rings,
    this.thresholdM,
    this.fireAt,
    this.ringSeconds = 60,
    this.maxRings = 1,
  });

  /// Stable across app restarts, so a scheduled alarm can be replaced or
  /// cancelled.
  final int id;

  final TripAlarmKind kind;

  /// The stop or final destination the alarm is about.
  final String targetId;

  /// True when the alarm rings like an alarm clock: alarm volume, full screen,
  /// repeating until dismissed. False for a notification.
  final bool rings;

  /// The approach distance for an approach alarm, in metres.
  final double? thresholdM;

  /// When a time-based alarm fires. Null for geofence alarms.
  final DateTime? fireAt;

  /// How long each ring lasts, in seconds.
  final int ringSeconds;

  /// How many rings before the alarm gives up and stays a notification.
  final int maxRings;
}

/// Which alarms a trip uses. The defaults wake the group at the final
/// destination and give notices as the group nears each stop.
class JourneyAlarmSettings {
  const JourneyAlarmSettings({
    this.hubApproach = true,
    this.hubApproachThresholdsM = const [5000, 1000],
    this.hubArrive = true,
    this.finalApproach = true,
    this.finalApproachThresholdsM = const [10000, 3000, 1000],
    this.finalArrivalAlarm = true,
    this.overshootAlarm = true,
    this.etaFallback = true,
    this.etaFallbackLead = const Duration(minutes: 25),
    this.mutedTargetIds = const <String>{},
  });

  final bool hubApproach;

  /// Distances at which a stop's approach notification fires, in metres.
  final List<double> hubApproachThresholdsM;

  final bool hubArrive;
  final bool finalApproach;

  /// Distances at which the final destination's approach notification fires,
  /// in metres.
  final List<double> finalApproachThresholdsM;

  /// Wake the group when they reach the final destination.
  final bool finalArrivalAlarm;

  /// Wake the group when they pass the final destination.
  final bool overshootAlarm;

  /// Arm a time-based alarm before the expected arrival.
  final bool etaFallback;

  /// How long before the expected arrival the time-based alarm fires.
  final Duration etaFallbackLead;

  /// Stops and destinations that raise no alarms.
  final Set<String> mutedTargetIds;

  JourneyAlarmSettings copyWith({
    bool? hubApproach,
    List<double>? hubApproachThresholdsM,
    bool? hubArrive,
    bool? finalApproach,
    List<double>? finalApproachThresholdsM,
    bool? finalArrivalAlarm,
    bool? overshootAlarm,
    bool? etaFallback,
    Duration? etaFallbackLead,
    Set<String>? mutedTargetIds,
  }) {
    return JourneyAlarmSettings(
      hubApproach: hubApproach ?? this.hubApproach,
      hubApproachThresholdsM:
          hubApproachThresholdsM ?? this.hubApproachThresholdsM,
      hubArrive: hubArrive ?? this.hubArrive,
      finalApproach: finalApproach ?? this.finalApproach,
      finalApproachThresholdsM:
          finalApproachThresholdsM ?? this.finalApproachThresholdsM,
      finalArrivalAlarm: finalArrivalAlarm ?? this.finalArrivalAlarm,
      overshootAlarm: overshootAlarm ?? this.overshootAlarm,
      etaFallback: etaFallback ?? this.etaFallback,
      etaFallbackLead: etaFallbackLead ?? this.etaFallbackLead,
      mutedTargetIds: mutedTargetIds ?? this.mutedTargetIds,
    );
  }
}

/// A 31-bit id for [key], the same on every run and every platform. Dart's
/// `String.hashCode` is not stable across runs, and a scheduled notification
/// needs an id that is. The top bit is set, so these ids do not collide with the
/// small ids other features use.
int stableAlarmId(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return 0x40000000 | (hash & 0x3fffffff);
}

/// The key of one alarm within a trip, such as `hubApproach|S1|5000.0`. The plan
/// and the alerts both build keys with this function, so an alert always finds
/// the alarm it belongs to.
String tripAlarmKey(TripAlarmKind kind, String targetId, {double? thresholdM}) {
  final base = '${kind.name}|$targetId';
  return thresholdM == null ? base : '$base|$thresholdM';
}

/// The stable notification id of one alarm within a trip.
int tripAlarmId(
  String tripId,
  TripAlarmKind kind,
  String targetId, {
  double? thresholdM,
}) {
  final key = tripAlarmKey(kind, targetId, thresholdM: thresholdM);
  return stableAlarmId('$tripId|$key');
}

/// Builds the alarms for one trip. Pure: the caller supplies the stops, the
/// final destination, the settings and the clock.
///
/// The final destination is the last stop of the outbound trip, not the home
/// the route may return to.
List<TripAlarm> buildTripAlarmPlan({
  required String tripId,
  required List<AlertTarget> stops,
  required AlertTarget? finalDestination,
  required JourneyAlarmSettings settings,
  required DateTime now,
  DateTime? finalEta,
}) {
  int idFor(TripAlarmKind kind, String targetId, {double? thresholdM}) =>
      tripAlarmId(tripId, kind, targetId, thresholdM: thresholdM);
  final plan = <TripAlarm>[];

  for (final stop in stops) {
    if (stop.kind != AlertTargetKind.stop) continue;
    if (settings.mutedTargetIds.contains(stop.id)) continue;
    if (settings.hubApproach) {
      for (final threshold in settings.hubApproachThresholdsM) {
        plan.add(TripAlarm(
          id: idFor(TripAlarmKind.hubApproach, stop.id, thresholdM: threshold),
          kind: TripAlarmKind.hubApproach,
          targetId: stop.id,
          thresholdM: threshold,
          rings: false,
        ));
      }
    }
    if (settings.hubArrive) {
      plan.add(TripAlarm(
        id: idFor(TripAlarmKind.hubArrive, stop.id),
        kind: TripAlarmKind.hubArrive,
        targetId: stop.id,
        rings: false,
      ));
    }
  }

  final destination = finalDestination;
  if (destination != null &&
      !settings.mutedTargetIds.contains(destination.id)) {
    if (settings.finalApproach) {
      for (final threshold in settings.finalApproachThresholdsM) {
        plan.add(TripAlarm(
          id: idFor(TripAlarmKind.finalApproach, destination.id,
              thresholdM: threshold),
          kind: TripAlarmKind.finalApproach,
          targetId: destination.id,
          thresholdM: threshold,
          rings: false,
        ));
      }
    }
    if (settings.finalArrivalAlarm) {
      plan.add(TripAlarm(
        id: idFor(TripAlarmKind.finalArrive, destination.id),
        kind: TripAlarmKind.finalArrive,
        targetId: destination.id,
        rings: true,
        maxRings: 10,
      ));
    }
    if (settings.overshootAlarm) {
      plan.add(TripAlarm(
        id: idFor(TripAlarmKind.overshoot, destination.id),
        kind: TripAlarmKind.overshoot,
        targetId: destination.id,
        rings: true,
        maxRings: 10,
      ));
    }
    final eta = finalEta;
    if (settings.etaFallback && eta != null) {
      final fireAt = eta.subtract(settings.etaFallbackLead);
      if (fireAt.isAfter(now)) {
        plan.add(TripAlarm(
          id: idFor(TripAlarmKind.etaFallback, destination.id),
          kind: TripAlarmKind.etaFallback,
          targetId: destination.id,
          rings: true,
          fireAt: fireAt,
          maxRings: 10,
        ));
      }
    }
  }

  assert(
    plan.map((a) => a.id).toSet().length == plan.length,
    'Alarm ids must be unique within a trip',
  );
  return plan;
}
