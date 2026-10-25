import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bhromon/features/chat/data/call_signaling_service.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_media_picker.dart';
import 'package:bhromon/features/chat/presentation/widgets/voice_message_bubble.dart';

void main() {
  group('Chat Features - Media & Voice', () {
    test('MediaPickResult stores XFile and type correctly', () {
      final xFile = XFile('test/path/image.jpg');
      final result = MediaPickResult(
        xFile: xFile,
        type: 'image',
      );

      expect(result.xFile.path, 'test/path/image.jpg');
      expect(result.type, 'image');
      expect(result.file, isNull);
    });

    test('MediaPickResult supports video type', () {
      final xFile = XFile('test/path/video.mp4');
      final result = MediaPickResult(
        xFile: xFile,
        type: 'video',
      );

      expect(result.xFile.path, 'test/path/video.mp4');
      expect(result.type, 'video');
    });

    testWidgets('VoiceMessageBubble renders correctly with duration',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceMessageBubble(
              audioUrl: 'https://example.com/audio.m4a',
              durationSeconds: 45,
              isMe: true,
            ),
          ),
        ),
      );

      expect(find.byType(VoiceMessageBubble), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('0:45'), findsOneWidget);
      expect(find.text('1x'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('VoiceMessageBubble cycles playback speed on tap',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceMessageBubble(
              audioUrl: 'https://example.com/audio.m4a',
              durationSeconds: 30,
              isMe: false,
            ),
          ),
        ),
      );

      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.text('1x'));
      await tester.pump();
      expect(find.text('1.5x'), findsOneWidget);

      await tester.tap(find.text('1.5x'));
      await tester.pump();
      expect(find.text('2x'), findsOneWidget);

      await tester.tap(find.text('2x'));
      await tester.pump();
      expect(find.text('1x'), findsOneWidget);
    });

    test('CallSignalingService initial state is idle', () {
      final service = CallSignalingService();
      expect(service.onLocalStream, isNull);
      expect(service.onRemoteStream, isNull);
      expect(service.onCallStateChange, isNull);
      expect(service.onCallEnded, isNull);
      service.dispose();
    });
  });
}
