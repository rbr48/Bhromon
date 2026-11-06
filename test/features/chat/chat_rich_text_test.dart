import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_code_block_widget.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_formatting_toolbar.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_rich_text.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_table_widget.dart';
import 'package:bhromon/features/chat/presentation/widgets/table_builder_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatRichText Widget', () {
    testWidgets('renders plain text and inline spans', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text:
                'Hello **bold** and *italic* and __underline__ and ==highlight==',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatRichText), findsOneWidget);
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('renders heading blocks', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text: '# Main Title\n## Sub Title\n### Small Title',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Title'), findsOneWidget);
      expect(find.text('Sub Title'), findsOneWidget);
      expect(find.text('Small Title'), findsOneWidget);
    });

    testWidgets('renders blockquotes and dividers', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text: '> This is a quoted message\n\n---\n\nBottom text',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This is a quoted message'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Bottom text'), findsOneWidget);
    });

    testWidgets('renders lists and checklists', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text:
                '- Item A\n- Item B\n1. First\n2. Second\n- [ ] Task todo\n- [x] Task done',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Item A'), findsOneWidget);
      expect(find.text('Item B'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Task todo'), findsOneWidget);
      expect(find.text('Task done'), findsOneWidget);
      expect(
          find.byIcon(Icons.check_box_outline_blank_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
    });

    testWidgets('renders code blocks with copy button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text: '```dart\nvoid main() {\n  print("hi");\n}\n```',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatCodeBlockWidget), findsOneWidget);
      expect(find.text('DART'), findsOneWidget);
      expect(find.text('void main() {\n  print("hi");\n}'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets('renders markdown tables', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text:
                '| Item | Cost | Status |\n|:---|:---:|---:|\n| Hotel | 5000 | Paid |\n| Transport | 3200 | Due |',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatTableWidget), findsOneWidget);
      expect(find.text('Item'), findsOneWidget);
      expect(find.text('Cost'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Hotel'), findsOneWidget);
      expect(find.text('5000'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('3200'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
    });

    testWidgets('renders markdown tables even if newlines were collapsed',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatRichText(
            text:
                '| Col 1 | Col 2 | Col 3           - | - | - | | Val 1 | Val 2 | Val 3 |',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatTableWidget), findsOneWidget);
      expect(find.text('Col 1'), findsOneWidget);
      expect(find.text('Col 2'), findsOneWidget);
      expect(find.text('Col 3'), findsOneWidget);
      expect(find.text('Val 1'), findsOneWidget);
      expect(find.text('Val 2'), findsOneWidget);
      expect(find.text('Val 3'), findsOneWidget);
    });
  });

  group('ChatFormattingToolbar Widget', () {
    testWidgets('renders all toolbar buttons', (tester) async {
      final controller = TextEditingController(text: 'sample text');
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _wrap(
          ChatFormattingToolbar(
            controller: controller,
            focusNode: focusNode,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatFormattingToolbar), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('I'), findsOneWidget);
      expect(find.text('U'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('H'), findsOneWidget);
      expect(find.text('=='), findsOneWidget);
      expect(find.text('||'), findsOneWidget);
      expect(find.text('</>'), findsOneWidget);
      expect(find.text('{ }'), findsOneWidget);
      expect(find.text('”'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('✕'), findsOneWidget);
    });

    testWidgets('wraps text with bold tags when bold icon tapped',
        (tester) async {
      final controller = TextEditingController(text: 'hello');
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _wrap(
          ChatFormattingToolbar(
            controller: controller,
            focusNode: focusNode,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(controller.text, equals('**hello**'));
    });

    testWidgets('wraps text with spoiler tags when spoiler icon tapped',
        (tester) async {
      final controller = TextEditingController(text: 'secret');
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 6);
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _wrap(
          ChatFormattingToolbar(
            controller: controller,
            focusNode: focusNode,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('||'));
      await tester.pumpAndSettle();

      expect(controller.text, equals('||secret||'));
    });

    testWidgets(
        'handles empty selection and heading prefix safely without crash',
        (tester) async {
      final controller = TextEditingController(text: 'hello');
      controller.selection = const TextSelection.collapsed(offset: 0);
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _wrap(
          ChatFormattingToolbar(
            controller: controller,
            focusNode: focusNode,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(controller.text, equals('# hello'));
    });
  });

  group('TableBuilderSheet Widget', () {
    testWidgets('renders table builder and generates table markdown',
        (tester) async {
      String? generated;

      await tester.pumpWidget(
        _wrap(
          TableBuilderSheet(
            onInsert: (String md) => generated = md,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ElevatedButton), findsOneWidget);

      // Tap Insert table
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(generated, isNotNull);
      expect(generated!.contains('|'), isTrue);
      expect(generated!.contains(':---'), isTrue);
    });
  });

  group('Interactive ChatTableWidget & Micro-Toolbar', () {
    testWidgets('renders micro-action toolbar and detects numeric auto-sum',
        (tester) async {
      const tableMarkdown = '''
| আইটেম | খরচ |
| :--- | :--- |
| ডাল ও চাল | ৫০০ |
| ডিম ও সবজি | ৬৫০ |
''';

      bool importedToLedger = false;
      bool pinnedToNotice = false;

      await tester.pumpWidget(
        _wrap(
          ChatRichText(
            text: tableMarkdown,
            tableTitle: 'বাজারের খরচ',
            onImportLedger: () => importedToLedger = true,
            onPinNotice: () => pinnedToNotice = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify table headers and cells
      expect(find.text('আইটেম'), findsOneWidget);
      expect(find.text('খরচ'), findsOneWidget);
      expect(find.text('ডাল ও চাল'), findsOneWidget);

      // Verify micro-action toolbar icons
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      // Verify Auto-Sum calculation (500 + 650 = 1150)
      expect(find.textContaining('মোট (খরচ): ৳1,150'), findsOneWidget);

      // Verify Contextual Ecosystem Chips
      expect(find.text('লেজারে যুক্ত'), findsOneWidget);
      expect(find.text('নোটিশে পিন'), findsOneWidget);

      // Tap Ledger chip
      await tester.tap(find.text('লেজারে যুক্ত'));
      await tester.pumpAndSettle();
      expect(importedToLedger, isTrue);

      // Tap Notice chip
      await tester.tap(find.text('নোটিশে পিন'));
      await tester.pumpAndSettle();
      expect(pinnedToNotice, isTrue);

      // Tap fullscreen modal button
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pumpAndSettle();

      // Fullscreen modal should now be open
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.screen_lock_landscape_rounded), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });
  });
}
