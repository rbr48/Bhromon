import 'package:flutter/material.dart';
import 'translation_keys.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  String translate(String key) {
    final values = TranslationKeys.localizedValues[locale.languageCode];
    if (values != null && values.containsKey(key)) {
      return values[key]!;
    }
    // Fallback to English
    final enValues = TranslationKeys.localizedValues['en'];
    if (enValues != null && enValues.containsKey(key)) {
      return enValues[key]!;
    }
    return key;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
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
  AppLocalizations get l10n => AppLocalizations.of(this) ?? AppLocalizations(const Locale('en'));
}
