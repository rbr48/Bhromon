// Safety alerts (SOS) that a member raises for the whole tour.

import 'date_codec.dart';

/// An alert nobody resolved stops counting as open after this long, so an old
/// SOS does not look live the next day.
const Duration kSafetyAlertWindow = Duration(hours: 6);

class SafetyAlert {
  final String id;
  final String senderEmail;
  final String senderName;
  final double? latitude;
  final double? longitude;

  /// Null while the server timestamp is still pending on this device.
  final DateTime? createdAt;
  final bool resolved;

  const SafetyAlert({
    required this.id,
    required this.senderEmail,
    required this.senderName,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.resolved = false,
  });

  /// Reads an alert. Every field is read by its type and a value of the wrong type is left
  /// out, so no document can make this throw. A coordinate outside the earth is left out too.
  factory SafetyAlert.fromMap(String id, Map<String, dynamic> map) {
    return SafetyAlert(
      id: id,
      senderEmail: normalizeEmail(_text(map['senderEmail']) ?? ''),
      senderName: _text(map['senderName']) ?? 'সদস্য',
      latitude: _coordinate(map['latitude'], 90),
      longitude: _coordinate(map['longitude'], 180),
      createdAt: readDate(map['createdAt']),
      resolved: map['resolved'] == true,
    );
  }

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }

  static double? _coordinate(Object? raw, double limit) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    if (!value.isFinite || value.abs() > limit) return null;
    return value;
  }

  /// True while the alert is unresolved and inside the window. An alert whose
  /// server time is not known yet counts as open, because it was just raised.
  bool isOpenAt(DateTime now) {
    if (resolved) return false;
    final raised = createdAt;
    if (raised == null) return true;
    return now.difference(raised) < kSafetyAlertWindow;
  }
}

/// The alerts in a snapshot, read one document at a time. A document that does not hold a
/// sender email cannot be attributed to anyone, so it is left out; the others are kept. One bad
/// document therefore never hides the rest of the list.
List<SafetyAlert> parseSafetyAlerts(
  Iterable<MapEntry<String, Map<String, dynamic>>> docs,
) {
  final alerts = <SafetyAlert>[];
  for (final doc in docs) {
    final alert = SafetyAlert.fromMap(doc.key, doc.value);
    if (alert.senderEmail.contains('@')) alerts.add(alert);
  }
  return alerts;
}

/// A family member's battery and place, as last published from their phone.
class BatteryTelemetry {
  final String email;
  final String name;

  /// 0 to 100, or null when the phone did not report it.
  final int? batteryLevel;
  final bool isCharging;

  /// Whether the member has chosen to share their place.
  final bool sharing;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAt;

  /// When this member last checked in as safe, or null if they never have.
  final DateTime? safeAt;

  const BatteryTelemetry({
    required this.email,
    required this.name,
    this.batteryLevel,
    this.isCharging = false,
    this.sharing = false,
    this.latitude,
    this.longitude,
    this.updatedAt,
    this.safeAt,
  });

  bool get isLowBattery => (batteryLevel ?? 101) <= 20;
  bool get isCriticalBattery => (batteryLevel ?? 101) <= 10;

  Map<String, dynamic> toMap() => {
        'email': normalizeEmail(email),
        'name': name,
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'sharing': sharing,
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': writeDate(updatedAt ?? DateTime.now()),
      };

  factory BatteryTelemetry.fromMap(Map<String, dynamic> map) {
    final level = (map['batteryLevel'] as num?)?.toInt();
    return BatteryTelemetry(
      email: normalizeEmail(map['email'] as String? ?? ''),
      name: map['name'] as String? ?? 'সদস্য',
      batteryLevel: level != null && level >= 0 && level <= 100 ? level : null,
      isCharging: map['isCharging'] as bool? ?? false,
      sharing: map['sharing'] == true,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      updatedAt: readDate(map['updatedAt']),
      safeAt: readDate(map['safeAt']),
    );
  }
}

/// How much of a member's place the family can see right now.
enum LocationStatus {
  /// Sharing, and updated within [kLiveLocationWindow].
  live,

  /// Sharing, but last updated longer ago. It is shown as the last known place.
  lastKnown,

  /// Not sharing, no place is stored, or the stored place is too old to show.
  off,
}

/// A place updated longer ago than this is not shown as live.
const Duration kLiveLocationWindow = Duration(minutes: 6);

/// A place older than this is not shown at all.
const Duration kLastKnownLocationWindow = Duration(hours: 12);

/// The [LocationStatus] of [t] at [now]. An update from a clock slightly ahead
/// of this device counts as live.
LocationStatus locationStatusAt(BatteryTelemetry t, DateTime now) {
  final at = t.updatedAt;
  if (!t.sharing || at == null || t.latitude == null || t.longitude == null) {
    return LocationStatus.off;
  }
  final age = now.difference(at);
  if (age <= kLiveLocationWindow) return LocationStatus.live;
  if (age <= kLastKnownLocationWindow) return LocationStatus.lastKnown;
  return LocationStatus.off;
}
