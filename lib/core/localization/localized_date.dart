import 'package:intl/intl.dart';

import 'locale_controller.dart';

/// A [DateFormat] for [pattern] in the language the user chose.
///
/// Bengali month and weekday names come from intl's `bn` symbols, which
/// `main` loads with `initializeDateFormatting` before the first frame.
/// Machine formats (CSV columns, file names, storage keys) do not use this:
/// they stay fixed so exports and stored values never change with the language.
DateFormat localizedDateFormat(String pattern) =>
    DateFormat(pattern, LocaleController.instance.locale.languageCode);
