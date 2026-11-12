import 'dart:typed_data';

import 'package:bhromon/features/tour_group/domain/services/invite_join_link.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/invite_qr_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inviteQrImage', () {
    test('draws the three finder patterns of a version 2 or larger code', () {
      final image = inviteQrImage(inviteJoinLink('ABCD2345'));
      final n = image.moduleCount;

      expect(n, greaterThanOrEqualTo(21));
      // Top left, top right and bottom left: a dark outer ring, a light ring, a dark centre.
      expect(image.isDark(0, 0), isTrue);
      expect(image.isDark(0, 6), isTrue);
      expect(image.isDark(1, 1), isFalse);
      expect(image.isDark(3, 3), isTrue);
      expect(image.isDark(0, n - 1), isTrue);
      expect(image.isDark(n - 1, 0), isTrue);
    });

    test('the same link always gives the same matrix', () {
      final a = inviteQrImage(inviteJoinLink('ABCD2345'));
      final b = inviteQrImage(inviteJoinLink('abcd2345'));

      expect(a.moduleCount, b.moduleCount);
      for (var row = 0; row < a.moduleCount; row++) {
        for (var col = 0; col < a.moduleCount; col++) {
          expect(a.isDark(row, col), b.isDark(row, col));
        }
      }
    });
  });

  group('renderInviteQrPng', () {
    testWidgets('makes a PNG of the requested size', (tester) async {
      final bytes = await tester.runAsync(
        () => renderInviteQrPng(inviteJoinLink('ABCD2345'), pixels: 64),
      );

      expect(bytes, isNotNull);
      final png = bytes!;
      // The PNG signature, then the IHDR chunk, whose width and height follow the chunk header.
      expect(
        png.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );
      final header = ByteData.sublistView(png);
      expect(header.getUint32(16), 64);
      expect(header.getUint32(20), 64);
    });
  });

  group('InviteQrCode', () {
    testWidgets('paints a square code of the given size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: InviteQrCode(
                  data: 'https://app.bhromon.fun/#/join?code=ABCD2345',
                  size: 180),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(InviteQrCode)), const Size(180, 180));
      expect(
        find.descendant(
          of: find.byType(InviteQrCode),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });
}
