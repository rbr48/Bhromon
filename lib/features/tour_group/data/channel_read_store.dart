import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/utils/app_logger.dart';

/// Per-device channel state: when each channel was last read, and which
/// channels are muted. Nothing here is shared with other members. If the box
/// cannot be opened, reads return nothing and writes are dropped.
class ChannelReadStore {
  static const String _boxName = 'channel_prefs';

  Box<dynamic>? _box;

  Future<Box<dynamic>?> _open() async {
    if (_box != null) return _box;
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
    } catch (e, st) {
      logWarning('[ChannelReadStore] could not open $_boxName', e, st);
    }
    return _box;
  }

  /// Forgets the read times and mute settings of every channel in [tourId].
  Future<void> clearTour(String tourId) async {
    try {
      final box = await _open();
      if (box == null) return;
      // The separators keep 'tour_a' from matching 'tour_ab'.
      final prefixes = ['read|$tourId|', 'mute|$tourId|'];
      final doomed = box.keys
          .where((key) =>
              key is String && prefixes.any((prefix) => key.startsWith(prefix)))
          .toList();
      await box.deleteAll(doomed);
    } catch (e, st) {
      logWarning('[ChannelReadStore] could not clear $tourId', e, st);
    }
  }

  String _readKey(String tourId, String channelId) => 'read|$tourId|$channelId';

  String _muteKey(String tourId, String channelId) => 'mute|$tourId|$channelId';

  Future<DateTime?> lastRead(String tourId, String channelId) async {
    final box = await _open();
    final ms = box?.get(_readKey(tourId, channelId));
    return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> markRead(String tourId, String channelId, DateTime at) async {
    final box = await _open();
    await box?.put(_readKey(tourId, channelId), at.millisecondsSinceEpoch);
  }

  Future<bool> isMuted(String tourId, String channelId) async {
    final box = await _open();
    return box?.get(_muteKey(tourId, channelId)) == true;
  }

  Future<void> setMuted(String tourId, String channelId,
      {required bool muted}) async {
    final box = await _open();
    await box?.put(_muteKey(tourId, channelId), muted);
  }
}
