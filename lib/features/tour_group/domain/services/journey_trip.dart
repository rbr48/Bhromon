/// One journey trip, started on purpose by the user (roadmap rule 1).
class JourneyTrip {
  const JourneyTrip({
    required this.id,
    required this.tourId,
    required this.startedAt,
    required this.lastReadingAt,
    this.sharing = false,
  });

  final String id;
  final String tourId;
  final DateTime startedAt;

  /// When the last reading for this trip was accepted. The idle limit counts
  /// from here.
  final DateTime lastReadingAt;

  /// Whether the group can see this device's position (rule 2). Off by default.
  final bool sharing;

  JourneyTrip copyWith({DateTime? lastReadingAt, bool? sharing}) {
    return JourneyTrip(
      id: id,
      tourId: tourId,
      startedAt: startedAt,
      lastReadingAt: lastReadingAt ?? this.lastReadingAt,
      sharing: sharing ?? this.sharing,
    );
  }

  /// Plain values, so the trip can be stored on the device.
  Map<String, Object> toMap() => {
        'id': id,
        'tourId': tourId,
        'startedAt': startedAt.toUtc().millisecondsSinceEpoch,
        'lastReadingAt': lastReadingAt.toUtc().millisecondsSinceEpoch,
        'sharing': sharing,
      };

  /// Reads a trip stored by [toMap]. Returns null when a field is missing or has
  /// the wrong type, so a damaged record is ignored rather than crashing.
  static JourneyTrip? fromMap(Map<Object?, Object?> map) {
    final id = map['id'];
    final tourId = map['tourId'];
    final startedAt = map['startedAt'];
    final lastReadingAt = map['lastReadingAt'];
    final sharing = map['sharing'];
    if (id is! String ||
        tourId is! String ||
        startedAt is! int ||
        lastReadingAt is! int ||
        sharing is! bool) {
      return null;
    }
    return JourneyTrip(
      id: id,
      tourId: tourId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true),
      lastReadingAt:
          DateTime.fromMillisecondsSinceEpoch(lastReadingAt, isUtc: true),
      sharing: sharing,
    );
  }
}

/// Starts, runs and ends one trip at a time.
///
/// The lifecycle is pure: the caller passes the time, so the rules can be tested
/// with fixed clocks. A trip ends only when the user ends it, or when no reading
/// has been accepted for [idleLimit].
class JourneyTripLifecycle {
  JourneyTripLifecycle({this.idleLimit = const Duration(hours: 36)});

  /// How long a trip may go without an accepted reading before it ends itself.
  final Duration idleLimit;

  JourneyTrip? _active;

  /// The running trip, or null when none runs.
  JourneyTrip? get active => _active;

  /// Starts a trip. When a trip is already running, that trip comes back
  /// unchanged, so a double tap cannot replace it.
  JourneyTrip start({
    required String id,
    required String tourId,
    required DateTime now,
  }) {
    final running = _active;
    if (running != null) return running;
    final trip = JourneyTrip(
      id: id,
      tourId: tourId,
      startedAt: now,
      lastReadingAt: now,
    );
    _active = trip;
    return trip;
  }

  /// Puts back a trip stored before the app closed. The idle rule still applies
  /// at the next [endIfIdle] check.
  void restore(JourneyTrip trip) {
    _active = trip;
  }

  /// Records an accepted reading. Returns false when no trip is running.
  bool recordReading(DateTime now) {
    final trip = _active;
    if (trip == null) return false;
    _active = trip.copyWith(lastReadingAt: now);
    return true;
  }

  /// Turns sharing on or off for the running trip. Returns false when no trip is
  /// running.
  bool setSharing({required bool on}) {
    final trip = _active;
    if (trip == null) return false;
    _active = trip.copyWith(sharing: on);
    return true;
  }

  /// Ends the trip the user chose to end. Returns the ended trip, or null when
  /// none was running.
  JourneyTrip? end() {
    final trip = _active;
    _active = null;
    return trip;
  }

  /// Ends the trip when it has been idle for [idleLimit]. Returns the ended trip,
  /// or null when it is still live or none runs.
  JourneyTrip? endIfIdle(DateTime now) {
    final trip = _active;
    if (trip == null) return null;
    if (now.difference(trip.lastReadingAt) < idleLimit) return null;
    _active = null;
    return trip;
  }
}
