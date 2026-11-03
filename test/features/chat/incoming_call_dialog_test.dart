import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/incoming_call_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

IncomingCallDialog _dialog({required bool waiting}) {
  return IncomingCallDialog(
    callerName: 'Rahim',
    avatarUrl: null,
    isVideo: false,
    waiting: waiting,
    onAccept: () async {},
    onDecline: () async {},
  );
}

void main() {
  group('IncomingCallDialog', () {
    testWidgets('a call that rings during a call shows the call-waiting label',
        (tester) async {
      await tester.pumpWidget(_app(_dialog(waiting: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('call-waiting-label')), findsOneWidget);
      expect(find.text('Call waiting'), findsOneWidget);
      expect(find.text('End & answer'), findsOneWidget);
    });

    testWidgets('a call with no call in progress shows no waiting label',
        (tester) async {
      await tester.pumpWidget(_app(_dialog(waiting: false)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('call-waiting-label')), findsNothing);
      expect(find.text('Call waiting'), findsNothing);
      expect(find.text('Accept'), findsOneWidget);
    });
  });
}
