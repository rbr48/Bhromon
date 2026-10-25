import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/services/tide_schedule_engine.dart';

void main() {
  group('TideWindow', () {
    test('contains handles windows that run past midnight', () {
      const night = TideWindow(
        name: 'night',
        startMinutes: 1380, // 23:00
        endMinutes: 60, // 01:00 next day
        type: TideType.low,
        description: '',
      );
      expect(night.contains(1400), isTrue);
      expect(night.contains(30), isTrue);
      expect(night.contains(120), isFalse);
      expect(night.contains(1000), isFalse);
    });

    test('contains handles a normal daytime window', () {
      const noon = TideWindow(
        name: 'noon',
        startMinutes: 650,
        endMinutes: 870,
        type: TideType.low,
        description: '',
      );
      expect(noon.contains(650), isTrue);
      expect(noon.contains(870), isTrue);
      expect(noon.contains(649), isFalse);
      expect(noon.contains(871), isFalse);
    });
  });

  group('TideScheduleEngine', () {
    test('marks times as estimates', () {
      expect(TideScheduleEngine.isEstimate, isTrue);
    });

    test('the curated day returns its own windows', () {
      final tides =
          TideScheduleEngine.getTidesForDate(DateTime(2026, 10, 24, 12));
      expect(tides.first.startMinutes, 320);
      expect(tides.length, 4);
    });

    test('a daytime low tide is reported as danger, with the estimate wording',
        () {
      final result = TideScheduleEngine.evaluateCurrentSafety(
          DateTime(2026, 10, 24, 12, 0));
      expect(result.status, SwimSafetyStatus.danger);
      expect(result.advisory, contains('আনুমানিক'));
      expect(result.currentWindow?.type, TideType.low);
    });

    test('the next window after a morning high tide is the noon low tide', () {
      final result = TideScheduleEngine.evaluateCurrentSafety(
          DateTime(2026, 10, 24, 7, 0));
      expect(result.status, SwimSafetyStatus.safe);
      expect(result.nextWindow?.startMinutes, 650);
    });

    test(
        'after the last window of the day the next window is tomorrow\'s first',
        () {
      final tomorrow =
          TideScheduleEngine.getTidesForDate(DateTime(2026, 10, 25));
      final result = TideScheduleEngine.evaluateCurrentSafety(
          DateTime(2026, 10, 24, 23, 30));
      expect(result.nextWindow, isNotNull);
      expect(result.nextWindow!.startMinutes, tomorrow.first.startMinutes);
    });

    test('evening and night are always danger, whatever the tide', () {
      final result = TideScheduleEngine.evaluateCurrentSafety(
          DateTime(2026, 10, 24, 19, 0));
      expect(result.status, SwimSafetyStatus.danger);
    });

    test('generated days are unaffected by the time of day they are asked at',
        () {
      final morning =
          TideScheduleEngine.getTidesForDate(DateTime(2026, 10, 30, 1));
      final evening =
          TideScheduleEngine.getTidesForDate(DateTime(2026, 10, 30, 22));
      expect(morning.map((t) => t.startMinutes).toList(),
          evening.map((t) => t.startMinutes).toList());
    });
  });
}
