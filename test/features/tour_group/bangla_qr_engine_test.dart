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

    test(
        'normalizePhone and isPhoneAccount correctly detect valid mobile numbers',
        () {
      expect(BanglaQrPayload.normalizePhone('+8801712345678'),
          equals('01712345678'));
      expect(BanglaQrPayload.normalizePhone('8801812345678'),
          equals('01812345678'));
      expect(BanglaQrPayload.normalizePhone('01912-345678'),
          equals('01912345678'));
      expect(BanglaQrPayload.normalizePhone(' 01300 123456 '),
          equals('01300123456'));

      const phonePayload = BanglaQrPayload(
        accountNumber: '+8801712345678',
        payeeName: 'Test Payee',
      );
      expect(phonePayload.isPhoneAccount, isTrue);

      const emailPayload = BanglaQrPayload(
        accountNumber: 'pahan1991@gmail.com',
        payeeName: 'Test Payee',
      );
      expect(emailPayload.isPhoneAccount, isFalse);

      final updated = emailPayload.copyWith(accountNumber: '01712345678');
      expect(updated.isPhoneAccount, isTrue);
      expect(updated.accountNumber, equals('01712345678'));
    });
  });

  group('BanglaQrView & Sheet Widgets', () {
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

    testWidgets('renders BanglaQrSheetModal with tabs and inputs',
        (tester) async {
      const payload = BanglaQrPayload(
        accountNumber: 'pahan1991@gmail.com',
        payeeName: 'Izhaan',
        amountTaka: 750,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BanglaQrSheetModal(initialPayload: payload),
          ),
        ),
      );

      expect(find.text('Bangla QR & MFS Payment'), findsOneWidget);
      expect(find.text('ডায়নামিক কিউআর'), findsOneWidget);
      expect(find.text('কিউআর ছবি (গ্যালারি)'), findsOneWidget);
      expect(find.text('৳ 750'), findsOneWidget);
      expect(find.text('Izhaan'), findsOneWidget);

      // Verify switching to custom QR image tab
      await tester.tap(find.text('কিউআর ছবি (গ্যালারি)'));
      await tester.pumpAndSettle();

      expect(find.text('গ্যালারি থেকে ছবি বাছাই করুন'), findsOneWidget);
    });
  });
}
