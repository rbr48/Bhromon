import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/utils/app_logger.dart';

/// Whether swiping the channel message area changes channel. On by default, for
/// people who swipe by accident, it can be turned off in Settings. The choice
/// stays on this device, in the same box as the language and the theme.
class ChannelSwipeController extends ChangeNotifier {
  ChannelSwipeController._();

  static final ChannelSwipeController instance = ChannelSwipeController._();

  static const String _boxName = 'app_prefs';
  static const String _key = 'channel_swipe_enabled';

  bool _enabled = true;

  bool get enabled => _enabled;

  /// Reads the saved choice. Until it loads, swiping stays on.
  Future<void> load() async {
    try {
      final box = await _openBox();
      final saved = box.get(_key);
      if (saved is bool && saved != _enabled) {
        _enabled = saved;
        notifyListeners();
      }
    } catch (e, st) {
      logWarning('[ChannelSwipeController] Could not load preference', e, st);
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final box = await _openBox();
      await box.put(_key, value);
    } catch (e, st) {
      logWarning('[ChannelSwipeController] Could not save preference', e, st);
    }
  }

  Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }
}
