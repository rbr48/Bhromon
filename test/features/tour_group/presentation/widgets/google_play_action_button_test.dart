import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/google_play_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget({
    Locale locale = const Locale('en'),
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        appBar: AppBar(
          actions: [
            GooglePlayActionButton(onTap: onTap),
          ],
        ),
      ),
    );
  }

  group('GooglePlayActionButton', () {
    test('canonical playStoreUrl targets Bhromon package on Google Play', () {
      expect(
        GooglePlayActionButton.playStoreUrl,
        'https://play.google.com/store/apps/details?id=com.bhromon.app&pli=1',
      );
    });

    testWidgets('renders IconButton and GooglePlayLogo vector', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(GooglePlayActionButton), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byType(GooglePlayLogo), findsOneWidget);
    });

    testWidgets('displays English tooltip correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(locale: const Locale('en')));
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Get app on Google Play');
    });

    testWidgets('displays Bengali tooltip correctly', (tester) async {
      await tester.pumpWidget(buildTestWidget(locale: const Locale('bn')));
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Google Play থেকে অ্যাপ নামান');
    });

    testWidgets('triggers callback on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildTestWidget(
        onTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
