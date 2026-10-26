import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:bhromon/core/localization/locale_controller.dart';
import 'package:bhromon/core/localization/localized_date.dart';

void main() {
  setUpAll(() async {
    // setLanguage saves the choice to Hive, so give Hive a directory.
    Hive.init(Directory.systemTemp.createTempSync('bhromon_date_test').path);
    await initializeDateFormatting('en');
    await initializeDateFormatting('bn');
  });

  final date = DateTime(2026, 3, 7, 14, 5);

  test('the default language is Bengali', () {
    expect(LocaleController.instance.locale.languageCode, 'bn');
  });

  test('English dates use English month names', () async {
    await LocaleController.instance.setLanguage('en');

    expect(localizedDateFormat('d MMM').format(date), '7 Mar');
    expect(localizedDateFormat('h:mm a').format(date), '2:05 PM');
  });

  test('Bengali dates use the Bengali symbols for the chosen language',
      () async {
    await LocaleController.instance.setLanguage('bn');

    expect(
      localizedDateFormat('d MMM').format(date),
      DateFormat('d MMM', 'bn').format(date),
    );
    expect(localizedDateFormat('d MMM').format(date), isNot('7 Mar'));
  });
}
