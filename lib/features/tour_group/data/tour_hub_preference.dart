import 'package:hive/hive.dart';

/// The tour the Tours hub last showed on this device.
///
/// This is the hub's own pick. A screen that belongs to a tour gets the tour's
/// id in its route and never reads this. The key is the one the app used for
/// its old shared value, so a pick saved before this change still applies.
class TourHubPreference {
  static const _boxName = 'tour_groups_box';
  static const _key = 'last_active_tour_id';

  /// The saved tour id, or null when none is saved.
  String? read() {
    try {
      if (!Hive.isBoxOpen(_boxName)) return null;
      final saved = Hive.box<dynamic>(_boxName).get(_key);
      return saved is String && saved.isNotEmpty ? saved : null;
    } catch (_) {
      return null;
    }
  }

  /// Saves [tourId] as the hub's pick. An empty id is ignored.
  Future<void> remember(String tourId) async {
    if (tourId.isEmpty) return;
    await _write(tourId);
  }

  /// Clears the saved pick when it is [tourId], such as after the user left it.
  Future<void> forget(String tourId) async {
    if (read() != tourId) return;
    await _write(null);
  }

  Future<void> _write(String? tourId) async {
    try {
      final box = Hive.isBoxOpen(_boxName)
          ? Hive.box<dynamic>(_boxName)
          : await Hive.openBox<dynamic>(_boxName);
      if (tourId == null) {
        await box.delete(_key);
      } else {
        await box.put(_key, tourId);
      }
    } catch (_) {
      // Best effort: the hub opens on its default tour next time.
    }
  }
}
