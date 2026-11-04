import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/journey_alarm_sound.dart';
import 'package:bhromon/features/tour_group/domain/services/journey_alarm_ring.dart';
import 'package:bhromon/features/tour_group/presentation/pages/journey_alarm_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records when the alarm sound starts and stops.
class _FakeSound implements JourneyAlarmSound {
  final List<String> log = [];

  @override
  Future<void> start() async => log.add('start');

  @override
  Future<void> stop() async => log.add('stop');
}

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  final t0 = DateTime.utc(2027, 1, 13, 22);

  testWidgets('the alarm rings as it opens, and Dismiss stops it',
      (tester) async {
    _phoneSize(tester);
    final sound = _FakeSound();
    RingEnd? ended;
    await tester.pumpWidget(_app(JourneyAlarmPage(
      title: 'You have reached your destination',
      body: 'Destination: Sajek',
      ring: AlarmRing(),
      sound: sound,
      onFinished: (end) => ended = end,
      now: () => t0,
    )));
    await tester.pump();

    expect(sound.log, ['start']);
    expect(find.text('Destination: Sajek'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(sound.log, ['start', 'stop']);
    expect(ended, RingEnd.dismissed);
  });

  testWidgets('snooze silences the alarm and rings again after five minutes',
      (tester) async {
    _phoneSize(tester);
    var current = t0;
    final sound = _FakeSound();
    await tester.pumpWidget(_app(JourneyAlarmPage(
      title: 'Approaching Bandarban',
      body: '2 km to go',
      ring: AlarmRing(),
      sound: sound,
      onFinished: (_) {},
      now: () => current,
    )));
    await tester.pump();

    await tester.tap(find.text('Snooze 5 min'));
    await tester.pump();
    expect(sound.log, ['start', 'stop']);

    final snooze = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Snooze 5 min'),
    );
    expect(snooze.onPressed, isNull, reason: 'no second snooze while snoozed');

    current = current.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(sound.log, ['start', 'stop', 'start']);
  });

  testWidgets('I am awake ends the alarm and is reported as awake',
      (tester) async {
    _phoneSize(tester);
    final sound = _FakeSound();
    RingEnd? ended;
    await tester.pumpWidget(_app(JourneyAlarmPage(
      title: 'You have reached your destination',
      body: 'Destination: Sajek',
      ring: AlarmRing(),
      sound: sound,
      onFinished: (end) => ended = end,
      now: () => t0,
    )));
    await tester.pump();

    await tester.tap(find.text('I am awake'));
    await tester.pump();

    expect(ended, RingEnd.awake);
    expect(sound.log, ['start', 'stop']);
  });

  testWidgets('the back button cannot close the alarm', (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(_app(JourneyAlarmPage(
      title: 'You have reached your destination',
      body: 'Destination: Sajek',
      ring: AlarmRing(),
      sound: _FakeSound(),
      onFinished: (_) {},
      now: () => t0,
    )));
    await tester.pump();

    final scope = tester.widget<PopScope>(
      find.descendant(
        of: find.byType(JourneyAlarmPage),
        matching: find.byType(PopScope),
      ),
    );
    expect(scope.canPop, isFalse);
  });
}
