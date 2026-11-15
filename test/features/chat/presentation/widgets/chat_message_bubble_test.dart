import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_skeleton.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// One message of a one-to-one chat. Its content is drawn again only when the message, its
// selection or the theme changes, and the chat finds a bubble on screen by the message's id.

class _Taps {
  int tap = 0;
  int longPress = 0;
}

Map<String, dynamic> _message({String text = 'Hello there', String? status}) =>
    {
      'type': 'text',
      'text': text,
      'senderId': 'me',
      'timestamp': Timestamp.fromDate(DateTime(2026, 11, 14, 9, 30)),
      if (status != null) 'status': status,
    };

Widget _host({
  required Map<String, dynamic> data,
  bool selected = false,
  ThemeMode mode = ThemeMode.dark,
  ChatBubbleRegistry? registry,
  _Taps? taps,
  String id = 'm1',
}) {
  return MaterialApp(
    locale: const Locale('en'),
    themeMode: mode,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ListView(
        children: [
          ChatMessageBubble(
            key: ValueKey<String>(id),
            messageId: id,
            data: data,
            hasPendingWrites: false,
            fromLocalCache: false,
            currentUid: 'me',
            isSelected: selected,
            isHighlighted: false,
            replyEnabled: true,
            registry: registry,
            formatTime: (time) => '${time.hour}:${time.minute}',
            onScrollToMessage: (_) {},
            onExpandText: (_) {},
            onReply: () {},
            onTap: () => taps?.tap++,
            onLongPress: () => taps?.longPress++,
            onSettleExpense: () {},
            onViewOnceOpened: () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() => ChatMessageBubble.debugContentBuilds = 0);

  testWidgets('shows the message text and its time', (tester) async {
    await tester.pumpWidget(_host(data: _message()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hello there'), findsOneWidget);
    expect(find.text('9:30'), findsOneWidget);
  });

  testWidgets(
      'is not drawn again when the screen rebuilds with the same message',
      (tester) async {
    await tester.pumpWidget(_host(data: _message()));
    await tester.pumpAndSettle();
    final drawn = ChatMessageBubble.debugContentBuilds;

    // A fresh copy of the same data, as every snapshot brings.
    await tester.pumpWidget(_host(data: _message()));
    await tester.pump();

    expect(ChatMessageBubble.debugContentBuilds, drawn);
  });

  testWidgets('is drawn again when its tick changes', (tester) async {
    await tester.pumpWidget(_host(data: _message(status: 'sent')));
    await tester.pumpAndSettle();
    final drawn = ChatMessageBubble.debugContentBuilds;

    await tester.pumpWidget(_host(data: _message(status: 'read')));
    await tester.pump();

    expect(ChatMessageBubble.debugContentBuilds, drawn + 1);
  });

  testWidgets('is drawn again when it is selected', (tester) async {
    await tester.pumpWidget(_host(data: _message()));
    await tester.pumpAndSettle();
    final drawn = ChatMessageBubble.debugContentBuilds;

    await tester.pumpWidget(_host(data: _message(), selected: true));
    await tester.pump();

    expect(ChatMessageBubble.debugContentBuilds, drawn + 1);
  });

  testWidgets('is drawn again when the theme changes', (tester) async {
    await tester.pumpWidget(_host(data: _message()));
    await tester.pumpAndSettle();
    final drawn = ChatMessageBubble.debugContentBuilds;

    await tester.pumpWidget(_host(data: _message(), mode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(ChatMessageBubble.debugContentBuilds, greaterThan(drawn));
  });

  testWidgets('a tap and a long press reach the chat', (tester) async {
    final taps = _Taps();
    await tester.pumpWidget(_host(data: _message(), taps: taps));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Hello there'));
    await tester.pump();
    await tester.longPress(find.textContaining('Hello there'));
    await tester.pump();

    expect(taps.tap, 1);
    expect(taps.longPress, 1);
  });

  testWidgets(
      'the chat finds a bubble on screen by its message id, until it leaves',
      (tester) async {
    final registry = ChatBubbleRegistry();
    await tester.pumpWidget(_host(data: _message(), registry: registry));
    await tester.pumpAndSettle();

    expect(registry.contextOf('m1'), isNotNull);
    expect(registry.contextOf('other'), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(registry.contextOf('m1'), isNull);
  });

  testWidgets('the loading skeleton draws bubble shapes and no spinner',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: ChatSkeleton())));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Container), findsNWidgets(6));
  });
}
