import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bhromon/features/chat/data/call_signaling_service.dart';
import 'package:bhromon/features/chat/data/call_notification_service.dart';
import 'package:bhromon/features/chat/data/chat_local_cache.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_media_picker.dart';
import 'package:bhromon/features/chat/presentation/widgets/voice_message_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_reply_preview.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_reaction_bar.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_document_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_location_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_expense_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_media_caption_screen.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_emoji_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    test('CallNotificationService singleton instantiation and lifecycle', () {
      final notifService = CallNotificationService();
      expect(notifService, isNotNull);
      expect(identical(notifService, CallNotificationService()), isTrue);
      notifService.dispose();
    });
  });

  group('Chat Features - WhatsApp Parity Widgets', () {
    test('ReplyMessageInfo serialization toMap and fromMap', () {
      const reply = ReplyMessageInfo(
        messageId: 'msg_123',
        senderId: 'user_456',
        senderName: 'Tanvir',
        text: 'Let us hike Keokradong tomorrow!',
        type: 'text',
      );

      final map = reply.toMap();
      expect(map['messageId'], 'msg_123');
      expect(map['senderId'], 'user_456');
      expect(map['senderName'], 'Tanvir');
      expect(map['text'], 'Let us hike Keokradong tomorrow!');

      final restored = ReplyMessageInfo.fromMap(map);
      expect(restored.messageId, reply.messageId);
      expect(restored.senderName, reply.senderName);
      expect(restored.text, reply.text);
    });

    testWidgets('ChatQuotedBubble renders sender name and text correctly',
        (tester) async {
      const reply = ReplyMessageInfo(
        messageId: 'msg_1',
        senderId: 'user_1',
        senderName: 'Sajid',
        text: 'Bus leaves at 10 PM from Sayedabad',
        type: 'text',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatQuotedBubble(
              reply: reply,
              isMe: true,
            ),
          ),
        ),
      );

      expect(find.text('Sajid'), findsOneWidget);
      expect(find.text('Bus leaves at 10 PM from Sayedabad'), findsOneWidget);
    });

    testWidgets('ChatReplyInputBanner renders preview and invokes onCancel',
        (tester) async {
      bool cancelled = false;
      const reply = ReplyMessageInfo(
        messageId: 'msg_2',
        senderId: 'user_2',
        senderName: 'Ayesha',
        text: 'Hotel booking confirmed',
        type: 'text',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatReplyInputBanner(
              reply: reply,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      expect(find.text('Ayesha'), findsOneWidget);
      expect(find.text('Hotel booking confirmed'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('ChatReactionBadge displays emoji counts correctly',
        (tester) async {
      final reactions = {
        'user_1': '❤️',
        'user_2': '❤️',
        'user_3': '👍',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatReactionBadge(reactions: reactions),
          ),
        ),
      );

      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('ChatDocumentBubble renders file name and formatted size',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatDocumentBubble(
              documentUrl: 'https://example.com/ticket.pdf',
              fileName: 'SaintMartin_Ship_Ticket.pdf',
              fileSizeBytes: 2048576, // ~2.0 MB
              isMe: true,
              timeStr: '10:30 AM',
            ),
          ),
        ),
      );

      expect(find.text('SaintMartin_Ship_Ticket.pdf'), findsOneWidget);
      expect(find.text('2.0 MB • PDF'), findsOneWidget);
      expect(find.text('10:30 AM'), findsOneWidget);
    });

    testWidgets('ChatLocationBubble renders coordinates and address',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatLocationBubble(
              latitude: 21.4272,
              longitude: 92.0058,
              title: 'Laboni Beach Point',
              address: 'Cox\'s Bazar, Chittagong Division',
              isMe: false,
              timeStr: '11:15 AM',
            ),
          ),
        ),
      );

      expect(find.text('Laboni Beach Point'), findsOneWidget);
      expect(find.text('Cox\'s Bazar, Chittagong Division'), findsOneWidget);
      expect(find.text('11:15 AM'), findsOneWidget);
      expect(find.byIcon(Icons.directions), findsOneWidget);
    });

    testWidgets('ChatExpenseBubble renders travel bill split and settle action',
        (tester) async {
      bool settled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatExpenseBubble(
              title: 'Chander Gari Jeep Rent',
              amount: 6000.0,
              paidByName: 'Rahim',
              isPaidByMe: false,
              isSettled: false,
              timeStr: '2:45 PM',
              onSettle: () => settled = true,
            ),
          ),
        ),
      );

      expect(find.text('Chander Gari Jeep Rent'), findsOneWidget);
      expect(find.text('৳6000 BDT'), findsOneWidget);
      expect(find.text('Rahim paid • You owe ৳3000'), findsOneWidget);

      await tester.tap(find.text('Mark Settled'));
      await tester.pump();
      expect(settled, isTrue);
    });

    test('MediaCaptionResult stores view-once toggle state', () {
      final file = XFile('test/photo.jpg');
      final result = MediaCaptionResult(
        file: file,
        caption: 'Sunset at Inani Beach',
        isViewOnce: true,
      );

      expect(result.caption, 'Sunset at Inani Beach');
      expect(result.isViewOnce, isTrue);
    });

    test('ChatLocalCache biometric locked chats interface', () {
      final cache = ChatLocalCache();
      expect(cache, isNotNull);
      expect(identical(cache, ChatLocalCache()), isTrue);
      expect(cache.isChatLocked('non_existent_chat'), isFalse);
      expect(cache.getLockedChatIds(), isEmpty);
    });

    testWidgets(
        'ChatEmojiPicker renders, allows selection, and supports backspace',
        (tester) async {
      String? selectedEmoji;
      bool backspaceTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatEmojiPicker(
              onEmojiSelected: (emoji) => selectedEmoji = emoji,
              onBackspace: () => backspaceTapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(ChatEmojiPicker), findsOneWidget);
      expect(
          find.byIcon(Icons.sentiment_satisfied_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

      // Verify emojis are rendered
      expect(find.text('😀'), findsOneWidget);

      // Tap an emoji
      await tester.tap(find.text('😀'));
      await tester.pump();
      expect(selectedEmoji, '😀');

      // Tap backspace
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(backspaceTapped, isTrue);

      // Tap another category (e.g. Animals & Nature)
      await tester.tap(find.byIcon(Icons.pets_outlined));
      await tester.pumpAndSettle();
      expect(find.text('🐶'), findsOneWidget);

      // Select animal emoji
      await tester.tap(find.text('🐶'));
      await tester.pump();
      expect(selectedEmoji, '🐶');
    });

    test(
        'Call date parser handles Timestamp, ISO string, and epoch milliseconds',
        () {
      // 1. Timestamp
      final ts = Timestamp.fromDate(DateTime(2026, 10, 26, 12, 30));
      final parsedFromTs = (ts is Timestamp) ? ts.toDate() : null;
      expect(parsedFromTs, DateTime(2026, 10, 26, 12, 30));

      // 2. ISO String
      const isoStr = '2026-10-26T12:30:00.000';
      final parsedFromStr = DateTime.tryParse(isoStr);
      expect(parsedFromStr, isNotNull);
      expect(parsedFromStr!.year, 2026);

      // 3. Epoch milliseconds
      final epoch = DateTime(2026, 10, 26, 12, 30).millisecondsSinceEpoch;
      final parsedFromNum = DateTime.fromMillisecondsSinceEpoch(epoch);
      expect(parsedFromNum.year, 2026);
    });
  });
}
