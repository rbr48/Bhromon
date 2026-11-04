/// What the phone currently allows for location.
enum LocationAccess { notDetermined, denied, deniedForever, whileInUse, always }

/// The next step toward the location access a trip needs.
enum LocationStep {
  /// Ask for location while the app is in use. This is the first prompt.
  askWhileInUse,

  /// Show the in-app disclosure before asking for background location.
  showDisclosure,

  /// Ask for background location ("allow all the time").
  askAlways,

  /// The user refused for good. Send them to the phone's settings.
  openSettings,

  /// The phone's location service is switched off.
  turnOnService,

  /// The trip can track now.
  ready,
}

/// Decides the next location step (roadmap LJ-2.2).
///
/// A trip that tracks in the background needs "always" access. The app asks for
/// "while in use" first, shows the disclosure, and asks for "always" only after
/// the user has read it. A trip that does not track in the background needs only
/// "while in use".
LocationStep nextLocationStep({
  required LocationAccess access,
  required bool serviceEnabled,
  required bool needsBackground,
  required bool disclosureAccepted,
}) {
  if (!serviceEnabled) return LocationStep.turnOnService;
  switch (access) {
    case LocationAccess.deniedForever:
      return LocationStep.openSettings;
    case LocationAccess.notDetermined:
    case LocationAccess.denied:
      return LocationStep.askWhileInUse;
    case LocationAccess.whileInUse:
      if (!needsBackground) return LocationStep.ready;
      return disclosureAccepted
          ? LocationStep.askAlways
          : LocationStep.showDisclosure;
    case LocationAccess.always:
      return LocationStep.ready;
  }
}

/// How often the phone asks for a position (roadmap LJ-2.4).
class SamplingPlan {
  const SamplingPlan({required this.interval, required this.distanceFilterM});

  /// Between two positions, as the platform is asked to deliver them.
  final Duration interval;

  /// Movement, in metres, that must happen before a new position is delivered.
  final double distanceFilterM;

  /// Moving: about every 10 seconds.
  static const SamplingPlan moving = SamplingPlan(
    interval: Duration(seconds: 10),
    distanceFilterM: 25,
  );

  /// Stopped for a short while: about every minute.
  static const SamplingPlan stationary = SamplingPlan(
    interval: Duration(seconds: 60),
    distanceFilterM: 25,
  );

  /// Stopped for a long while, after the user has been asked: every five minutes.
  static const SamplingPlan resting = SamplingPlan(
    interval: Duration(minutes: 5),
    distanceFilterM: 50,
  );

  /// The plan for the current state. A long stop uses [resting].
  static SamplingPlan forState({required bool moving, required bool longStop}) {
    if (moving) return SamplingPlan.moving;
    return longStop ? SamplingPlan.resting : SamplingPlan.stationary;
  }
}

/// Tells moving from stopped, and a short stop from a long one.
class StationaryDetector {
  StationaryDetector({
    this.movingAboveMps = 1.5,
    this.longStopAfter = const Duration(minutes: 30),
  });

  /// A speed at or above this, in metres per second, counts as moving. 1.5 m/s
  /// is about 5 km/h, which is above walking pace when not stopped.
  final double movingAboveMps;

  /// How long a stop must last to count as a long stop.
  final Duration longStopAfter;

  DateTime? _stoppedSince;
  bool _moving = true;

  /// Whether the last reading showed movement.
  bool get isMoving => _moving;

  /// Records one reading: its speed, in metres per second, and its time.
  void observe({required double speedMps, required DateTime at}) {
    if (speedMps >= movingAboveMps) {
      _moving = true;
      _stoppedSince = null;
    } else {
      _moving = false;
      _stoppedSince ??= at;
    }
  }

  /// True once the phone has been stopped for [longStopAfter], checked at [now].
  bool isLongStop(DateTime now) {
    final since = _stoppedSince;
    return since != null && now.difference(since) >= longStopAfter;
  }
}
