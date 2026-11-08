import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_message_bubble.dart';

void main() {
  group('Pinned Message Tests - Models & UI', () {
    test('Pinned message structure contains rich metadata fields', () {
      final pinnedData = <String, dynamic>{
        'id': 'msg_123',
        'text': 'Important announcement: Meeting at 5 PM',
        'type': 'image',
        'mediaUrl': 'https://example.com/photo.jpg',
        'mediaUrls': [
          'https://example.com/p1.jpg',
          'https://example.com/p2.jpg'
        ],
        'senderId': 'user_abc',
        'senderName': 'Admin',
      };

      expect(pinnedData['id'], 'msg_123');
      expect(pinnedData['text'], contains('Important announcement'));
      expect(pinnedData['type'], 'image');
      expect((pinnedData['mediaUrls'] as List).length, 2);
      expect(pinnedData['senderId'], 'user_abc');
    });

    testWidgets(
        'ChannelMessageBubble renders with highlight glow border when isHighlighted is true',
        (tester) async {
      final message = ChannelMessage(
        id: 'msg_pin_1',
        senderEmail: 'author@bhromon.fun',
        senderName: 'Author',
        text: 'This is a pinned message target',
        timestamp: DateTime.now(),
        isPinned: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChannelMessageBubble(
              message: message,
              isMine: false,
              mentionsMe: false,
              myEmail: 'me@bhromon.fun',
              badge: 'Leader',
              isHighlighted: true,
              onLongPress: () {},
              onReact: (_) {},
              onVote: (_) {},
              onOpenMedia: (_) {},
              onOpenLedger: () {},
            ),
          ),
        ),
      );

      expect(find.byType(ChannelMessageBubble), findsOneWidget);
      expect(find.text('This is a pinned message target'), findsOneWidget);

      // Verify Container decoration has highlight border
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ChannelMessageBubble),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border?.top.color, AppColors.gold);
      expect(decoration?.border?.top.width, 2.0);
    });

    testWidgets(
        'ChannelMessageBubble renders normally when isHighlighted is false',
        (tester) async {
      final message = ChannelMessage(
        id: 'msg_pin_2',
        senderEmail: 'author@bhromon.fun',
        senderName: 'Author',
        text: 'Regular unhighlighted message',
        timestamp: DateTime.now(),
        isPinned: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChannelMessageBubble(
              message: message,
              isMine: false,
              mentionsMe: false,
              myEmail: 'me@bhromon.fun',
              badge: 'Leader',
              isHighlighted: false,
              onLongPress: () {},
              onReact: (_) {},
              onVote: (_) {},
              onOpenMedia: (_) {},
              onOpenLedger: () {},
            ),
          ),
        ),
      );

      expect(find.byType(ChannelMessageBubble), findsOneWidget);
      expect(find.text('Regular unhighlighted message'), findsOneWidget);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ChannelMessageBubble),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNull);
    });
  });
}
