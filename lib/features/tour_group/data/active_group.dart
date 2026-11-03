import 'dart:async';

import 'tour_hub_preference.dart';

/// The group the user is working in on this device: the one the groups hub opened
/// last. The bottom navigation's Channels and Moments tabs and the groups list's
/// highlight read it. It is saved through [TourHubPreference], so it survives a restart.
///
/// One instance serves the whole app ([instance]). Screens read [current] and listen to
/// [changes]. A screen that belongs to a group gets the group id from its route and does
/// not need this.
class ActiveGroup {
  ActiveGroup({TourHubPreference? preference})
      : _preference = preference ?? TourHubPreference();

  /// The app-wide instance.
  static final ActiveGroup instance = ActiveGroup();

  final TourHubPreference _preference;
  final StreamController<String?> _changes =
      StreamController<String?>.broadcast();
  String? _current;
  bool _loaded = false;

  /// The active group's id, or null when none is selected. Read from the saved value
  /// the first time it is asked for.
  String? get current {
    if (!_loaded) {
      _current = _preference.read();
      _loaded = true;
    }
    return _current;
  }

  /// Every change: the new id, or null when the active group was cleared.
  Stream<String?> get changes => _changes.stream;

  /// Makes [tourId] the active group and saves it. An empty id is ignored.
  Future<void> select(String tourId) async {
    if (tourId.isEmpty) return;
    _current = tourId;
    _loaded = true;
    _changes.add(tourId);
    await _preference.remember(tourId);
  }

  /// Clears the active group when it is [tourId]: the user left that group or was
  /// removed from it. Any other id leaves the active group as it is.
  Future<void> clearIf(String tourId) async {
    if (current != tourId) return;
    await clear();
  }

  /// Clears the active group, such as at sign-out.
  Future<void> clear() async {
    final previous = current;
    _current = null;
    _loaded = true;
    _changes.add(null);
    if (previous != null) await _preference.forget(previous);
  }
}
