import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/app_logger.dart';

/// The theme the user picked: follow the system, light or dark. Dark stays the
/// default before a preference is loaded. The choice is kept on this device
/// only, in the same box as the language.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String _boxName = 'app_prefs';
  static const String _key = 'app_theme';

  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;

  /// The stored name for [mode].
  static String nameOf(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  /// The mode for a stored name, or null when the name is not one of the three.
  static ThemeMode? modeFor(String? name) {
    switch (name) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  /// Reads the saved choice.
  Future<void> load() async {
    try {
      final box = await _openBox();
      final saved = box.get(_key) as String?;
      final parsed = modeFor(saved);
      if (parsed != null) {
        _mode = parsed;
        notifyListeners();
      }
    } catch (e, st) {
      logWarning('[ThemeController] Could not load theme preference', e, st);
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final box = await _openBox();
      await box.put(_key, nameOf(mode));
    } catch (e, st) {
      logWarning('[ThemeController] Could not save theme preference', e, st);
    }
  }

  Future<Box<dynamic>> _openBox() async {
    try {
      if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
      return await Hive.openBox<dynamic>(_boxName);
    } catch (e, st) {
      logWarning(
          '[ThemeController] Corrupt preferences box: $e. Re-initializing...',
          e,
          st);
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        return await Hive.openBox<dynamic>(_boxName);
      } catch (_) {
        rethrow;
      }
    }
  }
}
