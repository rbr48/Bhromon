import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/data/mess_meal_sheet_pdf.dart';
import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/meal_log.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/meal_engine.dart';

int _pageCount(Uint8List bytes) {
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final month = DateTime(2026, 11, 1);

  final group = TourGroup(
    id: 'mess-1',
    name: 'Bachelor Mess Gulshan',
    ownerEmail: 'admin@example.com',
    inviteCode: 'MESS123',
    preset: TourGroup.messPreset,
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 12, 31),
    createdAt: DateTime(2026, 1, 1),
  );

  final members = [
    TourMember(
      tourId: 'mess-1',
      email: 'fahim@example.com',
      displayName: 'Fahim Ahmed',
      role: TourRole.owner,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026, 1, 1),
    ),
    TourMember(
      tourId: 'mess-1',
      email: 'shakil@example.com',
      displayName: 'Shakil Khan',
      role: TourRole.member,
      status: TourMemberStatus.active,
      joinedAt: DateTime(2026, 1, 1),
    ),
  ];

  final logs = [
    const MealLog(
      dateKey: '2026-11-01',
      email: 'fahim@example.com',
      breakfast: 1,
      lunch: 1,
      dinner: 1,
    ),
    const MealLog(
      dateKey: '2026-11-02',
      email: 'fahim@example.com',
      breakfast: 1,
      lunch: 1,
      dinner: 0,
    ),
    const MealLog(
      dateKey: '2026-11-01',
      email: 'shakil@example.com',
      breakfast: 0,
      lunch: 1,
      dinner: 1,
    ),
  ];

  final expenses = [
    ExpenseItem(
      id: 'e1',
      tourId: 'mess-1',
      title: 'Bazar Fish & Rice',
      amountPaisa: 60000,
      paidById: 'fahim@example.com',
      category: 'Groceries',
      date: DateTime(2026, 11, 2),
    ),
  ];

  final deposits = [
    DepositItem(
      id: 'd1',
      tourId: 'mess-1',
      memberId: 'shakil@example.com',
      memberName: 'Shakil Khan',
      amountPaisa: 30000,
      date: DateTime(2026, 11, 1),
    ),
  ];

  test('buildMessMealSheetPdf generates valid 2-page PDF document with logs',
      () async {
    final balance = calculateMessMonthlyBalance(
      month: month,
      members: members,
      logs: logs,
      expenses: expenses,
      deposits: deposits,
    );

    final data = MessMealSheetData(
      group: group,
      month: month,
      balance: balance,
      dailyLogs: logs,
      generatedAt: DateTime(2026, 11, 8),
    );

    final bytes = await buildMessMealSheetPdf(data: data);

    expect(bytes, isNotEmpty);
    // Starts with %PDF
    expect(bytes[0], 0x25);
    expect(bytes[1], 0x50);
    expect(bytes[2], 0x44);
    expect(bytes[3], 0x46);

    // Has 2 pages (Page 1: Summary, Page 2: 31-day log matrix)
    expect(_pageCount(bytes), 2);
  });
}
