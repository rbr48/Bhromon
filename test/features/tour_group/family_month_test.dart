import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/services/fund_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

ExpenseItem _exp(String id, DateTime date) => ExpenseItem(
      id: id,
      tourId: 'f',
      title: id,
      amountPaisa: 10000,
      paidById: 'a@x.com',
      paidByName: 'Asha',
      category: 'Groceries',
      date: date,
      splitMode: SplitMode.family,
    );

void main() {
  group('expensesInMonth', () {
    final october = DateTime(2026, 10);
    final expenses = [
      _exp('first', DateTime(2026, 10, 1)),
      _exp('last', DateTime(2026, 10, 31, 23, 59)),
      _exp('next', DateTime(2026, 11, 1)),
      _exp('last-year', DateTime(2025, 10, 15)),
    ];

    test('keeps the expenses of the month, whatever the day', () {
      expect(expensesInMonth(expenses, october).map((e) => e.id).toList(),
          ['first', 'last']);
    });

    test('a month with nothing spent is empty', () {
      expect(expensesInMonth(expenses, DateTime(2026, 9)), isEmpty);
    });

    test('December and January of the next year are different months', () {
      final december = [_exp('dec', DateTime(2026, 12, 31))];
      expect(expensesInMonth(december, DateTime(2027, 1)), isEmpty);
      expect(expensesInMonth(december, DateTime(2026, 12)), hasLength(1));
    });
  });

  test('monthOf drops the day and the time', () {
    expect(monthOf(DateTime(2026, 10, 31, 22, 5)), DateTime(2026, 10));
  });
}
