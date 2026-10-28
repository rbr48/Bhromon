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
  ///
  /// In Bengali, numeric arguments (`is num` or numeric string for count/n/etc)
  /// are automatically converted to Bengali digits so English numerals are
  /// never mixed into Bengali copy.
  String translate(String key, {Map<String, Object> args = const {}}) {
    final text = _lookup(locale.languageCode, key) ?? _lookup('en', key) ?? key;
    var filled = text;
    for (final entry in args.entries) {
      final value = entry.value;
      final String formatted;
      if (locale.languageCode == 'bn') {
        if (value is num) {
          formatted = number(value);
        } else if (value is String && _shouldLocalizeDigits(entry.key, value)) {
          formatted = number(value);
        } else {
          formatted = '$value';
        }
      } else {
        formatted = '$value';
      }
      filled = filled.replaceAll('{${entry.key}}', formatted);
    }
    return filled;
  }

  static bool _shouldLocalizeDigits(String key, String value) {
    const numericKeys = {
      'count',
      'n',
      'amount',
      'total',
      'current',
      'max',
      'seat',
      'room',
      'days',
      'nights',
      'page',
      'value',
      'views',
    };
    if (!numericKeys.contains(key)) return false;
    return int.tryParse(value) != null;
  }

  /// [n] written with this language's digits: Bengali digits in Bengali,
  /// Western digits otherwise. Accepts [int], [num], or numeric [String].
  String number(Object n) {
    final text = '$n';
    if (locale.languageCode != 'bn') return text;
    const bengaliDigits = '০১২৩৪৫৬৭৮৯';
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      final digit = unit - 0x30;
      out.write(digit >= 0 && digit <= 9
          ? bengaliDigits[digit]
          : String.fromCharCode(unit));
    }
    return out.toString();
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
