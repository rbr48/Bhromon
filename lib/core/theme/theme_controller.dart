import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// The theme the user picked: follow the system, light or dark. Dark stays the
/// default, because many screens still assume it. The choice is kept on this
/// device only, in the same box as the language.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String _boxName = 'app_prefs';
  static const String _key = 'app_theme';

  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;

  /// The stored name for [mode]: `system`, `light` or `dark`.
  static String nameOf(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      };

  /// The mode for a stored name, or null when the name is not one of the three.
  static ThemeMode? modeFor(String? name) => switch (name) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => null,
      };

  /// Reads the saved choice. A missing or unknown value keeps dark.
  Future<void> load() async {
    try {
      final box = await _openBox();
      final saved = modeFor(box.get(_key) as String?);
      if (saved != null && saved != _mode) {
        _mode = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ThemeController] Could not read the theme: $e');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final box = await _openBox();
      await box.put(_key, nameOf(mode));
    } catch (e) {
      debugPrint('[ThemeController] Could not save the theme: $e');
    }
  }

  Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }
}
