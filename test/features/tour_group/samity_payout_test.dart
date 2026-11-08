import 'package:bhromon/features/tour_group/domain/models/samity_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SamityPayout model and verification', () {
    test('serializes and deserializes receiptUrl and verification states', () {
      final now = DateTime(2026, 11, 8, 20, 0);
      final payout = SamityPayout(
        cycle: 0,
        recipientEmail: 'alice@example.com',
        amountTaka: 15000,
        recordedByEmail: 'admin@example.com',
        receiptUrl: 'https://bhromon.fun/media/receipts/cycle0.jpg',
        isVerified: true,
        verifiedAt: now,
      );

      final fields = payout.toFields('admin@example.com');
      expect(fields['cycleKey'], '000');
      expect(fields['recipientEmail'], 'alice@example.com');
      expect(fields['amountTaka'], 15000);
      expect(fields['recordedByEmail'], 'admin@example.com');
      expect(fields['receiptUrl'],
          'https://bhromon.fun/media/receipts/cycle0.jpg');
      expect(fields['isVerified'], isTrue);
      expect(fields['verifiedAt'], isNotNull);

      final restored = SamityPayout.fromMap({
        'cycleKey': '000',
        'recipientEmail': 'alice@example.com',
        'amountTaka': 15000,
        'recordedByEmail': 'admin@example.com',
        'receiptUrl': 'https://bhromon.fun/media/receipts/cycle0.jpg',
        'isVerified': true,
        'verifiedAt': now.toIso8601String(),
      });

      expect(restored, isNotNull);
      expect(restored!.cycle, 0);
      expect(restored.recipientEmail, 'alice@example.com');
      expect(restored.amountTaka, 15000);
      expect(
          restored.receiptUrl, 'https://bhromon.fun/media/receipts/cycle0.jpg');
      expect(restored.isVerified, isTrue);
      expect(restored.verifiedAt, isNotNull);
    });

    test('defaults isVerified to false and handles omitted receiptUrl', () {
      const payout = SamityPayout(
        cycle: 1,
        recipientEmail: 'bob@example.com',
        amountTaka: 15000,
      );

      expect(payout.isVerified, isFalse);
      expect(payout.receiptUrl, isNull);
      expect(payout.verifiedAt, isNull);

      final fields = payout.toFields('admin@example.com');
      expect(fields.containsKey('receiptUrl'), isFalse);
      expect(fields['isVerified'], isFalse);
      expect(fields.containsKey('verifiedAt'), isFalse);

      final restored = SamityPayout.fromMap({
        'cycleKey': '001',
        'recipientEmail': 'bob@example.com',
        'amountTaka': 15000,
      });

      expect(restored, isNotNull);
      expect(restored!.isVerified, isFalse);
      expect(restored.receiptUrl, isNull);
    });
  });
}
