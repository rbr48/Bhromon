import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/models/safety_alert_models.dart';
import '../domain/models/tour_group.dart';
import 'tour_group_repository.dart';

/// Listens for safety alerts (SOS) in every group of the signed-in person that has SOS.
///
/// Before this, an alert was read only by the safety screen and the Moments screen of its
/// own group. A member who had the app open anywhere else, or was looking at another group,
/// saw nothing until a push arrived, and a browser shows no push at all. The watcher keeps
/// one live listener per group with SOS, so an alert reaches every open app at once.
class SafetyAlertWatcher {
  SafetyAlertWatcher(this._repository);

  final TourGroupRepository _repository;

  /// The newest alerts of each group with SOS, by group id.
  final ValueNotifier<Map<String, List<SafetyAlert>>> alertsByTour =
      ValueNotifier<Map<String, List<SafetyAlert>>>(const {});

  /// The name of each group being watched, by group id.
  final ValueNotifier<Map<String, String>> groupNames =
      ValueNotifier<Map<String, String>>(const {});

  StreamSubscription<List<TourGroup>>? _groupsSub;
  final Map<String, StreamSubscription<List<SafetyAlert>>> _alertSubs = {};
  bool _running = false;

  bool get isRunning => _running;

  /// Starts watching. Calling it again while it runs does nothing.
  void start() {
    if (_running) return;
    _running = true;
    _groupsSub = _repository.watchMyGroups().listen(
          _onGroups,
          onError: (Object error, StackTrace stack) => logWarning(
              '[SafetyAlertWatcher] groups unavailable', error, stack),
        );
  }

  void _onGroups(List<TourGroup> groups) {
    if (_disposed || !_running) return;
    final withSos = {
      for (final group in groups)
        if (group.supportsSafetyAlerts) group.id: group.name,
    };
    for (final id in _alertSubs.keys.toList()) {
      if (!withSos.containsKey(id)) {
        unawaited(_alertSubs.remove(id)?.cancel());
        alertsByTour.value = {...alertsByTour.value}..remove(id);
      }
    }
    for (final id in withSos.keys) {
      if (_alertSubs.containsKey(id)) continue;
      // A few are enough: only the open ones are shown, and they are the newest.
      _alertSubs[id] = _repository.watchSafetyAlerts(id, limit: 5).listen(
        (alerts) {
          if (_disposed) return;
          alertsByTour.value = {...alertsByTour.value, id: alerts};
        },
        onError: (Object error, StackTrace stack) {
          logWarning(
              '[SafetyAlertWatcher] alerts of $id unavailable', error, stack);
          // Firestore closes a listener that failed. Dropping it lets the next groups
          // answer open it again.
          unawaited(_alertSubs.remove(id)?.cancel());
        },
      );
    }
    groupNames.value = withSos;
  }

  /// Stops every listener and forgets what was read. Called at sign-out.
  Future<void> stop() async {
    _running = false;
    final groups = _groupsSub;
    _groupsSub = null;
    final subs = _alertSubs.values.toList();
    _alertSubs.clear();
    // What was read is forgotten at once, before the listeners finish closing, so nothing
    // is written after a dispose.
    if (!_disposed) {
      alertsByTour.value = const {};
      groupNames.value = const {};
    }
    await groups?.cancel();
    for (final sub in subs) {
      await sub.cancel();
    }
  }

  bool _disposed = false;

  void dispose() {
    unawaited(stop());
    _disposed = true;
    alertsByTour.dispose();
    groupNames.dispose();
  }
}
