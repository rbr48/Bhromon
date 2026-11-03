import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/services/battery_guidance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, Locale locale) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  final now = DateTime(2026, 1, 20, 10);

  group('shouldShowBatteryGuidance', () {
    test('shows the first time on Android, when not exempt', () {
      expect(
        shouldShowBatteryGuidance(
          isAndroid: true,
          alreadyExempt: false,
          lastShown: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('never shows on another platform or when already exempt', () {
      expect(
        shouldShowBatteryGuidance(
          isAndroid: false,
          alreadyExempt: false,
          lastShown: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldShowBatteryGuidance(
          isAndroid: true,
          alreadyExempt: true,
          lastShown: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('shows at most once a week', () {
      bool showAfter(Duration gap) => shouldShowBatteryGuidance(
            isAndroid: true,
            alreadyExempt: false,
            lastShown: now.subtract(gap),
            now: now,
          );
      expect(showAfter(const Duration(days: 6, hours: 23)), isFalse);
      expect(showAfter(const Duration(days: 7)), isTrue);
    });
  });

  group('batteryTipKeyFor', () {
    test('gives each maker its own tip, and others none', () {
      expect(batteryTipKeyFor('Xiaomi'), 'battery_tip_xiaomi');
      expect(batteryTipKeyFor('Redmi'), 'battery_tip_xiaomi');
      expect(batteryTipKeyFor('OPPO'), 'battery_tip_oppo');
      expect(batteryTipKeyFor('realme'), 'battery_tip_oppo');
      expect(batteryTipKeyFor('vivo'), 'battery_tip_vivo');
      expect(batteryTipKeyFor('samsung'), 'battery_tip_samsung');
      expect(batteryTipKeyFor('Google'), isNull);
      expect(batteryTipKeyFor(''), isNull);
    });
  });

  group('BatteryGuidanceDialog', () {
    testWidgets('shows the tip for the maker, in English', (tester) async {
      await tester.pumpWidget(_app(
        const BatteryGuidanceDialog(tipKey: 'battery_tip_samsung'),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Keep calls ringing'), findsOneWidget);
      expect(find.byKey(const ValueKey('battery-tip')), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('shows no tip when the maker has none, in Bengali',
        (tester) async {
      await tester.pumpWidget(_app(
        const BatteryGuidanceDialog(tipKey: null),
        const Locale('bn'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('battery-tip')), findsNothing);
      expect(find.text('পরে'), findsOneWidget);
      expect(find.text('সেটিংস খুলুন'), findsOneWidget);
    });
  });
}
