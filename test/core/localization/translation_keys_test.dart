import 'package:bhromon/core/localization/translation_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = TranslationKeys.localizedValues['en']!;
  final bn = TranslationKeys.localizedValues['bn']!;

  test('every key exists in both languages', () {
    expect(bn.keys.toSet(), equals(en.keys.toSet()));
  });

  test('no translation is blank, except the open end of a split sentence', () {
    // A `_prefix` or `_suffix` may be empty: a sentence is built from its
    // parts, and in one language a name has nothing before or after it.
    bool isFragment(String key) =>
        key.endsWith('_prefix') || key.endsWith('_suffix');
    for (final table in [en, bn]) {
      for (final entry in table.entries) {
        if (isFragment(entry.key)) continue;
        expect(entry.value.trim(), isNotEmpty, reason: 'blank ${entry.key}');
      }
    }
  });

  test('both languages use the same placeholders', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final key in en.keys) {
      final english =
          placeholder.allMatches(en[key]!).map((m) => m.group(1)).toSet();
      final bengali =
          placeholder.allMatches(bn[key]!).map((m) => m.group(1)).toSet();
      expect(bengali, equals(english), reason: 'placeholders differ for $key');
    }
  });

  test('sign-in errors have both translations', () {
    for (final key in const [
      'auth_error_network',
      'auth_error_google_play_services',
      'auth_error_popup_blocked',
      'auth_privacy_open_failed',
      'error_generic',
    ]) {
      expect(en.containsKey(key), isTrue, reason: 'no English for $key');
      expect(bn.containsKey(key), isTrue, reason: 'no Bengali for $key');
    }
  });

  test('the Google Play services fix names the service in English', () {
    expect(
      en['auth_error_google_play_services'],
      contains('Google Play services'),
    );
  });
}
