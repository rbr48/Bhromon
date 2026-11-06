import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/theme/theme.dart';
import 'package:bhromon/features/chat/presentation/widgets/voice_message_bubble.dart';

Future<void> _pump(WidgetTester tester, Widget bubble) {
  return tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: bubble)),
  ));
}

void main() {
  testWidgets('a voice message that is still sending shows its progress',
      (tester) async {
    await _pump(
      tester,
      const VoiceMessageBubble(
        audioUrl: '',
        durationSeconds: 12,
        isMe: true,
        uploadProgress: 0.42,
      ),
    );

    expect(find.text('42%'), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, closeTo(0.42, 1e-9));
  });

  testWidgets(
      'a voice message that is still sending cannot be played or sped up',
      (tester) async {
    await _pump(
      tester,
      const VoiceMessageBubble(
        audioUrl: '',
        durationSeconds: 12,
        isMe: true,
        uploadProgress: 0.1,
      ),
    );

    final tappable = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .where((g) => g.onTap != null);
    expect(tappable, isEmpty);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
  });

  testWidgets('a voice message that is not sending shows no progress',
      (tester) async {
    await _pump(
      tester,
      const VoiceMessageBubble(
        audioUrl: 'https://example.com/voice.m4a',
        durationSeconds: 12,
        isMe: true,
      ),
    );

    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final tappable = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .where((g) => g.onTap != null);
    expect(tappable, isNotEmpty);
  });
}
