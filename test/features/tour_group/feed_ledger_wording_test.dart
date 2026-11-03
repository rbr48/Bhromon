import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// The feed's add-to-ledger wording is shared by every kind of group, so these
/// strings must not name a trip or a tour in either language.
void main() {
  final en = TourTranslationKeys.localizedValues['en']!;
  final bn = TourTranslationKeys.localizedValues['bn']!;
  final tripOrTour = RegExp(r'trip|tour|ট্রিপ|ট্যুর', caseSensitive: false);

  const feedLedgerKeys = [
    'ig_add_to_ledger',
    'ig_add_as_expense',
    'ig_trip_expense',
    'ig_expense_added',
  ];

  for (final key in feedLedgerKeys) {
    test('$key names no trip or tour in English or Bengali', () {
      expect(en[key], isNotNull, reason: 'no English for $key');
      expect(bn[key], isNotNull, reason: 'no Bengali for $key');
      expect(tripOrTour.hasMatch(en[key]!), isFalse, reason: en[key]);
      expect(tripOrTour.hasMatch(bn[key]!), isFalse, reason: bn[key]);
    });
  }
}
