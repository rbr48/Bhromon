import 'package:bhromon/features/tour_group/domain/services/bangla_qr_engine.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/bangla_qr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BanglaQrEngine', () {
    test('generate builds dynamic payload when amount is provided', () {
      const payload = BanglaQrPayload(
        accountNumber: '01711000000',
        payeeName: 'Alice Rahman',
        provider: BanglaQrProvider.bkash,
        amountTaka: 1500,
        reference: 'Trek Expense',
      );

      final qr = BanglaQrEngine.generate(payload);

      expect(qr, startsWith('000201010212')); // Dynamic
      expect(qr, contains('5303050')); // BDT Currency
      expect(qr, contains('54071500.00')); // Amount 1500.00
      expect(qr, contains('5802BD')); // Country BD
      expect(qr, contains('5912Alice Rahman')); // Payee
      expect(qr, contains('6005Dhaka')); // City Dhaka
      expect(qr, contains('62160112Trek Expense')); // Reference
      expect(qr, contains('6304')); // CRC Tag

      // Verify CRC length and checksum integrity
      final crcStr = qr.substring(qr.length - 4);
      expect(RegExp(r'^[0-9A-F]{4}$').hasMatch(crcStr), isTrue);

      final payloadToCrc = qr.substring(0, qr.length - 4);
      final computedCrc = BanglaQrEngine.calculateCrc16(payloadToCrc)
          .toRadixString(16)
          .toUpperCase()
          .padLeft(4, '0');
      expect(crcStr, equals(computedCrc));
    });

    test('generate builds static payload when amount is omitted', () {
      const payload = BanglaQrPayload(
        accountNumber: '01811000000',
        payeeName: 'Bob Ahmed',
        provider: BanglaQrProvider.nagad,
      );

      final qr = BanglaQrEngine.generate(payload);

      expect(qr, startsWith('000201010211')); // Static initiation
      expect(qr, isNot(contains('540'))); // No amount tag
      expect(qr, contains('NAGAD')); // Provider
      expect(qr, contains('6304')); // CRC
    });

    test('generate strips spaces from account numbers and limits name length',
        () {
      const payload = BanglaQrPayload(
        accountNumber: ' 0191 123 4567 ',
        payeeName: 'Very Long Name That Exceeds Twenty Five Characters Easily',
        provider: BanglaQrProvider.rocket,
      );

      final qr = BanglaQrEngine.generate(payload);

      expect(qr, contains('011101911234567'));
      // Truncated to 25 chars
      expect(qr, contains('5925Very Long Name That Excee'));
    });
  });

  group('BanglaQrView Widget', () {
    testWidgets('renders BanglaQrView cleanly without error', (tester) async {
      const payload = BanglaQrPayload(
        accountNumber: '01700000000',
        payeeName: 'Test Payee',
        amountTaka: 500,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BanglaQrView(payload: payload, size: 150),
            ),
          ),
        ),
      );

      expect(find.byType(BanglaQrView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('BANGLA QR'), findsOneWidget);
      expect(find.text('bKash'), findsOneWidget);
    });
  });
}
