import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/app_logger.dart';

/// The language the user picked for the whole app. Bengali stays the default,
/// as it always was. The choice is kept on this device only.
class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const List<String> supportedLanguages = ['bn', 'en'];
  static const String _boxName = 'app_prefs';
  static const String _key = 'app_language';

  Locale _locale = const Locale('bn');

  Locale get locale => _locale;

  static bool isSupported(String code) => supportedLanguages.contains(code);

  /// Reads the saved choice. A missing or unknown value keeps Bengali.
  Future<void> load() async {
    try {
      final box = await _openBox();
      final saved = box.get(_key);
      if (saved is String && isSupported(saved)) {
        _locale = Locale(saved);
        notifyListeners();
      }
    } catch (e, st) {
      logWarning('[LocaleController] Could not read the language', e, st);
    }
  }

  Future<void> setLanguage(String code) async {
    if (!isSupported(code) || code == _locale.languageCode) return;
    _locale = Locale(code);
    notifyListeners();
    try {
      final box = await _openBox();
      await box.put(_key, code);
    } catch (e, st) {
      logWarning('[LocaleController] Could not save the language', e, st);
    }
  }

  Future<Box<dynamic>> _openBox() async {
    try {
      if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
      return await Hive.openBox<dynamic>(_boxName);
    } catch (e, st) {
      logWarning(
          '[LocaleController] Corrupt preferences box: $e. Re-initializing...', e, st);
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        return await Hive.openBox<dynamic>(_boxName);
      } catch (_) {
        rethrow;
      }
    }
  }
}
