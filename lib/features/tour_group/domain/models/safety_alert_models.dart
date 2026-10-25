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

  factory SafetyAlert.fromMap(String id, Map<String, dynamic> map) {
    return SafetyAlert(
      id: id,
      senderEmail: normalizeEmail(map['senderEmail'] as String? ?? ''),
      senderName: map['senderName'] as String? ?? 'সদস্য',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: readDate(map['createdAt']),
      resolved: map['resolved'] as bool? ?? false,
    );
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
