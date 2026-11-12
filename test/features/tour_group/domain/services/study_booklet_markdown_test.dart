import 'dart:typed_data';

import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:bhromon/features/tour_group/domain/services/study_booklet_markdown.dart';
import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every widget under [widgets], depth first, including those inside padding, containers, rows,
/// columns, centres, flexible children, table rows and sized boxes.
Iterable<pw.Widget> _walk(Iterable<pw.Widget?> widgets) sync* {
  for (final widget in widgets) {
    if (widget == null) continue;
    yield widget;
    if (widget is pw.Table) {
      for (final row in widget.children) {
        yield* _walk(row.children);
      }
    } else if (widget is pw.Flex) {
      yield* _walk(widget.children);
    } else if (widget is pw.Padding) {
      yield* _walk([widget.child]);
    } else if (widget is pw.Container) {
      yield* _walk([widget.child]);
    } else if (widget is pw.Center) {
      yield* _walk([widget.child]);
    } else if (widget is pw.Flexible) {
      yield* _walk([widget.child]);
    } else if (widget is pw.SizedBox) {
      yield* _walk([widget.child]);
    }
  }
}

/// The text each widget draws, in order.
List<String> _texts(Iterable<pw.Widget?> widgets) => [
      for (final widget in _walk(widgets))
        if (widget is pw.RichText)
          widget.text.toPlainText()
        else if (widget is pw.Text)
          widget.text,
    ];

/// The number of pages in a PDF file, counted from its page objects.
int _pageCount(Uint8List bytes) => RegExp(r'/Type\s*/Page(?!s)')
    .allMatches(String.fromCharCodes(bytes))
    .length;

/// A booklet with one question whose solution is [markdown].
StudyBookletContent _contentWith(String markdown) => StudyBookletContent(
      subjectTitle: 'Laws and Practice of General Banking',
      tourName: 'Study Circle',
      chapters: [
        StudyBookletChapterItem(
          number: 1,
          title: 'Chapter',
          questions: [
            StudyBookletQuestionItem(
              questionNumber: '1',
              title: 'প্রশ্ন ১',
              pieces: [StudyBookletText(markdown)],
            ),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('studyBookletMarkdownWidgets', () {
    test('a heading loses its hashes and is drawn bold', () {
      final widgets = studyBookletMarkdownWidgets('#### দ্বিতীয় অংশ');

      expect(_texts(widgets), ['দ্বিতীয় অংশ']);
      final heading = _walk(widgets).whereType<pw.Text>().single;
      expect(heading.style?.fontWeight, pw.FontWeight.bold);
    });

    test('a pipe table is drawn as a table, with no pipes or separator left',
        () {
      final widgets = studyBookletMarkdownWidgets(
        '| সুবিধা (Advantages) | অসুবিধা (Disadvantages) |\n'
        '| :--- | :--- |\n'
        '| এক | দুই |\n'
        '| তিন | চার |',
      );

      expect(_walk(widgets).whereType<pw.Table>(), hasLength(1));
      expect(
        _texts(widgets),
        containsAll(['সুবিধা (Advantages)', 'এক', 'চার']),
      );
      expect(
        _texts(widgets)
            .any((text) => text.contains('|') || text.contains(':---')),
        isFalse,
      );
    });

    test('a long table is cut into tables that repeat the header, in row order',
        () {
      final rows = [for (var i = 1; i <= 40; i++) '| সারি $i | মান $i |'];
      final widgets = studyBookletMarkdownWidgets(
        ['| শিরোনাম A | শিরোনাম B |', '| --- | --- |', ...rows].join('\n'),
      );

      final tables = _walk(widgets).whereType<pw.Table>().toList();
      expect(tables.length, greaterThan(1));
      for (final table in tables) {
        expect(
          _texts(table.children.first.children),
          ['শিরোনাম A', 'শিরোনাম B'],
        );
      }
      final body = [
        for (final table in tables)
          for (final row in table.children.skip(1)) ..._texts(row.children),
      ];
      expect(body, [
        for (var i = 1; i <= 40; i++) ...['সারি $i', 'মান $i']
      ]);
    });

    test('a long cell is cut into fragments that keep every word, in order',
        () {
      final words = [for (var i = 0; i < 3000; i++) 'শব্দ$i'];
      final widgets = studyBookletMarkdownWidgets(
        '| শিরোনাম | বিবরণ |\n| --- | --- |\n| এক | ${words.join(' ')} |',
      );

      final tables = _walk(widgets).whereType<pw.Table>().toList();
      expect(tables.length, greaterThan(1));
      final kept = [
        for (final table in tables)
          for (final row in table.children.skip(1))
            for (final text in _texts([row.children[1]])) ...text.split(' '),
      ].where((word) => word.isNotEmpty).toList();
      expect(kept, words);
    });

    test('a table whose header is too long to repeat is laid out as records',
        () {
      final header = List.filled(200, 'শিরোনাম').join(' ');
      final widgets = studyBookletMarkdownWidgets(
        '| $header | দ্বিতীয় |\n| --- | --- |\n| এক | দুই |',
      );

      expect(_walk(widgets).whereType<pw.Table>(), isEmpty);
      final texts = _texts(widgets);
      expect(texts.any((text) => text.endsWith(': এক')), isTrue);
      expect(texts.any((text) => text.endsWith(': দুই')), isTrue);
    });

    test('a quote keeps its bar and its list, with no marker left in the text',
        () {
      final widgets = studyBookletMarkdownWidgets(
        '> উপ-প্রশ্ন:\n> - প্রথম বিন্দু\n> - দ্বিতীয় বিন্দু',
      );
      final texts = _texts(widgets);

      expect(
        texts,
        containsAll(['উপ-প্রশ্ন:', 'প্রথম বিন্দু', 'দ্বিতীয় বিন্দু']),
      );
      expect(
        texts.any((text) => text.startsWith('>') || text.startsWith('- ')),
        isFalse,
      );
      expect(texts.where((text) => text == '•'), hasLength(2));
      final bars = _walk(widgets).whereType<pw.Container>().where((box) {
        final decoration = box.decoration;
        if (decoration is! pw.BoxDecoration) return false;
        final border = decoration.border;
        return border is pw.Border && border.left.width > 0;
      });
      expect(bars, isNotEmpty);
    });

    test('a rule is drawn as a line and no dashes are printed', () {
      final widgets = studyBookletMarkdownWidgets('প্রথম।\n\n---\n\nদ্বিতীয়।');

      expect(_walk(widgets).whereType<pw.Divider>(), hasLength(1));
      expect(_texts(widgets), ['প্রথম।', 'দ্বিতীয়।']);
    });

    test('bold is drawn bold, and the markers of bold and italic go', () {
      final widgets = studyBookletMarkdownWidgets(
        '**উত্তর**: *(Explain the rule)* আর বাকি।',
      );

      expect(_texts(widgets), ['উত্তর: (Explain the rule) আর বাকি।']);
      final root =
          _walk(widgets).whereType<pw.RichText>().single.text as pw.TextSpan;
      final runs = root.children!.cast<pw.TextSpan>();
      final bold = runs.firstWhere((run) => run.text == 'উত্তর');
      expect(bold.style?.fontWeight, pw.FontWeight.bold);
    });

    test('a numbered list keeps its numbers', () {
      final widgets = studyBookletMarkdownWidgets('1. প্রথম\n2. দ্বিতীয়');

      expect(_texts(widgets), containsAll(['1.', 'প্রথম', '2.', 'দ্বিতীয়']));
    });

    test(
        'a long paragraph is cut into widgets that each stay within the budget',
        () {
      final lines = [
        for (var i = 0; i < 400; i++)
          'বাক্য $i: ব্যাংক কোম্পানি আইন ১৯৯১ এবং বাংলাদেশ ব্যাংকের নির্দেশনাবলী অনুসারে তফসিলি ব্যাংক।',
      ];
      final widgets = studyBookletMarkdownWidgets(lines.join('\n'));

      final columns = _walk(widgets).whereType<pw.Column>().toList();
      expect(columns.length, greaterThan(1));
      for (final column in columns) {
        var linesTaken = 0;
        for (final child in column.children) {
          final text = _texts([child]).single;
          linesTaken += (text.length / studyBookletCharsPerLine).ceil();
        }
        expect(linesTaken, lessThanOrEqualTo(studyBookletBlockLines));
      }
    });
  });

  group('studyBookletCleanText', () {
    test('characters the bundled fonts cannot draw are replaced', () {
      expect(
        studyBookletCleanText('A → B ⇒ C ☐ ☑ D E​'),
        'A — B — C [ ] [x] D E',
      );
    });
  });

  group('studyBookletCleanSolution', () {
    test('HTML comments are removed and blank runs are cut to one', () {
      expect(
        studyBookletCleanSolution('প্রথম\n\n\n\n<!-- নোট -->\nদ্বিতীয়'),
        'প্রথম\n\nদ্বিতীয়',
      );
    });
  });

  group('the booklet PDF', () {
    test('a table cell far longer than a page is laid out across pages',
        () async {
      final cell = List.filled(6000, 'শব্দ').join(' ');
      final bytes = await const StudyBookletPdfGenerator().generateBookletPdf(
        _contentWith('| শিরোনাম | বিবরণ |\n| --- | --- |\n| এক | $cell |'),
        isBengali: true,
      );

      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(_pageCount(bytes), greaterThan(2));
    });

    test('a solution with the Markdown of the app builds a valid PDF',
        () async {
      const solution = '''
> - ২(খ) তারল্য কী? *(Define liquidity.)* [মান: ২ + ৮ = ৬]

---

#### ২(ক) নগদ পরিশোধ ব্যবস্থার সুবিধা-অসুবিধা

> উপ-প্রশ্ন ২(ক): নগদ পরিশোধ ব্যবস্থার সুবিধাগুলো উল্লেখ করুন।

উত্তর:

| সুবিধা (Advantages) | অসুবিধা (Disadvantages) |
| :--- | :--- |
| সর্বজনীন গ্রহণযোগ্যতা: নোট ও ধাতব মুদ্রা আইনগত গ্রহীতা। | উচ্চ ব্যয়: নোট ছাপানো ও পরিবহন ব্যয়বহুল। |

1. প্রথম অংশ **গুরুত্বপূর্ণ** বিষয়।
2. দ্বিতীয় অংশ → যা ☐ চিহ্নিত।
''';
      final bytes = await const StudyBookletPdfGenerator().generateBookletPdf(
        _contentWith(solution),
        isBengali: true,
      );

      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    });
  });
}
