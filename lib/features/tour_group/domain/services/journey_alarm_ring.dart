/// What the sound should do after a step. The alarm page plays or stops it.
enum RingSound { none, start, stop }

/// How the wake-up ended.
enum RingEnd {
  /// The user dismissed it.
  dismissed,

  /// The user said they are awake.
  awake,

  /// It rang its full number of times with no answer.
  expired,
}

/// Where the wake-up alarm is now.
enum RingStatus {
  /// Not started yet.
  idle,

  /// Sounding.
  ringing,

  /// Silent between two rings. The next ring is due at [AlarmRing.nextRingAt].
  waiting,

  /// Silent because the user snoozed it. The next ring is due at
  /// [AlarmRing.nextRingAt].
  snoozed,

  /// Finished. See [AlarmRing.end].
  done,
}

/// The timing of the wake-up alarm (roadmap rules 6 and 9). Pure: the caller
/// passes the time.
///
/// Each ring lasts [ringFor]. When a ring ends unanswered, the next one starts
/// after [pauseFor], up to [maxRings] rings. A snooze silences the alarm for
/// [snoozeFor], and the snooze can be used [maxSnoozes] times. Dismiss and "I am
/// awake" end it.
class AlarmRing {
  AlarmRing({
    this.ringFor = const Duration(seconds: 60),
    this.pauseFor = const Duration(seconds: 60),
    this.maxRings = 10,
    this.snoozeFor = const Duration(minutes: 5),
    this.maxSnoozes = 3,
  });

  final Duration ringFor;
  final Duration pauseFor;
  final int maxRings;
  final Duration snoozeFor;
  final int maxSnoozes;

  RingStatus _status = RingStatus.idle;
  RingEnd? _end;
  DateTime? _endsAt;
  DateTime? _nextAt;
  int _ringsStarted = 0;
  int _snoozesUsed = 0;

  RingStatus get status => _status;

  /// How the alarm ended, once it has.
  RingEnd? get end => _end;

  /// How many rings have started, counting snoozed ones.
  int get ringsStarted => _ringsStarted;

  /// How many snoozes have been used.
  int get snoozesUsed => _snoozesUsed;

  /// When the next ring starts, while the alarm is waiting or snoozed.
  DateTime? get nextRingAt {
    final silent =
        _status == RingStatus.waiting || _status == RingStatus.snoozed;
    return silent ? _nextAt : null;
  }

  /// True while a snooze is allowed: the alarm is ringing or waiting, and the
  /// user has snoozes left.
  bool get canSnooze {
    final active =
        _status == RingStatus.ringing || _status == RingStatus.waiting;
    return active && _snoozesUsed < maxSnoozes;
  }

  /// Starts the alarm at [now]. Does nothing once it has started.
  RingSound begin(DateTime now) {
    if (_status != RingStatus.idle) return RingSound.none;
    _startRing(now);
    return RingSound.start;
  }

  /// Moves the alarm on to [now] and returns the sound change, if any.
  RingSound advance(DateTime now) {
    switch (_status) {
      case RingStatus.idle:
      case RingStatus.done:
        return RingSound.none;
      case RingStatus.ringing:
        if (now.isBefore(_endsAt!)) return RingSound.none;
        if (_ringsStarted >= maxRings) {
          _finish(RingEnd.expired);
          return RingSound.stop;
        }
        _status = RingStatus.waiting;
        _nextAt = _endsAt!.add(pauseFor);
        _endsAt = null;
        return RingSound.stop;
      case RingStatus.waiting:
      case RingStatus.snoozed:
        if (now.isBefore(_nextAt!)) return RingSound.none;
        _startRing(now);
        return RingSound.start;
    }
  }

  /// Snoozes the alarm from [now]. Returns the sound change (stop when it was
  /// ringing), or null when no snooze is left or the alarm is not active.
  RingSound? snooze(DateTime now) {
    if (!canSnooze) return null;
    final wasRinging = _status == RingStatus.ringing;
    _snoozesUsed++;
    _status = RingStatus.snoozed;
    _nextAt = now.add(snoozeFor);
    _endsAt = null;
    return wasRinging ? RingSound.stop : RingSound.none;
  }

  /// The user dismissed the alarm.
  RingSound dismiss() => _finish(RingEnd.dismissed);

  /// The user says they are awake. This ends the alarm, and it is recorded as
  /// such.
  RingSound imAwake() => _finish(RingEnd.awake);

  RingSound _finish(RingEnd reason) {
    if (_status == RingStatus.done || _status == RingStatus.idle) {
      return RingSound.none;
    }
    final wasRinging = _status == RingStatus.ringing;
    _status = RingStatus.done;
    _end = reason;
    _endsAt = null;
    _nextAt = null;
    return wasRinging ? RingSound.stop : RingSound.none;
  }

  void _startRing(DateTime now) {
    _status = RingStatus.ringing;
    _endsAt = now.add(ringFor);
    _nextAt = null;
    _ringsStarted++;
  }
}
