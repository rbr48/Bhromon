import 'package:flutter/widgets.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../domain/models/tour_group.dart';

/// Day numbers for a day picker: the tour's days, plus [current] so a post
/// saved on a day the tour no longer lists still has a matching item.
List<int> instafeedDayNumbers(List<TourDayInfo> days, String current) {
  final numbers = <int>{for (final d in days) d.dayNumber};
  if (numbers.isEmpty) numbers.addAll([1, 2, 3, 4, 5]);
  final currentNumber = int.tryParse(current.replaceAll(RegExp(r'[^0-9]'), ''));
  if (currentNumber != null) numbers.add(currentNumber);
  return numbers.toList()..sort();
}

/// The picker value for a day number, such as `day3`.
String instafeedDayId(int dayNumber) => 'day$dayNumber';

/// "Day 3" in English, "দিন ৩" in Bengali.
String instafeedDayLabel(BuildContext context, int dayNumber) =>
    context.l10n.translate('ig_day_n', args: {'n': dayNumber});
