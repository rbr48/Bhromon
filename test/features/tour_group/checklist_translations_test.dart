import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/presentation/pages/tour_checklist_screen.dart';

void main() {
  final en = TourTranslationKeys.localizedValues['en']!;
  final bn = TourTranslationKeys.localizedValues['bn']!;

  test('every default item and category has both translations', () {
    for (final item in checklistDefaultItems) {
      for (final key in [item.title, item.category]) {
        expect(en.containsKey(key), isTrue, reason: 'no English for $key');
        expect(bn.containsKey(key), isTrue, reason: 'no Bengali for $key');
      }
    }
    expect(en.containsKey('check_cat_custom'), isTrue);
    expect(bn.containsKey('check_cat_custom'), isTrue);
  });

  test('the default items keep their saved positions', () {
    // Each item's index is its saved id (default_0 ... default_17), so ticks
    // already saved depend on this order.
    expect(checklistDefaultItems, hasLength(18));
    expect(checklistDefaultItems.first.title, 'check_item_id_copy');
    expect(checklistDefaultItems.last.title, 'check_item_umbrella_hat');
  });
}
