import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/meal_log.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/meal_engine.dart';

void main() {
  final month = DateTime(2026, 11, 1);

  final member1 = TourMember(
    tourId: 'mess_tour',
    email: 'fahim@example.com',
    displayName: 'Fahim',
    role: TourRole.owner,
    status: TourMemberStatus.active,
    joinedAt: DateTime(2026, 1, 1),
  );
  final member2 = TourMember(
    tourId: 'mess_tour',
    email: 'shakil@example.com',
    displayName: 'Shakil',
    role: TourRole.member,
    status: TourMemberStatus.active,
    joinedAt: DateTime(2026, 1, 1),
  );
  final member3 = TourMember(
    tourId: 'mess_tour',
    email: 'tanvir@example.com',
    displayName: 'Tanvir',
    role: TourRole.member,
    status: TourMemberStatus.active,
    joinedAt: DateTime(2026, 1, 1),
  );

  final members = [member1, member2, member3];

  group('Mess Meal Engine Calculations', () {
    test('calculates meal rate accurately and splits member balances', () {
      // 1. Logs: Fahim ate 40 meals, Shakil ate 50 meals, Tanvir ate 10 meals (Total = 100 meals)
      final logs = [
        MealLog(
            dateKey: '2026-11-01',
            email: 'fahim@example.com',
            breakfast: 1,
            lunch: 1,
            dinner: 1), // 3
        MealLog(
            dateKey: '2026-11-02',
            email: 'fahim@example.com',
            breakfast: 0,
            lunch: 2,
            dinner: 1), // 3
        // Add single aggregated records for simplicity
        MealLog(
            dateKey: '2026-11-03',
            email: 'fahim@example.com',
            breakfast: 34,
            lunch: 0,
            dinner: 0), // total 40
        MealLog(
            dateKey: '2026-11-01',
            email: 'shakil@example.com',
            breakfast: 50,
            lunch: 0,
            dinner: 0), // total 50
        MealLog(
            dateKey: '2026-11-01',
            email: 'tanvir@example.com',
            breakfast: 10,
            lunch: 0,
            dinner: 0), // total 10
      ];

      // 2. Expenses:
      // - Fahim did bazar worth ৳ 4,000 (400,000 paisa)
      // - Shakil did bazar worth ৳ 2,000 (200,000 paisa)
      // Total bazar = ৳ 6,000 (600,000 paisa)
      final expenses = [
        ExpenseItem(
          id: 'e1',
          tourId: 'mess_tour',
          title: 'Morning Bazar',
          amountPaisa: 400000,
          paidById: 'fahim@example.com',
          category: 'Groceries',
          date: DateTime(2026, 11, 2),
          addedByEmail: 'fahim@example.com',
        ),
        ExpenseItem(
          id: 'e2',
          tourId: 'mess_tour',
          title: 'Vegetables & Meat',
          amountPaisa: 200000,
          paidById: 'shakil@example.com',
          category: 'Food',
          date: DateTime(2026, 11, 5),
          addedByEmail: 'shakil@example.com',
        ),
      ];

      // 3. Deposits: Tanvir gave advance deposit of ৳ 1,500 (150,000 paisa)
      final deposits = [
        DepositItem(
          id: 'd1',
          tourId: 'mess_tour',
          memberId: 'tanvir@example.com',
          memberName: 'Tanvir',
          amountPaisa: 150000,
          date: DateTime(2026, 11, 1),
        ),
      ];

      final balance = calculateMessMonthlyBalance(
        month: month,
        members: members,
        logs: logs,
        expenses: expenses,
        deposits: deposits,
      );

      // Verify total bazar & meal rate
      // Total meals = 100
      // Total bazar = 600,000 paisa (৳ 6,000)
      // Meal rate = 6,000 / 100 = ৳ 60.00 / meal (6,000 paisa)
      expect(balance.totalMeals, 100);
      expect(balance.totalBazarPaisa, 600000);
      expect(balance.mealRatePaisa, 6000.0);
      expect(balance.mealRateTaka, 60.0);

      // Verify member shares:
      // Fahim: 40 meals * 60 = ৳ 2,400 meal cost. Contributed ৳ 4,000. Net = +৳ 1,600 (Refund)
      final fahimBal = balance.memberBalances
          .firstWhere((m) => m.email == 'fahim@example.com');
      expect(fahimBal.mealCount, 40);
      expect(fahimBal.mealCostPaisa, 240000);
      expect(fahimBal.totalContributedPaisa, 400000);
      expect(fahimBal.netBalancePaisa, 160000);
      expect(fahimBal.isRefund, isTrue);

      // Shakil: 50 meals * 60 = ৳ 3,000 meal cost. Contributed ৳ 2,000. Net = -৳ 1,000 (Due)
      final shakilBal = balance.memberBalances
          .firstWhere((m) => m.email == 'shakil@example.com');
      expect(shakilBal.mealCount, 50);
      expect(shakilBal.mealCostPaisa, 300000);
      expect(shakilBal.totalContributedPaisa, 200000);
      expect(shakilBal.netBalancePaisa, -100000);
      expect(shakilBal.isDue, isTrue);

      // Tanvir: 10 meals * 60 = ৳ 600 meal cost. Contributed ৳ 1,500. Net = +৳ 900 (Refund)
      final tanvirBal = balance.memberBalances
          .firstWhere((m) => m.email == 'tanvir@example.com');
      expect(tanvirBal.mealCount, 10);
      expect(tanvirBal.mealCostPaisa, 60000);
      expect(tanvirBal.totalContributedPaisa, 150000);
      expect(tanvirBal.netBalancePaisa, 90000);
      expect(tanvirBal.isRefund, isTrue);

      // Net conservation: Total dues = ৳ 1,000. Total refunds = 1600 + 900 = 2500 - 1500 deposit = 1000.
      expect(balance.totalDuePaisa, 100000);

      // Report generation
      final report = balance.formatReport();
      expect(report.contains('মেস মিল ও বাজার মাসিক ব্যালেন্স শিট'), isTrue);
      expect(report.contains('৳60.00'), isTrue);
      expect(report.contains('Fahim'), isTrue);
    });

    test('handles zero meals gracefully without division by zero', () {
      final balance = calculateMessMonthlyBalance(
        month: month,
        members: members,
        logs: [],
        expenses: [],
        deposits: [],
      );

      expect(balance.totalMeals, 0);
      expect(balance.mealRatePaisa, 0.0);
      expect(balance.mealRateTaka, 0.0);
      for (final m in balance.memberBalances) {
        expect(m.mealCostPaisa, 0);
        expect(m.netBalancePaisa, 0);
        expect(m.isSettled, isTrue);
      }
    });
  });
}
