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
        'renders bilingual toggle and switches between English and Bangla solutions on tap',
        (tester) async {
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

      expect(find.text('🇧🇩 বাংলা'), findsOneWidget);
      expect(find.textContaining('English answer here.'), findsOneWidget);

      await tester.tap(find.text('🇧🇩 বাংলা'));
      await tester.pumpAndSettle();

      expect(find.text('🇬🇧 English'), findsOneWidget);
      expect(find.textContaining('বাংলা সমাধান এখানে।'), findsOneWidget);
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
