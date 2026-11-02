import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/core/theme/theme.dart';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_document_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_expense_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_location_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_reaction_bar.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_reply_preview.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

/// The colour behind [node], or null when it is a gradient or an image.
Color? _backgroundOf(RenderObject node, Color fallback) {
  final layers = <Color>[];
  RenderObject? current = node.parent;
  while (current != null) {
    Color? color;
    if (current is RenderDecoratedBox) {
      final decoration = current.decoration;
      if (decoration is BoxDecoration) {
        if (decoration.gradient != null || decoration.image != null) {
          return null;
        }
        color = decoration.color;
      }
    } else if (current is RenderPhysicalModel) {
      color = current.color;
    } else if (current is RenderPhysicalShape) {
      color = current.color;
    } else if (current.runtimeType.toString() == '_RenderColoredBox') {
      color = (current as dynamic).color as Color;
    }
    if (color != null && color.a > 0) {
      layers.add(color);
      if (color.a >= 1) break;
    }
    current = current.parent;
  }
  var result = fallback;
  for (final layer in layers.reversed) {
    result = Color.alphaBlend(layer, result);
  }
  return result;
}

/// Every painted text with letters or digits must reach 3:1 on its background.
void _expectReadable(WidgetTester tester, ThemeData theme, String label) {
  final paragraphs = tester.allRenderObjects.whereType<RenderParagraph>();
  var checked = 0;
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    if (!RegExp(r'[A-Za-z0-9ঀ-৿]').hasMatch(text)) continue;
    final color = paragraph.text.style?.color;
    if (color == null) continue;
    final background = _backgroundOf(paragraph, theme.scaffoldBackgroundColor);
    if (background == null) continue;
    final ratio = _contrast(Color.alphaBlend(color, background), background);
    expect(ratio, greaterThanOrEqualTo(3.0),
        reason: '$label: "$text" has contrast ${ratio.toStringAsFixed(2)} '
            '($color on $background)');
    checked++;
  }
  expect(checked, greaterThan(0), reason: '$label: no text was checked');
}

Widget _bubbles(bool isMe, ChatPalette palette) {
  const reply = ReplyMessageInfo(
    messageId: 'm1',
    senderId: 'u1',
    senderName: 'Sajid',
    text: 'Bus leaves at 10 PM',
    type: 'text',
  );
  return ColoredBox(
    color: palette.wallpaper,
    child: ListView(
      children: [
        ColoredBox(
          color: isMe ? palette.outgoing : palette.panel,
          child: ChatQuotedBubble(reply: reply, isMe: isMe),
        ),
        ChatReplyInputBanner(reply: reply, onCancel: () {}),
        ChatDocumentBubble(
          documentUrl: 'https://example.com/ticket.pdf',
          fileName: 'Ship_Ticket.pdf',
          fileSizeBytes: 2048576,
          isMe: isMe,
          timeStr: '10:30 AM',
        ),
        ChatLocationBubble(
          latitude: 21.4272,
          longitude: 92.0058,
          title: 'Laboni Beach Point',
          address: "Cox's Bazar",
          isMe: isMe,
          timeStr: '11:15 AM',
        ),
        ChatExpenseBubble(
          title: 'Jeep Rent',
          amount: 6000,
          paidByName: 'Rahim',
          isPaidByMe: isMe,
          isSettled: false,
          timeStr: '2:45 PM',
          onSettle: () {},
        ),
        const ChatReactionBadge(reactions: {'u1': '❤️', 'u2': '👍'}),
      ],
    ),
  );
}

void main() {
  for (final dark in [false, true]) {
    for (final isMe in [false, true]) {
      final themeName = dark ? 'dark' : 'light';
      final side = isMe ? 'own' : 'their';
      testWidgets('chat bubbles are readable in $themeName mode ($side)',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 3200);
        addTearDown(tester.view.resetPhysicalSize);
        final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: _bubbles(isMe, dark ? ChatPalette.dark : ChatPalette.light),
          ),
        ));
        await tester.pump();
        _expectReadable(tester, theme, '$themeName/$side');
      });
    }
  }
}
