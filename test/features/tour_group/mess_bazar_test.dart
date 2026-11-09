import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/mess_bazar_model.dart';

void main() {
  group('MessBazarSchedule Model', () {
    test('creates full model and converts to and from map', () {
      final now = DateTime(2026, 11, 9, 8, 30);
      final schedule = MessBazarSchedule(
        dateKey: '2026-11-09',
        assignedEmails: ['Alice@Example.com', 'bob@test.com'],
        assignedNames: ['Alice', 'Bob'],
        note: 'Fresh fish and vegetables',
        estimatedBudgetPaisa: 50000, // 500 Taka
        isCompleted: true,
        actualExpensePaisa: 48000, // 480 Taka
        expenseId: 'exp_12345',
        updatedByEmail: 'admin@test.com',
        updatedAt: now,
      );

      expect(schedule.id, '2026-11-09');
      expect(schedule.isAssigned('alice@example.com'), isTrue);
      expect(schedule.isAssigned('BOB@test.com'), isTrue);
      expect(schedule.isAssigned('carol@test.com'), isFalse);

      final map = schedule.toMap();
      expect(map['dateKey'], '2026-11-09');
      expect(map['assignedEmails'], ['alice@example.com', 'bob@test.com']);
      expect(map['assignedNames'], ['Alice', 'Bob']);
      expect(map['note'], 'Fresh fish and vegetables');
      expect(map['estimatedBudgetPaisa'], 50000);
      expect(map['isCompleted'], isTrue);
      expect(map['actualExpensePaisa'], 48000);
      expect(map['expenseId'], 'exp_12345');
      expect(map['updatedByEmail'], 'admin@test.com');

      final reconstructed = MessBazarSchedule.fromDoc('2026-11-09', map);
      expect(reconstructed, isNotNull);
      expect(reconstructed!.dateKey, '2026-11-09');
      expect(
          reconstructed.assignedEmails, ['alice@example.com', 'bob@test.com']);
      expect(reconstructed.assignedNames, ['Alice', 'Bob']);
      expect(reconstructed.note, 'Fresh fish and vegetables');
      expect(reconstructed.estimatedBudgetPaisa, 50000);
      expect(reconstructed.isCompleted, isTrue);
      expect(reconstructed.actualExpensePaisa, 48000);
      expect(reconstructed.expenseId, 'exp_12345');
      expect(reconstructed.updatedByEmail, 'admin@test.com');
    });

    test('handles minimal/empty optional fields gracefully', () {
      const schedule = MessBazarSchedule(
        dateKey: '2026-11-10',
        assignedEmails: ['member@mess.org'],
      );

      expect(schedule.note, isNull);
      expect(schedule.estimatedBudgetPaisa, isNull);
      expect(schedule.isCompleted, isFalse);
      expect(schedule.actualExpensePaisa, isNull);
      expect(schedule.expenseId, isNull);
      expect(schedule.assignedNames, isEmpty);

      final map = schedule.toMap();
      expect(map.containsKey('note'), isFalse);
      expect(map.containsKey('estimatedBudgetPaisa'), isFalse);
      expect(map.containsKey('expenseId'), isFalse);
      expect(map['isCompleted'], isFalse);

      final reconstructed = MessBazarSchedule.fromDoc('2026-11-10', map);
      expect(reconstructed, isNotNull);
      expect(reconstructed!.dateKey, '2026-11-10');
      expect(reconstructed.assignedEmails, ['member@mess.org']);
      expect(reconstructed.note, isNull);
      expect(reconstructed.isCompleted, isFalse);
    });

    test('copyWith creates modified clone correctly', () {
      const original = MessBazarSchedule(
        dateKey: '2026-11-09',
        assignedEmails: ['user1@test.com'],
        isCompleted: false,
      );

      final modified = original.copyWith(
        isCompleted: true,
        actualExpensePaisa: 60000,
        note: 'Completed early morning bazar',
      );

      expect(modified.dateKey, '2026-11-09');
      expect(modified.assignedEmails, ['user1@test.com']);
      expect(modified.isCompleted, isTrue);
      expect(modified.actualExpensePaisa, 60000);
      expect(modified.note, 'Completed early morning bazar');
      expect(original.isCompleted, isFalse); // immutability preserved
    });

    test('fromDoc returns null on null data', () {
      expect(MessBazarSchedule.fromDoc('2026-11-09', null), isNull);
    });
  });
}
