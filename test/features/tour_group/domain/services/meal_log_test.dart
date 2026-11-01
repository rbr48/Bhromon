import 'package:bhromon/features/tour_group/domain/models/meal_log.dart';
import 'package:bhromon/features/tour_group/domain/services/meal_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('meal log', () {
    test('the id joins the day and the member, and the total adds the meals',
        () {
      const log = MealLog(
        dateKey: '2026-11-01',
        email: 'a@example.com',
        breakfast: 1,
        lunch: 2,
        dinner: 1,
      );

      expect(log.id, '2026-11-01__a@example.com');
      expect(log.total, 4);
    });

    test('a stored day reads its counts and keeps each one within the limit',
        () {
      final log = MealLog.fromMap({
        'dateKey': '2026-11-01',
        'email': 'a@example.com',
        'breakfast': 9,
        'lunch': -3,
        'dinner': 'two',
      });

      expect(log, isNotNull);
      expect(log!.breakfast, kMaxMealsPerSlot);
      expect(log.lunch, 0);
      expect(log.dinner, 0);
    });

    test('a record with no day or no member is skipped', () {
      expect(
          MealLog.fromMap({'email': 'a@example.com', 'breakfast': 1}), isNull);
      expect(
          MealLog.fromMap({'dateKey': '2026-11-01', 'breakfast': 1}), isNull);
      expect(
          MealLog.fromMap({'dateKey': '', 'email': 'a@example.com'}), isNull);
    });

    test('the fields a member writes name the day, the member and the writer',
        () {
      const log = MealLog(
        dateKey: '2026-11-01',
        email: 'a@example.com',
        dinner: 2,
      );

      expect(log.toFields('admin@example.com'), {
        'dateKey': '2026-11-01',
        'email': 'a@example.com',
        'breakfast': 0,
        'lunch': 0,
        'dinner': 2,
        'updatedByEmail': 'admin@example.com',
      });
    });
  });

  group('meal engine', () {
    test('a day key pads the month and the day', () {
      expect(mealDateKey(DateTime(2026, 3, 7)), '2026-03-07');
    });

    test('a month runs from its first day to its last, leap years included',
        () {
      expect(mealMonthFirstKey(DateTime(2026, 11, 15)), '2026-11-01');
      expect(mealMonthLastKey(DateTime(2026, 11, 15)), '2026-11-30');
      expect(mealMonthLastKey(DateTime(2028, 2, 10)), '2028-02-29');
      expect(mealDaysInMonth(DateTime(2027, 2, 1)), 28);
    });

    test('totals add each member\'s meals over the month, skipping empty days',
        () {
      final totals = mealTotalsByEmail(const [
        MealLog(
            dateKey: '2026-11-01',
            email: 'a@example.com',
            breakfast: 1,
            lunch: 1,
            dinner: 1),
        MealLog(dateKey: '2026-11-02', email: 'a@example.com', lunch: 2),
        MealLog(dateKey: '2026-11-01', email: 'b@example.com'),
      ]);

      expect(totals, {'a@example.com': 5});
    });
  });
}
