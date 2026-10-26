import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';

void main() {
  final when = DateTime(2026, 10, 25, 9, 30);

  group('SplitMode', () {
    test('reads a stored name and falls back to family', () {
      expect(SplitMode.fromString('exact'), SplitMode.exact);
      expect(SplitMode.fromString('shares'), SplitMode.shares);
      expect(SplitMode.fromString('equal'), SplitMode.equal);
      expect(SplitMode.fromString('unknown'), SplitMode.family);
      expect(SplitMode.fromString(null), SplitMode.family);
    });
  });

  group('ExpenseItem', () {
    test('round-trips every field, with emails normalised', () {
      final item = ExpenseItem(
        id: 'e1',
        tourId: 't1',
        title: 'Lunch',
        amountPaisa: 123450,
        paidById: ' Rina@Example.com ',
        paidByName: 'Rina',
        category: 'Food',
        date: when,
        notes: 'Good fish',
        addedByEmail: 'Asha@Example.com',
        participantIds: const ['Rina@Example.com', 'Babu@Example.com'],
        splitMode: SplitMode.exact,
        splitShares: const {
          'Rina@Example.com': 60000,
          'Babu@Example.com': 63450
        },
        stopId: 'main',
        currency: 'INR',
        originalMinor: 9000,
        fxRate: 1.37,
      );

      final back = ExpenseItem.fromMap('e1', item.toMap());

      expect(back.title, 'Lunch');
      expect(back.amountPaisa, 123450);
      expect(back.amountTaka, closeTo(1234.5, 0.001));
      expect(back.paidById, 'rina@example.com');
      expect(back.addedByEmail, 'asha@example.com');
      expect(back.participantIds, ['rina@example.com', 'babu@example.com']);
      expect(back.splitMode, SplitMode.exact);
      expect(back.splitShares, {
        'rina@example.com': 60000,
        'babu@example.com': 63450,
      });
      expect(back.stopId, 'main');
      expect(back.currency, 'INR');
      expect(back.originalMinor, 9000);
      expect(back.fxRate, 1.37);
      expect(back.isForeign, isTrue);
      expect(back.date.isAtSameMomentAs(when), isTrue);
    });

    test('reads the older amount field in taka and fills defaults', () {
      final item = ExpenseItem.fromMap('old', {
        'amount': 12.5,
        'date': when.toIso8601String(),
        'paidBy': 'Rina',
        'participantIds': <String>[],
      });

      expect(item.amountPaisa, 1250);
      expect(item.title, 'Expense');
      expect(item.category, 'Others');
      expect(item.paidById, isNull);
      expect(item.paidByName, 'Rina');
      expect(item.splitMode, SplitMode.family);
      expect(item.participantIds, isEmpty);
      expect(item.isForeign, isFalse);
    });

    test('a BDT expense is not foreign, and an empty payer is no payer', () {
      final item = ExpenseItem.fromMap('b', {
        'amountPaisa': 500,
        'currency': 'BDT',
        'paidById': '',
        'date': when.toIso8601String(),
      });

      expect(item.isForeign, isFalse);
      expect(item.paidById, isNull);
    });
  });

  group('DepositItem', () {
    test('round-trips and reads the older amount field', () {
      final deposit = DepositItem(
        id: 'd1',
        tourId: 't1',
        memberId: ' Rina@Example.com',
        memberName: 'Rina',
        amountPaisa: 250000,
        date: when,
        notes: 'First instalment',
        addedByEmail: 'Asha@Example.com',
      );

      final back = DepositItem.fromMap('d1', deposit.toMap());

      expect(back.memberId, 'rina@example.com');
      expect(back.amountPaisa, 250000);
      expect(back.amountTaka, 2500);
      expect(back.addedByEmail, 'asha@example.com');
      expect(back.notes, 'First instalment');

      final legacy = DepositItem.fromMap('d2', {
        'amount': 100.25,
        'date': when.toIso8601String(),
      });
      expect(legacy.amountPaisa, 10025);
      expect(legacy.memberName, 'Member');
    });
  });

  group('TransferItem', () {
    test('a null id is the fund on either side', () {
      final payOut = TransferItem(
        id: 'x1',
        tourId: 't1',
        fromName: 'Fund',
        toId: 'rina@example.com',
        toName: 'Rina',
        amountPaisa: 4000,
        date: when,
      );
      final payIn = TransferItem(
        id: 'x2',
        tourId: 't1',
        fromId: 'babu@example.com',
        fromName: 'Babu',
        toName: 'Fund',
        amountPaisa: 4000,
        date: when,
      );

      expect(payOut.fromFund, isTrue);
      expect(payOut.toFund, isFalse);
      expect(payIn.fromFund, isFalse);
      expect(payIn.toFund, isTrue);
    });

    test('round-trips, and empty ids read as the fund', () {
      final transfer = TransferItem(
        id: 'x1',
        tourId: 't1',
        fromId: 'Babu@Example.com',
        fromName: 'Babu',
        toId: 'Rina@Example.com',
        toName: 'Rina',
        amountPaisa: 4000,
        date: when,
        notes: 'Settled',
      );

      final back = TransferItem.fromMap('x1', transfer.toMap());
      expect(back.fromId, 'babu@example.com');
      expect(back.toId, 'rina@example.com');
      expect(back.amountPaisa, 4000);
      expect(back.notes, 'Settled');

      final fromFund = TransferItem.fromMap('x3', {
        'fromId': '',
        'toId': null,
        'date': when.toIso8601String(),
      });
      expect(fromFund.fromId, isNull);
      expect(fromFund.fromFund, isTrue);
      expect(fromFund.toFund, isTrue);
    });
  });

  group('FundBudget', () {
    test('totals its categories and reports when it is empty', () {
      const budget = FundBudget(
        categoryPaisa: {'Food': 500000, 'Transport': 250000},
        perHeadTargetPaisa: 100000,
      );

      expect(budget.totalPaisa, 750000);
      expect(budget.isEmpty, isFalse);
      expect(const FundBudget().isEmpty, isTrue);
    });

    test('keeps only positive numeric categories when reading', () {
      final budget = FundBudget.fromMap({
        'categoryPaisa': {
          'Food': 500,
          'Hotel': 0,
          'Tickets': -20,
          'Other': 'x'
        },
        'perHeadTargetPaisa': 3000,
      });

      expect(budget.categoryPaisa, {'Food': 500});
      expect(budget.perHeadTargetPaisa, 3000);
      expect(
        FundBudget.fromMap(budget.toMap()).categoryPaisa,
        {'Food': 500},
      );
    });

    test('a value that is not a map reads as an empty budget', () {
      expect(FundBudget.fromMap(null).isEmpty, isTrue);
      expect(FundBudget.fromMap('budget').isEmpty, isTrue);
    });
  });
}
