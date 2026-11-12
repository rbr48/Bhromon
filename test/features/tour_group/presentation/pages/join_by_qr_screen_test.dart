import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/presentation/pages/join_by_qr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the scanner from a button, with the camera off, and returns the list of results the
  /// scanner popped with.
  Future<List<String?>> openScanner(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
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
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const JoinByQrScreen(scannerEnabled: false),
                  ),
                );
                results.add(code);
              },
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
    return results;
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  testWidgets('with the camera off it still offers the paste field',
      (tester) async {
    await openScanner(tester);

    expect(find.text('Scan to join'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('a pasted join link returns its invite code', (tester) async {
    final results = await openScanner(tester);

    await paste(tester, 'https://app.bhromon.fun/#/join?code=abcd2345');

    expect(results, ['ABCD2345']);
    expect(find.byType(JoinByQrScreen), findsNothing);
  });

  testWidgets('a bare code with spaces around it is read as the code',
      (tester) async {
    final results = await openScanner(tester);

    await paste(tester, '  abcd2345 ');

    expect(results, ['ABCD2345']);
  });

  testWidgets('a link from another site is refused and the page stays open',
      (tester) async {
    final results = await openScanner(tester);

    await paste(tester, 'https://example.com/#/join?code=ABCD2345');

    expect(results, isEmpty);
    expect(find.byType(JoinByQrScreen), findsOneWidget);
    expect(find.text('That is not a Bhromon group code.'), findsOneWidget);
  });

  testWidgets('the labels are in Bengali when the app is', (tester) async {
    await openScanner(tester, locale: const Locale('bn'));

    expect(find.text('স্ক্যান করে যোগ দিন'), findsOneWidget);
    expect(find.text('চালিয়ে যান'), findsOneWidget);
  });
}
