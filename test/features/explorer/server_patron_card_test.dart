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

  testWidgets('ServerPatronCard renders title and the QR option in English',
      (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Keep Bhromon Running'), findsOneWidget);
    expect(find.text('Bangla QR'), findsOneWidget);
    expect(find.text('Open Source'), findsOneWidget);
    expect(find.byIcon(Icons.volunteer_activism_rounded), findsOneWidget);
  });

  testWidgets('the card shows no bKash or Nagad number', (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.textContaining('01737910040'), findsNothing);
    expect(find.text('bKash'), findsNothing);
    expect(find.text('Nagad'), findsNothing);
  });

  testWidgets('tapping the Bangla QR option opens the QR sheet',
      (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bangla QR'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(
      find.text('Scan with bKash, Nagad, Rocket or any bank app to donate'),
      findsOneWidget,
    );
    expect(find.text('GitHub Sponsors'), findsOneWidget);
  });

  testWidgets('the QR sits on a white tile so it scans from the dark card',
      (tester) async {
    await tester.pumpWidget(buildCard(locale: const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();

    final whiteTile = find.ancestor(
      of: find.byType(Image),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.white,
      ),
    );
    expect(whiteTile, findsOneWidget);
  });

  test('Bengali strings for the QR are accurate and non-empty', () {
    final bn = AppLocalizations(const Locale('bn'));
    expect(
        bn.translate('server_patron_title'), 'ভ্রমণ সার্ভার সচল রাখতে সহায়তা');
    expect(bn.translate('server_patron_qr_chip'), 'বাংলা কিউআর');
    expect(bn.translate('server_patron_github'), 'গিটহাব স্পনসর');
    expect(bn.translate('server_patron_qr_caption'),
        'অনুদান দিতে বিকাশ, নগদ, রকেট বা যেকোনো ব্যাংক অ্যাপ দিয়ে স্ক্যান করুন');
  });
}
