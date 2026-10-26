import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_composer.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_message_bubble.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/channel_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] once the localizations have loaded, which takes a few frames.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(_app(child));
  await tester.pumpAndSettle();
}

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: Center(child: child)),
  );
}

ChannelMessage _message({
  String text = 'hello',
  ChannelMessageKind kind = ChannelMessageKind.text,
  List<String> pollOptions = const [],
  Map<String, int> votes = const {},
  int expenseAmountPaisa = 0,
  Map<String, String> reactions = const {},
}) {
  return ChannelMessage(
    id: 'm1',
    senderEmail: 'rahim@x.com',
    senderName: 'Rahim',
    text: text,
    timestamp: DateTime(2026, 1, 2, 9, 30),
    kind: kind,
    pollOptions: pollOptions,
    votes: votes,
    expenseAmountPaisa: expenseAmountPaisa,
    expenseTitle: 'Dinner',
    reactions: reactions,
  );
}

ChannelMessageBubble _bubble(
  ChannelMessage message, {
  VoidCallback? onLongPress,
  ValueChanged<int>? onVote,
  bool isMine = false,
}) {
  return ChannelMessageBubble(
    message: message,
    isMine: isMine,
    mentionsMe: false,
    myEmail: 'me@x.com',
    badge: 'Seat B2',
    onLongPress: onLongPress ?? () {},
    onReact: (_) {},
    onVote: onVote ?? (_) {},
    onOpenMedia: (_) {},
    onOpenLedger: () {},
  );
}

void main() {
  group('ChannelMessageBubble', () {
    testWidgets('shows the sender, seat badge and formatted text',
        (tester) async {
      await _pump(tester, _bubble(_message(text: 'meet at **Gate 2**')));
      expect(find.text('Rahim'), findsOneWidget);
      expect(find.text('Seat B2'), findsOneWidget);
      expect(find.textContaining('Gate 2'), findsOneWidget);
    });

    testWidgets('a long press opens the message actions', (tester) async {
      var pressed = false;
      await _pump(
          tester,
          _bubble(
            _message(),
            onLongPress: () => pressed = true,
          ));
      await tester.longPress(find.textContaining('hello'));
      expect(pressed, isTrue);
    });

    testWidgets('tapping a poll option votes for it', (tester) async {
      int? chosen;
      await _pump(
          tester,
          _bubble(
            _message(
              kind: ChannelMessageKind.poll,
              text: 'Dinner?',
              pollOptions: const ['Hilsa', 'Chicken'],
              votes: const {'a@x.com': 0},
            ),
            onVote: (i) => chosen = i,
          ));
      await tester.tap(find.text('Chicken'));
      expect(chosen, 1);
      expect(find.text('1 votes'), findsOneWidget);
    });

    testWidgets('an expense card shows its amount', (tester) async {
      await _pump(
          tester,
          _bubble(_message(
            kind: ChannelMessageKind.expense,
            text: 'Dinner',
            expenseAmountPaisa: 240000,
          )));
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.textContaining('2,400'), findsOneWidget);
    });

    testWidgets('reactions are listed with their counts', (tester) async {
      await _pump(
          tester,
          _bubble(_message(
            reactions: const {'a@x.com': '👍', 'b@x.com': '👍'},
          )));
      expect(find.text('👍 2'), findsOneWidget);
    });
  });

  group('ChannelRichText spoilers', () {
    testWidgets('tapping a spoiler reports its id', (tester) async {
      int? tapped;
      await _pump(
          tester,
          ChannelRichText(
            text: '||surprise||',
            revealed: const {},
            onSpoiler: (id) => tapped = id,
          ));
      await tester.tap(find.byType(ChannelRichText));
      expect(tapped, 0);
    });
  });

  group('ChannelComposer', () {
    Widget composer({
      required VoidCallback onSend,
      ValueChanged<MentionChoice>? onPick,
      List<MentionChoice> mentions = const [],
      ChannelReply? replyTo,
    }) {
      return ChannelComposer(
        controller: TextEditingController(),
        focusNode: FocusNode(),
        hint: 'Write',
        sending: false,
        replyTo: replyTo,
        editing: false,
        pending: const [],
        uploadProgress: 0,
        uploadLabel: null,
        mentionChoices: mentions,
        onChanged: (_) {},
        onPickMention: onPick ?? (_) {},
        onSend: onSend,
        onAttach: () {},
        onCancelContext: () {},
        onCancelUpload: () {},
        onRemovePending: (_) {},
      );
    }

    testWidgets('the send button sends', (tester) async {
      var sent = false;
      await _pump(tester, composer(onSend: () => sent = true));
      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(sent, isTrue);
    });

    testWidgets('a reply shows whom it answers and can be cancelled',
        (tester) async {
      await _pump(
          tester,
          composer(
            onSend: () {},
            replyTo: const ChannelReply(
                id: 'x', senderName: 'Rahim', text: 'lunch?'),
          ));
      expect(find.text('Replying to Rahim'), findsOneWidget);
    });

    testWidgets('a mention choice is shown and can be picked', (tester) async {
      MentionChoice? picked;
      await _pump(
          tester,
          composer(
            onSend: () {},
            mentions: const [
              MentionChoice(
                  label: 'everyone', display: '@everyone · the whole tour'),
            ],
            onPick: (c) => picked = c,
          ));
      await tester.tap(find.text('@everyone · the whole tour'));
      expect(picked?.label, 'everyone');
    });
  });

  group('showChannelMembersSheet', () {
    testWidgets('shows audio and video call buttons for other members',
        (tester) async {
      final members = [
        TourMember(
          tourId: 't1',
          email: 'me@x.com',
          displayName: 'Me User',
          role: TourRole.owner,
          status: TourMemberStatus.active,
          joinedAt: DateTime(2026, 1, 1),
          uid: 'uid_me',
        ),
        TourMember(
          tourId: 't1',
          email: 'alice@x.com',
          displayName: 'Alice Explorer',
          role: TourRole.member,
          status: TourMemberStatus.active,
          joinedAt: DateTime(2026, 1, 2),
          uid: 'uid_alice',
        ),
      ];

      TourMember? calledMember;
      bool? calledIsVideo;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('bn')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showChannelMembersSheet(
                  ctx,
                  members: members,
                  myEmail: 'me@x.com',
                  badgeFor: (_) => '',
                  onStartCall: (m, isVideo) {
                    calledMember = m;
                    calledIsVideo = isVideo;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Me User (you)'), findsOneWidget);
      expect(find.text('Alice Explorer'), findsOneWidget);

      // Call buttons exist for Alice
      expect(find.byIcon(Icons.call), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);

      // Tap Audio Call
      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(calledMember?.email, 'alice@x.com');
      expect(calledIsVideo, isFalse);
    });
  });
}
