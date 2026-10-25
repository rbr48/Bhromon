import 'dart:io';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/localization/locale_controller.dart';
import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = TourTranslationKeys.localizedValues['en']!;
  final bn = TourTranslationKeys.localizedValues['bn']!;

  group('tour translation table', () {
    test('every key exists in both languages', () {
      expect(bn.keys.toSet(), equals(en.keys.toSet()));
    });

    test('no translation is blank', () {
      for (final text in [...en.values, ...bn.values]) {
        expect(text.trim(), isNotEmpty);
      }
    });

    test('both languages use the same placeholders', () {
      final placeholder = RegExp(r'\{(\w+)\}');
      for (final key in en.keys) {
        final english =
            placeholder.allMatches(en[key]!).map((m) => m.group(1)).toSet();
        final bengali =
            placeholder.allMatches(bn[key]!).map((m) => m.group(1)).toSet();
        expect(bengali, equals(english),
            reason: 'placeholders differ for $key');
      }
    });

    test('every key the tour screens use has both translations', () {
      final use = RegExp(r"translate\(\s*'([a-z_]+)'");
      final keys = <String>{};
      final files = Directory('lib/features/tour_group/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        for (final match in use.allMatches(file.readAsStringSync())) {
          keys.add(match.group(1)!);
        }
      }
      expect(keys, isNotEmpty);
      for (final key in keys) {
        expect(en.containsKey(key), isTrue, reason: 'no English for $key');
        expect(bn.containsKey(key), isTrue, reason: 'no Bengali for $key');
      }
    });
  });

  group('AppLocalizations.translate', () {
    test('uses the language asked for', () {
      expect(
          AppLocalizations(const Locale('en')).translate('tour_save'), 'Save');
      expect(AppLocalizations(const Locale('bn')).translate('tour_save'),
          'সংরক্ষণ');
    });

    test('fills placeholders with the given values', () {
      expect(
        AppLocalizations(const Locale('en')).translate(
            'tour_seats_booked_count',
            args: {'booked': 3, 'total': 36}),
        'Booked: 3 / 36',
      );
      expect(
        AppLocalizations(const Locale('bn'))
            .translate('tour_seat_label', args: {'number': 'A1'}),
        'সিট A1',
      );
    });

    test('falls back to English, then to the key itself', () {
      expect(
          AppLocalizations(const Locale('fr')).translate('tour_save'), 'Save');
      expect(AppLocalizations(const Locale('bn')).translate('no_such_key'),
          'no_such_key');
    });
  });

  group('LocaleController', () {
    test('supports only Bengali and English', () {
      expect(LocaleController.isSupported('bn'), isTrue);
      expect(LocaleController.isSupported('en'), isTrue);
      expect(LocaleController.isSupported('fr'), isFalse);
    });

    test('starts in Bengali, the existing default', () {
      expect(LocaleController.instance.locale.languageCode, 'bn');
    });
  });
}
