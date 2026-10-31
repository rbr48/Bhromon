// What this device tells the family about itself: its battery, and whether it
// shares its place. The decisions are kept here, free of plugins and clocks, so
// they can be tested with fixed times.

/// A battery reading from this device. A null [level] means it could not be read,
/// so it is never shown as a number.
class DeviceBattery {
  const DeviceBattery({this.level, this.isCharging = false});

  /// Used when the device cannot report its battery (web, or a platform error).
  static const DeviceBattery unknown = DeviceBattery();

  /// A reading from the platform. A level outside 0 to 100 counts as unknown.
  factory DeviceBattery.reading({
    required int? level,
    required bool isCharging,
  }) {
    if (level == null || level < 0 || level > 100) return unknown;
    return DeviceBattery(level: level, isCharging: isCharging);
  }

  final int? level;
  final bool isCharging;

  @override
  bool operator ==(Object other) =>
      other is DeviceBattery &&
      other.level == level &&
      other.isCharging == isCharging;

  @override
  int get hashCode => Object.hash(level, isCharging);
}

/// A place on the map, in degrees.
class PositionFix {
  const PositionFix(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// What one publish writes. The coordinates are null unless the member is
/// sharing their place, and a null coordinate clears the stored one.
class FamilyTelemetryWrite {
  const FamilyTelemetryWrite({
    required this.battery,
    required this.sharing,
    this.latitude,
    this.longitude,
  });

  final DeviceBattery battery;
  final bool sharing;
  final double? latitude;
  final double? longitude;
}

typedef FamilyTelemetrySink = Future<void> Function(FamilyTelemetryWrite write);

typedef FamilyTelemetryErrorHandler = void Function(
  Object error,
  StackTrace stack,
);

/// Decides when this device writes its battery and place to the family.
///
/// The Safety Hub reports events as they happen: a battery change, a new
/// position, and a heartbeat tick. The publisher writes at most one position
/// every [minGap], and refreshes the record every [heartbeat], so a phone that
/// is not moving still looks live. It never reads the clock itself. Every method
/// takes the time it should use, so tests can drive it with fixed times.
class FamilyTelemetryPublisher {
  FamilyTelemetryPublisher({
    required FamilyTelemetrySink sink,
    FamilyTelemetryErrorHandler? onError,
    this.heartbeat = const Duration(minutes: 2),
    this.minGap = const Duration(seconds: 15),
  })  : _sink = sink,
        _onError = onError;

  final FamilyTelemetrySink _sink;
  final FamilyTelemetryErrorHandler? _onError;
  final Duration heartbeat;
  final Duration minGap;

  bool _sharing = false;
  PositionFix? _fix;
  bool _fixUnwritten = false;
  DeviceBattery? _battery;
  DateTime? _lastWriteAt;

  /// Whether this device is sharing its place right now.
  bool get isSharingLocation => _sharing;

  /// Called when the Safety Hub opens, with the battery just read. Writes "not
  /// sharing" with that battery, so a place left over from an earlier visit (for
  /// example after the app was closed) is cleared in the same write.
  Future<void> reset(DeviceBattery battery, DateTime now) async {
    _sharing = false;
    _fix = null;
    _fixUnwritten = false;
    _battery = battery;
    await _write(now);
  }

  /// Turns place sharing on or off. Turning it off clears the stored place.
  Future<void> setSharingLocation(bool on, DateTime now) async {
    if (on == _sharing) return;
    _sharing = on;
    if (!on) {
      _fix = null;
      _fixUnwritten = false;
    }
    await _write(now);
  }

  /// Records a battery reading. Writes straight away when it has changed.
  Future<void> onBattery(DeviceBattery battery, DateTime now) async {
    if (battery == _battery) return;
    _battery = battery;
    await _write(now);
  }

  /// Records a new position. It is written only while sharing, and no more often
  /// than [minGap]. A position that arrives too soon waits for the next tick.
  Future<void> onFix(PositionFix fix, DateTime now) async {
    if (!_sharing) return;
    _fix = fix;
    _fixUnwritten = true;
    final last = _lastWriteAt;
    if (last == null || now.difference(last) >= minGap) {
      await _write(now);
    }
  }

  /// Called on a timer. Writes when the heartbeat is due, or when a position is
  /// waiting and the minimum gap has passed.
  Future<void> tick(DateTime now) async {
    final last = _lastWriteAt;
    final heartbeatDue = last == null || now.difference(last) >= heartbeat;
    final fixWaiting =
        _fixUnwritten && (last == null || now.difference(last) >= minGap);
    if (heartbeatDue || fixWaiting) {
      await _write(now);
    }
  }

  /// Called when the Safety Hub closes. Stops sharing the place. The battery
  /// stays as the last reading.
  Future<void> stop(DateTime now) => setSharingLocation(false, now);

  Future<void> _write(DateTime now) async {
    final fix = _sharing ? _fix : null;
    final write = FamilyTelemetryWrite(
      battery: _battery ?? DeviceBattery.unknown,
      sharing: _sharing,
      latitude: fix?.latitude,
      longitude: fix?.longitude,
    );
    _lastWriteAt = now;
    _fixUnwritten = false;
    try {
      await _sink(write);
    } catch (error, stack) {
      // The next heartbeat writes again, so a failed write is reported, not kept.
      _onError?.call(error, stack);
    }
  }
}
