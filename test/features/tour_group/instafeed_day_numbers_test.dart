import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/instafeed_day_label.dart';
import 'package:flutter_test/flutter_test.dart';

TourDayInfo _day(int n) => TourDayInfo(
      id: 'day$n',
      dayNumber: n,
      date: DateTime(2026, 10, n),
      label: 'Day $n',
    );

void main() {
  group('instafeedDayNumbers', () {
    test('offers the tour days', () {
      final days = [for (var n = 1; n <= 7; n++) _day(n)];

      expect(instafeedDayNumbers(days, 'day2'), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('keeps a post on a day past the tour so its dropdown value exists',
        () {
      final days = [for (var n = 1; n <= 3; n++) _day(n)];

      expect(instafeedDayNumbers(days, 'day6'), [1, 2, 3, 6]);
    });

    test('falls back to five days when the tour has no days yet', () {
      expect(instafeedDayNumbers(const [], 'day1'), [1, 2, 3, 4, 5]);
    });

    test('day ids match the stored values', () {
      expect(instafeedDayId(4), 'day4');
    });
  });
}
