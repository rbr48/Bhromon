import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/groups/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _english = 'You are offline. These groups are saved on this device.';
const _bengali = 'আপনি অফলাইনে আছেন। এই গ্রুপগুলো এই ডিভাইসে সংরক্ষিত আছে।';

Widget _app(ValueNotifier<bool> fromCache) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: GroupsOfflineBanner(fromCache: fromCache)),
  );
}

/// Bengali without MaterialApp: Material's own localisations have no Bengali version
/// in this app, so the banner is localised through its own delegate alone.
Widget _bengaliApp(ValueNotifier<bool> fromCache) {
  return Localizations(
    locale: const Locale('bn'),
    delegates: const [
      AppLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Material(child: GroupsOfflineBanner(fromCache: fromCache)),
    ),
  );
}

Finder get _liveRegion => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.liveRegion == true);

void main() {
  testWidgets('the banner stays hidden while the groups come from the server',
      (tester) async {
    final fromCache = ValueNotifier<bool>(false);
    await tester.pumpWidget(_app(fromCache));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 30));

    expect(find.text(_english), findsNothing);
    expect(_liveRegion, findsNothing);
  });

  testWidgets(
      'the banner shows once the answer has come from the cache for 8 seconds',
      (tester) async {
    final fromCache = ValueNotifier<bool>(false);
    await tester.pumpWidget(_app(fromCache));
    await tester.pumpAndSettle();

    fromCache.value = true;
    await tester.pump(const Duration(seconds: 7));
    expect(find.text(_english), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_english), findsOneWidget);
    expect(_liveRegion, findsOneWidget);
  });

  testWidgets('a connection that comes back hides the banner at once',
      (tester) async {
    final fromCache = ValueNotifier<bool>(true);
    await tester.pumpWidget(_app(fromCache));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
    expect(find.text(_english), findsOneWidget);

    fromCache.value = false;
    await tester.pump();

    expect(find.text(_english), findsNothing);
  });

  testWidgets('a short cache-only answer never shows the banner',
      (tester) async {
    final fromCache = ValueNotifier<bool>(false);
    await tester.pumpWidget(_app(fromCache));
    await tester.pumpAndSettle();

    fromCache.value = true;
    await tester.pump(const Duration(seconds: 3));
    fromCache.value = false;
    await tester.pump(const Duration(seconds: 30));

    expect(find.text(_english), findsNothing);
  });

  testWidgets('leaving the screen while the banner waits cancels its timer',
      (tester) async {
    // A timer still pending when the test ends fails the test, so this checks that
    // dispose cancels the wait.
    final fromCache = ValueNotifier<bool>(true);
    await tester.pumpWidget(_app(fromCache));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the banner text follows the language', (tester) async {
    final fromCache = ValueNotifier<bool>(true);
    await tester.pumpWidget(_bengaliApp(fromCache));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));

    expect(find.text(_bengali), findsOneWidget);
    expect(find.text(_english), findsNothing);
  });
}
