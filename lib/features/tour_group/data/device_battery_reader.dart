import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/services/family_telemetry_publisher.dart';

/// Reads this phone's battery for the family's battery radar.
///
/// Web does not report a battery reliably (the plugin returns 0 when it cannot
/// read one), so web always reports unknown. Any platform error is also unknown,
/// and is logged, rather than shown as a number.
class DeviceBatteryReader {
  DeviceBatteryReader({Battery? battery}) : _battery = battery;

  Battery? _battery;

  Battery get _native => _battery ??= Battery();

  /// The current reading. Unknown on web or when the platform fails.
  Future<DeviceBattery> read() async {
    if (kIsWeb) return DeviceBattery.unknown;
    try {
      final level = await _native.batteryLevel;
      final state = await _native.batteryState;
      return DeviceBattery.reading(
        level: level,
        isCharging: state == BatteryState.charging,
      );
    } catch (error, stack) {
      logWarning('DeviceBatteryReader: battery unavailable', error, stack);
      return DeviceBattery.unknown;
    }
  }

  /// Fires whenever the charging state changes (plugged in, unplugged, full).
  /// Never fires on web.
  Stream<void> get changes {
    if (kIsWeb) return const Stream<void>.empty();
    return _native.onBatteryStateChanged.map((_) {});
  }
}
