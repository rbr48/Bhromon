import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_formatting_toolbar.dart';
import 'package:bhromon/features/tour_group/domain/models/study_thread_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_thread_rules.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The chat box under a discussion and a thread, and how the text in it becomes a thread. The
// screens that use the box are tested in study_thread_screens_test.dart.

Future<void> _pump(WidgetTester tester, Widget box) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Column(children: [const Spacer(), box])),
  ));
  // One frame, not a settle: the box shows a spinner while a message is sent, and that never settles.
  await tester.pump();
}

StudyThread _thread(String id, {bool pinned = false, DateTime? at}) =>
    StudyThread(
      id: id,
      title: id,
      body: id,
      createdByEmail: 'a@x.com',
      createdAt: at,
      pinned: pinned,
    );

void main() {
  group('the title of a thread started from the chat box', () {
    test('a single line is both the title and the question', () {
      final parts = threadTitleAndBody('  Why the train?  ');
      expect(parts.title, 'Why the train?');
      expect(parts.body, 'Why the train?');
    });

    test('the first line is the title and the whole text is the question', () {
      final parts =
          threadTitleAndBody('Why the train?\nIt appears three times.');
      expect(parts.title, 'Why the train?');
      expect(parts.body, 'Why the train?\nIt appears three times.');
    });

    test('a long first line is cut at a word and ends with an ellipsis', () {
      final line = List.filled(30, 'word').join(' ');
      final title = threadTitleAndBody(line).title;
      expect(title, endsWith('…'));
      expect(title.length, lessThanOrEqualTo(kThreadTitleMax + 1));
      expect(line.startsWith(title.substring(0, title.length - 1)), isTrue);
    });

    test('a blank text gives a blank title and question', () {
      final parts = threadTitleAndBody('   \n  ');
      expect(parts.title, isEmpty);
      expect(parts.body, isEmpty);
    });
  });

  group('the order of threads in a chat', () {
    test('pinned first, then the rest oldest first, so the newest is last', () {
      final ordered = chatOrderStudyThreads([
        _thread('c', at: DateTime(2030, 1, 3)),
        _thread('a', at: DateTime(2030, 1, 1)),
        _thread('p', pinned: true, at: DateTime(2029, 1, 1)),
        _thread('b', at: DateTime(2030, 1, 2)),
      ]).map((t) => t.id).toList();
      expect(ordered, ['p', 'a', 'b', 'c']);
    });

    test('a thread whose time is not yet known is last, as it was just started',
        () {
      final ordered = chatOrderStudyThreads([
        _thread('new'),
        _thread('old', at: DateTime(2030, 1, 1)),
      ]).map((t) => t.id).toList();
      expect(ordered, ['old', 'new']);
    });
  });

  group('the chat box', () {
    testWidgets('the markup button shows the formatting menu without a table',
        (tester) async {
      await _pump(
        tester,
        StudyChatComposer(
          controller: TextEditingController(),
          hint: 'Write',
          sending: false,
          onSend: () {},
        ),
      );

      await tester.tap(find.text('Aa'));
      await tester.pumpAndSettle();

      final menu = tester
          .widget<ChatFormattingToolbar>(find.byType(ChatFormattingToolbar));
      expect(menu.showTable, isFalse);
    });

    testWidgets('send is off until there is text, and then it sends',
        (tester) async {
      var sent = 0;
      await _pump(
        tester,
        StudyChatComposer(
          controller: TextEditingController(),
          hint: 'Write',
          sending: false,
          onSend: () => sent++,
        ),
      );

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(sent, 0);

      await tester.enterText(find.byType(TextField), 'A question');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(sent, 1);
    });

    testWidgets(
        'the chapter and page button shows only when the box offers one',
        (tester) async {
      var opened = 0;
      final controller = TextEditingController();
      await _pump(
        tester,
        StudyChatComposer(
          controller: controller,
          hint: 'Write',
          sending: false,
          onSend: () {},
        ),
      );
      expect(find.byIcon(Icons.menu_book_outlined), findsNothing);

      await _pump(
        tester,
        StudyChatComposer(
          controller: controller,
          hint: 'Write',
          sending: false,
          onSend: () {},
          onDetails: () => opened++,
          detailsTooltip: 'Chapter and page',
        ),
      );
      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets(
        'while a message is sent the box shows progress and cannot send',
        (tester) async {
      var sent = 0;
      await _pump(
        tester,
        StudyChatComposer(
          controller: TextEditingController(text: 'Sending now'),
          hint: 'Write',
          sending: true,
          onSend: () => sent++,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump();
      expect(sent, 0);
    });
  });
}
