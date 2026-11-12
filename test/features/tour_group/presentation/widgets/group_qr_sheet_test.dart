import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_qr_sheet.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/invite_qr_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final group = TourGroup(
    id: 'group-1',
    name: 'Family Circle',
    ownerEmail: 'owner@example.com',
    inviteCode: 'ABCD2345',
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 1, 2),
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGroupQrSheet(context, group),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // The localizations load asynchronously, so the button appears only after the frames settle.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the group name, its code and the join code as a QR code',
      (tester) async {
    await openSheet(tester);

    expect(find.text('Family Circle'), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.byType(InviteQrCode), findsOneWidget);
    expect(find.text('Share QR image'), findsOneWidget);
  });

  testWidgets('copying the link puts the join link on the clipboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await openSheet(tester);

    await tester.tap(find.text('Copy invite link'));
    await tester.pumpAndSettle();

    expect(copied, 'https://app.bhromon.fun/#/join?code=ABCD2345');
    expect(find.text('Invite link copied to clipboard!'), findsOneWidget);
  });
}
