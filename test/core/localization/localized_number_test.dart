import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/localization/app_localizations.dart';

void main() {
  test('Bengali writes numbers with Bengali digits', () {
    final bn = AppLocalizations(const Locale('bn'));
    expect(bn.number(2026), '২০২৬');
    expect(bn.number(0), '০');
    expect(bn.number(-15), '-১৫');
  });

  test('English keeps Western digits', () {
    expect(AppLocalizations(const Locale('en')).number(2026), '2026');
  });
}
