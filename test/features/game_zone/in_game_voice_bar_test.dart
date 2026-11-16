import 'package:bhromon/features/game_zone/common/in_game_voice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('InGameVoiceBar renders join voice button when disconnected',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InGameVoiceBar(
            tourId: 'tour_cox_2026',
            gameId: 'game_carrom_1',
            myEmail: 'player@bhromon.fun',
            myDisplayName: 'Sea Explorer',
            myUid: 'uid_player_1',
            initialJoin: false,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Join Button
    expect(find.text('Voice chat with group'), findsOneWidget);
    expect(find.text('Join Voice'), findsOneWidget);
    expect(find.byIcon(Icons.headset_mic_rounded), findsOneWidget);
  });

  testWidgets('InGameVoiceBar collapses safely when tourId or gameId is empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InGameVoiceBar(
            tourId: '',
            gameId: '',
            myEmail: 'player@bhromon.fun',
            myDisplayName: 'Player',
            myUid: 'uid_1',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Empty widget rendered
    expect(find.byType(InGameVoiceBar), findsOneWidget);
    expect(find.text('Voice chat with group'), findsNothing);
  });

  testWidgets('InGameVoiceBar fits narrow 320px viewport without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          home: Scaffold(
            body: InGameVoiceBar(
              tourId: 'tour_cox_2026',
              gameId: 'game_carrom_1',
              myEmail: 'player@bhromon.fun',
              myDisplayName: 'Sea Explorer',
              myUid: 'uid_player_1',
              initialJoin: false,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Join Voice'), findsOneWidget);
  });
}
