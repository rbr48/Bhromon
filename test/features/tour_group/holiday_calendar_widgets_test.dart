import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/localization/localized_date.dart';
import 'package:bhromon/core/localization/tour_translation_keys.dart';
import 'package:bhromon/features/tour_group/domain/services/holiday_calendar.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/holiday_calendar/holiday_common.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/holiday_calendar/holiday_leave_view.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/holiday_calendar/holiday_list_view.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/holiday_calendar/holiday_month_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Widget _wrap(Widget child, {String language = 'en'}) {
  return MaterialApp(
    locale: Locale(language),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      backgroundColor: const Color(0xFF0D1A12),
      body: SingleChildScrollView(child: child),
    ),
  );
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('bn');
  });

  testWidgets('the month grid shows January 2027 and tapping a day reports it',
      (tester) async {
    _phoneSize(tester);
    final calendar = HolidayCalendar();
    DateTime? tapped;

    await tester.pumpWidget(_wrap(HolidayMonthView(
      calendar: calendar,
      month: 1,
      trip: null,
      selected: null,
      onMonthChanged: (_) {},
      onDayTap: (d) => tapped = d,
    )));
    await tester.pumpAndSettle();

    // The title follows the app's saved language, so compare with the same formatter.
    expect(
      find.text(localizedDateFormat('MMMM yyyy').format(DateTime(2027, 1))),
      findsOneWidget,
    );
    expect(find.text('31'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('24')); // Shab-e-Barat, a holiday
    expect(tapped, DateTime(2027, 1, 24));
  });

  testWidgets('the holiday list renders every holiday without overflowing',
      (tester) async {
    _phoneSize(tester);
    await tester
        .pumpWidget(_wrap(HolidayListView(calendar: HolidayCalendar())));
    await tester.pumpAndSettle();

    expect(find.text('Shab-e-Barat'), findsOneWidget);
    expect(find.text('Christmas Day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leave planner lists the best leave days', (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(_wrap(HolidayLeaveView(
      calendar: HolidayCalendar(),
      onDayTap: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Best single leave days'), findsOneWidget);
    expect(find.text('Check a date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('keys read from variables exist in both languages', () {
    final keys = [
      ...kHolidayWeekdayKeys,
      for (final c in HolidayCategoryKeysForTest.all) c,
    ];
    for (final key in keys) {
      expect(
          TourTranslationKeys.localizedValues['en']?.containsKey(key), isTrue,
          reason: 'no English for $key');
      expect(
          TourTranslationKeys.localizedValues['bn']?.containsKey(key), isTrue,
          reason: 'no Bengali for $key');
    }
  });
}

/// The category keys, which are returned by [holidayCategoryKey].
class HolidayCategoryKeysForTest {
  static const List<String> all = [
    'hol_category_public',
    'hol_category_executive',
    'hol_category_bank',
  ];
}
