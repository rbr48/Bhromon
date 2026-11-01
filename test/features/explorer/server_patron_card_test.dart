import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/explorer/presentation/widgets/server_patron_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildCard({Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: const Scaffold(
        body: SingleChildScrollView(
          child: ServerPatronCard(),
        ),
      ),
    );
  }

  testWidgets('ServerPatronCard renders title and payment options in English',
      (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Keep Bhromon Running'), findsOneWidget);
    expect(find.text('bKash'), findsOneWidget);
    expect(find.text('Nagad'), findsOneWidget);
    expect(find.text('Open Source'), findsOneWidget);
    expect(find.byIcon(Icons.volunteer_activism_rounded), findsOneWidget);
  });

  testWidgets('Tapping bKash triggers clipboard copy and snackbar',
      (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    final bkashBtn = find.text('bKash');
    expect(bkashBtn, findsOneWidget);

    await tester.tap(bkashBtn);
    await tester.pump(); // Start snackbar animation

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('01737910040'), findsOneWidget);
  });

  testWidgets('Tapping info icon opens support details bottom sheet',
      (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    final infoIcon = find.byIcon(Icons.info_outline_rounded);
    expect(infoIcon, findsOneWidget);

    await tester.tap(infoIcon);
    await tester.pumpAndSettle();

    expect(find.text('bKash (Personal)'), findsOneWidget);
    expect(find.text('Nagad (Personal)'), findsOneWidget);
    expect(find.text('GitHub Sponsors'), findsOneWidget);
  });

  test('Translation keys in Bengali are accurate and non-empty', () {
    final bn = AppLocalizations(const Locale('bn'));
    expect(
        bn.translate('server_patron_title'), 'ভ্রমণ সার্ভার সচল রাখতে সহায়তা');
    expect(bn.translate('server_patron_bkash'), 'বিকাশ');
    expect(bn.translate('server_patron_nagad'), 'নগদ');
    expect(bn.translate('server_patron_github'), 'গিটহাব স্পনসর');
    expect(
        bn.translate('server_patron_copied', args: {'number': '01737910040'}),
        'নম্বর কপি হয়েছে: 01737910040');
  });
}
