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

  ThemeMode get mode => ThemeMode.dark;

  /// The stored name for [mode]: always `dark`.
  static String nameOf(ThemeMode mode) => 'dark';

  /// The mode for a stored name, or null when the name is not one of the three.
  static ThemeMode? modeFor(String? name) => ThemeMode.dark;

  /// Reads the saved choice. Bhromon enforces dark theme.
  Future<void> load() async {
    _mode = ThemeMode.dark;
    try {
      final box = await _openBox();
      await box.put(_key, 'dark');
    } catch (e) {
      debugPrint('[ThemeController] Could not set dark theme: $e');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = ThemeMode.dark;
    notifyListeners();
  }

  Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return Hive.openBox<dynamic>(_boxName);
  }
}
