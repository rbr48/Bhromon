// The safety alerts (SOS) other members have raised that this person should see now, on
// whatever screen they are on. Pure Dart, so who is shown what is tested without Firebase.

import '../models/safety_alert_models.dart';

/// An open alert another member raised in one of this person's groups.
class IncomingSafetyAlert {
  const IncomingSafetyAlert({
    required this.tourId,
    required this.groupName,
    required this.alert,
  });

  final String tourId;
  final String groupName;
  final SafetyAlert alert;

  /// What the banner remembers as dismissed: one alert in one group.
  String get key => '$tourId/${alert.id}';
}

/// The alerts to show, newest first.
///
/// An alert is shown while it is open ([SafetyAlert.isOpenAt]), was raised by someone else,
/// and has not been dismissed on this device. A person's own alert is not shown: the safety
/// screen and its siren already tell them it is on. An alert whose time the server has not
/// set yet counts as the newest.
List<IncomingSafetyAlert> incomingSafetyAlerts({
  required Map<String, List<SafetyAlert>> alertsByTour,
  required Map<String, String> groupNames,
  required String myEmail,
  required DateTime now,
  Set<String> dismissed = const <String>{},
}) {
  final mine = myEmail.trim().toLowerCase();
  final incoming = <IncomingSafetyAlert>[];
  alertsByTour.forEach((tourId, alerts) {
    final name = groupNames[tourId];
    // A group that is no longer in the list is one the person has left.
    if (name == null) return;
    for (final alert in alerts) {
      if (!alert.isOpenAt(now)) continue;
      if (alert.senderEmail == mine) continue;
      final entry =
          IncomingSafetyAlert(tourId: tourId, groupName: name, alert: alert);
      if (dismissed.contains(entry.key)) continue;
      incoming.add(entry);
    }
  });
  incoming.sort((a, b) {
    final ta = a.alert.createdAt;
    final tb = b.alert.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  });
  return incoming;
}

/// The alerts in [now] that were not in [before], by [IncomingSafetyAlert.key]. These are
/// the ones the phone sounds for: an alert already on the banner does not sound again.
List<IncomingSafetyAlert> newlyArrivedAlerts(
  List<IncomingSafetyAlert> before,
  List<IncomingSafetyAlert> now,
) {
  final known = {for (final alert in before) alert.key};
  return [
    for (final alert in now)
      if (!known.contains(alert.key)) alert,
  ];
}
