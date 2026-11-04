import 'dart:async';

import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/official_feed/domain/official_feed_choice.dart';
import 'package:bhromon/features/official_feed/presentation/official_feed_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OfficialFeedChoice stored;
  late List<bool> followed;

  setUp(() {
    stored = OfficialFeedChoice.unanswered;
    followed = <bool>[];
  });

  Future<OfficialFeedChoice> load() async => stored;

  Future<void> save(OfficialFeedChoice choice) async {
    stored = choice;
  }

  Future<void> pumpOpener(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                unawaited(showOfficialFeedPromptIfNeeded(
                  context,
                  onFollowChanged: (follow) async => followed.add(follow),
                  loadChoice: load,
                  saveChoice: save,
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    // The localizations load after the first frame.
    await tester.pumpAndSettle();
  }

  testWidgets('asks once, and passes the answer on', (tester) async {
    await pumpOpener(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the official feed?'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(followed, [true]);
    expect(stored, OfficialFeedChoice.follow);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the official feed?'), findsNothing);
    expect(followed, [true]);
  });

  testWidgets('Not now is kept as an answer too', (tester) async {
    await pumpOpener(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(followed, [false]);
    expect(stored, OfficialFeedChoice.notNow);
  });

  testWidgets('tapping outside the question does not dismiss it',
      (tester) async {
    await pumpOpener(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Follow the official feed?'), findsOneWidget);
    expect(followed, isEmpty);
  });
}
