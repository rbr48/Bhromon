import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/chat/presentation/widgets/chat_rich_text.dart';
import 'package:bhromon/features/tour_group/presentation/pages/markdown_viewer_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestApp(
    Widget child, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) {
    return MaterialApp(
      locale: locale,
      theme: theme,
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );
  }

  group('MarkdownViewerScreen', () {
    testWidgets('renders raw markdown content and MD badge in AppBar',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Readme.md',
            rawContent: '# Welcome to Bhromon\n\nThis is a *markdown* test.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Readme.md'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
      expect(find.byType(ChatRichText), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    });

    testWidgets('copy button copies markdown content and shows feedback',
        (tester) async {
      final List<MethodCall> log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (methodCall) async {
        log.add(methodCall);
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Notes.md',
            rawContent: 'Sample note body',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pump();

      expect(
        log.any((call) =>
            call.method == 'Clipboard.setData' &&
            call.arguments['text'] == 'Sample note body'),
        isTrue,
      );
      expect(find.text('Document text copied'), findsOneWidget);
    });

    testWidgets('displays error state when no source is available',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Empty.md',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders localized Bengali title and retry button',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: '',
          ),
          locale: const Locale('bn'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('মার্কডাউন ডকুমেন্ট'), findsOneWidget);
      expect(find.text('আবার চেষ্টা করুন'), findsOneWidget);
    });

    testWidgets(
        'renders Question Navigator button when questions exist, opens bottom sheet',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Exam Solutions',
            rawContent: '''
# Exam Solutions Guide

### Question 1 [Marks: 10]
Answer to question 1.

### Question 2 [Marks: 10]
Answer to question 2.
''',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.format_list_bulleted_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Question Navigator'), findsOneWidget);
      expect(find.text('Question 1 [Marks: 10]'), findsNWidgets(2));
      expect(find.text('Question 2 [Marks: 10]'), findsNWidgets(2));
    });

    testWidgets(
        'renders bilingual toggle and switches between English and Bangla solutions on tap on mobile',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: '98th BPE - Accounting (English)',
            rawContent: '### Question 1\nEnglish answer here.',
            alternateRawContent: '### প্রশ্ন ১\nবাংলা সমাধান এখানে।',
            alternateTitle: '৯৮তম বিপিই - অ্যাকাউন্টিং (বাংলা)',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('বাংলা'), findsOneWidget);
      expect(find.textContaining('English answer here.'), findsOneWidget);

      await tester.tap(find.text('বাংলা'));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.textContaining('বাংলা সমাধান এখানে।'), findsOneWidget);
    });

    testWidgets(
        'renders dual-language synchronized split reader on wide screens and toggles mode',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: '98th BPE - Accounting (English)',
            rawContent: '### Question 1\nEnglish answer here.',
            alternateRawContent: '### প্রশ্ন ১\nবাংলা সমাধান এখানে।',
            alternateTitle: '৯৮তম বিপিই - অ্যাকাউন্টিং (বাংলা)',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In split view, both pane headers and content are visible concurrently
      expect(find.text('English Solution'), findsOneWidget);
      expect(find.text('বাংলা সমাধান'), findsOneWidget);
      expect(find.textContaining('English answer here.'), findsOneWidget);
      expect(find.textContaining('বাংলা সমাধান এখানে।'), findsOneWidget);
      expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);

      // Toggle to single-column mode
      await tester.tap(find.byIcon(Icons.view_agenda_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.vertical_split_rounded), findsOneWidget);
      expect(find.text('বাংলা'), findsOneWidget);

      // Toggle back to split view
      await tester.tap(find.byIcon(Icons.vertical_split_rounded));
      await tester.pumpAndSettle();

      expect(find.text('English Solution'), findsOneWidget);
      expect(find.text('বাংলা সমাধান'), findsOneWidget);
    });

    testWidgets(
        'extracts question topic and renders in navigator sheet subtitle',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: '97th BPE Solution',
            chapterTitle: '97th BPE (Nov 2023)',
            subjectTitle: 'Laws & Practice of General Banking',
            rawContent:
                '### প্রশ্ন ৮ [মান: ২০]\n৮(ক) উত্তরাধিকার পরিকল্পনা (Succession Planning) বলতে কী বুঝায়?\nউত্তর বিবরণ।',
          ),
          theme: ThemeData.light(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.text('97th BPE (Nov 2023) · 97th BPE Solution'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(ListTile, 'প্রশ্ন ৮ [মান: ২০]'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find
              .textContaining('উত্তরাধিকার পরিকল্পনা (Succession Planning)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'adapts AppBar title and Question Navigator contrast in Light mode',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Light Mode Title',
            rawContent: '### Question 1 [Marks: 10]\nAnswer here.',
          ),
          theme: ThemeData.light(),
        ),
      );
      await tester.pumpAndSettle();

      final titleText = tester.widget<Text>(find.text('Light Mode Title'));
      expect(titleText.style?.color, AppColors.darkText);

      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      final sheetTitle = tester.widget<Text>(find.text('Question Navigator'));
      expect(sheetTitle.style?.color, AppColors.darkText);
    });

    testWidgets('uses white title and Question Navigator text in Dark mode',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Dark Mode Title',
            rawContent: '### Question 1 [Marks: 10]\nAnswer here.',
          ),
          theme: ThemeData.dark(),
        ),
      );
      await tester.pumpAndSettle();

      final titleText = tester.widget<Text>(find.text('Dark Mode Title'));
      expect(titleText.style?.color, Colors.white);

      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      final sheetTitle = tester.widget<Text>(find.text('Question Navigator'));
      expect(sheetTitle.style?.color, Colors.white);
    });

    testWidgets(
        'renders syllabus module filter chips in Question Navigator and filters questions by module',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: 'Laws & Practice of General Banking',
            rawContent: '''
### Question 1 [Marks: 10]
Explain the Bank Company Act 1991 provisions.

### Question 2 [Marks: 10]
What are the KYC procedures for opening an account?

### Question 3 [Marks: 10]
Explain special crossing of a cheque under NI Act.
''',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Question Navigator
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      // Module chips should be present
      expect(find.text('All Modules'), findsOneWidget);
      expect(find.text('Module A'), findsOneWidget);
      expect(find.text('Module B'), findsOneWidget);
      expect(find.text('Module C'), findsOneWidget);

      // Question 1 has Mod A badge, Question 2 has Mod B badge, Question 3 has Mod C badge
      expect(find.text('Mod A'), findsOneWidget);
      expect(find.text('Mod B'), findsOneWidget);
      expect(find.text('Mod C'), findsOneWidget);

      // Filter by Module A
      await tester.tap(find.text('Module A'));
      await tester.pumpAndSettle();

      final bottomSheet = find.byType(BottomSheet);

      // Question 1 should be visible in bottom sheet, while Question 2 and Question 3 should be filtered out
      expect(
        find.descendant(
            of: bottomSheet, matching: find.textContaining('Question 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: bottomSheet, matching: find.textContaining('Question 2')),
        findsNothing,
      );
      expect(
        find.descendant(
            of: bottomSheet, matching: find.textContaining('Question 3')),
        findsNothing,
      );

      // Select All Modules again
      await tester.tap(find.text('All Modules'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
            of: bottomSheet, matching: find.textContaining('Question 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: bottomSheet, matching: find.textContaining('Question 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: bottomSheet, matching: find.textContaining('Question 3')),
        findsOneWidget,
      );
    });

    testWidgets(
        'jumps to a distant question in split view and scrolls both panes simultaneously',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Build 50 questions for primary and alternate content
      final primaryBuilder = StringBuffer();
      final alternateBuilder = StringBuffer();
      for (int i = 1; i <= 50; i++) {
        primaryBuilder.writeln('### Question $i [Marks: 10]');
        primaryBuilder
            .writeln('Detailed answer paragraph for English question $i.\n\n');
        alternateBuilder.writeln('### প্রশ্ন $i [মান: ১০]');
        alternateBuilder
            .writeln('বাংলা সমাধান অনুচ্ছেদ প্রশ্ন $i এর জন্য।\n\n');
      }

      await tester.pumpWidget(
        buildTestApp(
          MarkdownViewerScreen(
            title: 'Long Exam Paper (English)',
            rawContent: primaryBuilder.toString(),
            alternateRawContent: alternateBuilder.toString(),
            alternateTitle: 'দীর্ঘ পরীক্ষার প্রশ্নপত্র (বাংলা)',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Question Navigator bottom sheet
      await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Question Navigator'), findsOneWidget);

      // Scroll bottom sheet to find Question 40 item in the bottom sheet
      final bottomSheetFinder = find.byType(BottomSheet);
      final question40Finder = find.descendant(
        of: bottomSheetFinder,
        matching: find.textContaining('Question 40'),
      );
      await tester.scrollUntilVisible(
        question40Finder,
        300,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(question40Finder, findsOneWidget);

      await tester.tap(question40Finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Verify that both split panes scrolled down significantly past 0
      final scrollables = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .toList();
      expect(scrollables.length, greaterThanOrEqualTo(2));
      expect(scrollables[0].controller!.offset, greaterThan(200.0));
      expect(scrollables[1].controller!.offset, greaterThan(200.0));
    });

    testWidgets(
        'toggles language button between Bangla and English in single view',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          const MarkdownViewerScreen(
            title: '৭ম ব্যাংকিং প্রফেশনাল পরীক্ষা (বাংলা সমাধান)',
            rawContent: '### প্রশ্ন ১\nবাংলা উত্তর বিবরণ।',
            alternateRawContent: '### Question 1\nEnglish answer details.',
            alternateTitle: '7th Banking Exam (English Solution)',
            alternateLanguageLabel: 'English',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially showing Bangla, so the button should offer to switch to English
      expect(find.text('English'), findsOneWidget);
      expect(find.text('৭ম ব্যাংকিং প্রফেশনাল পরীক্ষা (বাংলা সমাধান)'),
          findsOneWidget);

      // Tap to switch to English
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      // Now showing English, button should offer to switch to Bangla
      expect(find.text('বাংলা'), findsOneWidget);
      expect(find.text('7th Banking Exam (English Solution)'), findsOneWidget);

      // Tap to switch back to Bangla
      await tester.tap(find.text('বাংলা'));
      await tester.pumpAndSettle();

      // Back to offering English
      expect(find.text('English'), findsOneWidget);
      expect(find.text('৭ম ব্যাংকিং প্রফেশনাল পরীক্ষা (বাংলা সমাধান)'),
          findsOneWidget);
    });
  });

  group('PdfViewerScreen', () {
    testWidgets('adapts AppBar title color in Light and Dark mode',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const PdfViewerScreen(
            title: 'Light Document.pdf',
          ),
          theme: ThemeData.light(),
        ),
      );
      await tester.pumpAndSettle();

      final lightTitle = tester.widget<Text>(find.text('Light Document.pdf'));
      expect(lightTitle.style?.color, AppColors.darkText);

      await tester.pumpWidget(
        buildTestApp(
          const PdfViewerScreen(
            title: 'Dark Document.pdf',
          ),
          theme: ThemeData.dark(),
        ),
      );
      await tester.pumpAndSettle();

      final darkTitle = tester.widget<Text>(find.text('Dark Document.pdf'));
      expect(darkTitle.style?.color, Colors.white);
    });

    testWidgets('renders PDF badge in AppBar and error state for invalid input',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const PdfViewerScreen(
            title: 'Document.pdf',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Document.pdf'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders localized Bengali title and retry button on error',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const PdfViewerScreen(
            title: '',
          ),
          locale: const Locale('bn'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('পিডিএফ ডকুমেন্ট'), findsOneWidget);
      expect(find.text('আবার চেষ্টা করুন'), findsOneWidget);
    });
  });
}
