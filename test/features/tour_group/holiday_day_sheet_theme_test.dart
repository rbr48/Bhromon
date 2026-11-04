import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/features/tour_group/domain/services/holiday_calendar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/holiday_calendar/holiday_common.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/holiday_calendar/holiday_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('bn');
  });

  testWidgets(
    'the day sheet follows the light theme: a light sheet with dark text, not fixed dark green',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final calendar = HolidayCalendar();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('bn')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showHolidayDaySheet(
                    context,
                    calendar: calendar,
                    date: DateTime(2027, 1, 13),
                    inTrip: false,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      // Localization delegates load asynchronously, so let the first frame settle.
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The sheet is no longer painted with the fixed dark green.
      expect(
        find.byWidgetPredicate((w) => w is Material && w.color == kHolidayCard),
        findsNothing,
      );
      // It is painted with the light palette's card colour.
      expect(
        find.byWidgetPredicate(
          (w) => w is Material && w.color == ForestPalette.light.card,
        ),
        findsWidgets,
      );
      // The date title uses the light palette's dark text.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.style?.fontWeight == FontWeight.bold &&
              w.style?.color == ForestPalette.light.text,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
