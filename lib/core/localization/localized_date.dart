import 'package:intl/intl.dart';

import 'locale_controller.dart';

/// A date formatter for [pattern] in the language the user chose.
///
/// Bengali month and weekday names come from intl's `bn` symbols, which
/// `main` loads with `initializeDateFormatting` before the first frame.
/// When in Bengali, English AM/PM markers in 12-hour timestamps are cleanly
/// translated into standard Bengali ('পূর্বাহ্ন' / 'অপরাহ্ন') so English letters
/// are never mixed into Bengali date strings.
class AppDateFormatter {
  final DateFormat _df;
  final bool _isBn;

  const AppDateFormatter(this._df, this._isBn);

  /// Formats [date] according to the pattern and current locale.
  String format(DateTime date) {
    var str = _df.format(date);
    if (_isBn) {
      if (str.endsWith(' AM')) {
        str = '${str.substring(0, str.length - 3)} পূর্বাহ্ন';
      } else if (str.endsWith(' PM')) {
        str = '${str.substring(0, str.length - 3)} অপরাহ্ন';
      } else if (str.contains(' AM')) {
        str = str.replaceAll(' AM', ' পূর্বাহ্ন');
      } else if (str.contains(' PM')) {
        str = str.replaceAll(' PM', ' অপরাহ্ন');
      } else if (str.contains('AM')) {
        str = str.replaceAll('AM', 'পূর্বাহ্ন');
      } else if (str.contains('PM')) {
        str = str.replaceAll('PM', 'অপরাহ্ন');
      }
    }
    return str;
  }

  String? get pattern => _df.pattern;
  DateFormat get raw => _df;
}

AppDateFormatter localizedDateFormat(String pattern) {
  final language = LocaleController.instance.locale.languageCode;
  final isBn = language == 'bn';
  try {
    return AppDateFormatter(DateFormat(pattern, language), isBn);
  } on Exception {
    return AppDateFormatter(DateFormat(pattern), false);
  }
}
