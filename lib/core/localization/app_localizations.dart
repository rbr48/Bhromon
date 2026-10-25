import 'package:flutter/material.dart';
import 'tour_translation_keys.dart';
import 'translation_keys.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// Looks up [key] in this language, then in English, then returns the key
  /// itself. Each `{name}` in the text is replaced with `args['name']`.
  String translate(String key, {Map<String, Object> args = const {}}) {
    final text = _lookup(locale.languageCode, key) ?? _lookup('en', key) ?? key;
    var filled = text;
    for (final entry in args.entries) {
      filled = filled.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return filled;
  }

  static String? _lookup(String languageCode, String key) {
    return TranslationKeys.localizedValues[languageCode]?[key] ??
        TourTranslationKeys.localizedValues[languageCode]?[key];
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'bn'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}

extension AppLocalizationsExtension on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizations(const Locale('en'));
}
