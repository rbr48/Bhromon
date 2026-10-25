import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/theme/theme_controller.dart';

void main() {
  test('every mode round-trips through its stored name', () {
    for (final mode in ThemeMode.values) {
      expect(ThemeController.modeFor(ThemeController.nameOf(mode)), mode);
    }
  });

  test('stored names are the three words the settings screen writes', () {
    expect(ThemeController.nameOf(ThemeMode.system), 'system');
    expect(ThemeController.nameOf(ThemeMode.light), 'light');
    expect(ThemeController.nameOf(ThemeMode.dark), 'dark');
  });

  test('a missing or unknown stored value is not a mode', () {
    expect(ThemeController.modeFor(null), isNull);
    expect(ThemeController.modeFor('sepia'), isNull);
    expect(ThemeController.modeFor(''), isNull);
  });

  test('before anything is loaded the app stays dark', () {
    expect(ThemeController.instance.mode, ThemeMode.dark);
  });
}
