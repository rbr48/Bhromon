import 'journey_geometry.dart';

/// Whether an [AlertTarget] is a stop on the route or the final destination the
/// group wakes up for.
enum AlertTargetKind { stop, finalDestination }

/// A place the journey alerts about.
class AlertTarget {
  const AlertTarget({
    required this.id,
    required this.name,
    required this.point,
    required this.kind,
    this.approachThresholdsM = const [],
    this.arriveRadiusM = 1000,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final AlertTargetKind kind;

  /// Distances at which an approach alert fires, in metres. Each fires once per
  /// approach.
  final List<double> approachThresholdsM;

  /// Within this distance the group counts as having arrived, in metres.
  final double arriveRadiusM;
}

/// The kinds of alert the engine raises.
enum HubAlertKind { approach, arrive, overshoot }

/// One alert the engine raised.
class HubAlert {
  const HubAlert({
    required this.kind,
    required this.targetId,
    required this.distanceM,
    this.thresholdM,
  });

  final HubAlertKind kind;
  final String targetId;

  /// How far the group was from the target when the alert fired, in metres.
  /// For an overshoot, how far past the end of the route it was.
  final double distanceM;

  /// For an approach alert, the threshold that fired, in metres.
  final double? thresholdM;
}

class _TargetState {
  final Set<double> fired = <double>{};

  /// Currently inside the arrival radius (re-arms once the group leaves).
  bool arrived = false;

  /// Has ever arrived on this trip. An overshoot after arriving is not an
  /// overshoot, so the wake-up alarm does not ring a second time.
  bool everArrived = false;

  /// Has raised the overshoot alert during the current excursion past the end.
  bool overshot = false;
}

/// Raises approach, arrival and overshoot alerts as a group moves.
///
/// Each approach threshold fires once per approach. When several are crossed in
/// one reading (a long gap in GPS), only the tightest fires, and the others are
/// marked as fired so they do not fire later. A threshold re-arms only after the
/// group is [hysteresisM] farther away than it, so GPS jitter at a boundary
/// cannot fire it twice. Arrival re-arms the same way.
class HubAlertEngine {
  HubAlertEngine({
    required List<AlertTarget> targets,
    this.hysteresisM = 1000,
    this.overshootM = 1000,
  })  : _targets = List.unmodifiable(targets),
        _state = {for (final t in targets) t.id: _TargetState()};

  final List<AlertTarget> _targets;
  final Map<String, _TargetState> _state;

  /// How far a group must move away before a threshold or arrival re-arms.
  final double hysteresisM;

  /// How far past the final destination the group must be before the
  /// overshoot alert fires.
  final double overshootM;

  /// Checks every target against [at]. [pastEndM] is how far past the end of the
  /// route the group is, from the tracker. It drives the overshoot alert.
  List<HubAlert> evaluate({required GeoPoint at, double pastEndM = 0}) {
    final alerts = <HubAlert>[];
    for (final target in _targets) {
      final s = _state[target.id]!;
      final d = distanceM(at, target.point);

      s.fired.removeWhere((threshold) => d > threshold + hysteresisM);
      if (s.arrived && d > target.arriveRadiusM + hysteresisM) {
        s.arrived = false;
      }

      if (!s.arrived && d <= target.arriveRadiusM) {
        s.arrived = true;
        s.everArrived = true;
        s.fired.addAll(target.approachThresholdsM);
        alerts.add(HubAlert(
          kind: HubAlertKind.arrive,
          targetId: target.id,
          distanceM: d,
        ));
      } else if (!s.arrived) {
        final crossed = [
          for (final threshold in target.approachThresholdsM)
            if (d <= threshold && !s.fired.contains(threshold)) threshold,
        ];
        if (crossed.isNotEmpty) {
          final tightest = crossed.reduce((a, b) => a < b ? a : b);
          s.fired.addAll(crossed);
          alerts.add(HubAlert(
            kind: HubAlertKind.approach,
            targetId: target.id,
            distanceM: d,
            thresholdM: tightest,
          ));
        }
      }

      if (pastEndM == 0) s.overshot = false;
      if (target.kind == AlertTargetKind.finalDestination &&
          !s.everArrived &&
          !s.overshot &&
          pastEndM > overshootM) {
        s.overshot = true;
        alerts.add(HubAlert(
          kind: HubAlertKind.overshoot,
          targetId: target.id,
          distanceM: pastEndM,
        ));
      }
    }
    return alerts;
  }
}
