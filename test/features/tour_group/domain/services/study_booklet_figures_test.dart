import 'package:bhromon/features/tour_group/domain/services/ppc_curve.dart';
import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

const _chart = '```chart:ppc\n'
    'title: উৎপাদন সম্ভাবনা সীমা\n'
    'x: কৃষিপণ্য\n'
    'y: শিল্পপণ্য\n'
    'xmax: 100\n'
    'ymax: 80\n'
    'point A: 20 70\n'
    '```';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const generator = StudyBookletPdfGenerator();

  group('solutionPieces', () {
    test('a solution with no figure is one prose piece, its Markdown kept', () {
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        '**উত্তর**: ব্যাংক একটি প্রতিষ্ঠান।',
      );

      expect(pieces, hasLength(1));
      final text = pieces.single as StudyBookletText;
      expect(text.text, '**উত্তর**: ব্যাংক একটি প্রতিষ্ঠান।');
    });

    test('a chart between two paragraphs sits between them', () {
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        'প্রথম অংশ।\n\n$_chart\n\nশেষ অংশ।',
      );

      expect(pieces, hasLength(3));
      expect((pieces[0] as StudyBookletText).text, contains('প্রথম অংশ'));
      final figure = pieces[1] as StudyBookletFigure;
      expect(figure.spec.xMax, 100);
      expect(figure.spec.points.single.label, 'A');
      expect((pieces[2] as StudyBookletText).text, contains('শেষ অংশ'));
    });

    test('two charts give text, figure, text, figure, text', () {
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        '$_chart\n\nমাঝখানে।\n\n$_chart',
      );

      // Empty prose before the first chart and after the last is dropped.
      expect(pieces.map((p) => p.runtimeType), [
        StudyBookletFigure,
        StudyBookletText,
        StudyBookletFigure,
      ]);
    });

    test('a chart fence that does not parse stays in the prose', () {
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        '```chart:ppc\nxmax: 100\n```',
      );

      expect(pieces.whereType<StudyBookletFigure>(), isEmpty);
      expect(
        pieces.whereType<StudyBookletText>().single.text,
        contains('xmax: 100'),
      );
    });

    test('other code fences are cleaned as prose, not drawn', () {
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        '```dart\nprint(1);\n```',
      );

      expect(pieces.whereType<StudyBookletFigure>(), isEmpty);
    });

    test('CRLF line endings still find the chart', () {
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        _chart.replaceAll('\n', '\r\n'),
      );

      expect(pieces.whereType<StudyBookletFigure>(), hasLength(1));
    });

    test('an svg code fence becomes a StudyBookletSvgFigure', () {
      const svg =
          '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40"/></svg>';
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        'শুরু।\n\n```svg\n$svg\n```\n\nশেষ।',
      );

      expect(pieces, hasLength(3));
      expect(pieces[0], isA<StudyBookletText>());
      expect(pieces[1], isA<StudyBookletSvgFigure>());
      expect((pieces[1] as StudyBookletSvgFigure).svg, svg);
      expect(pieces[2], isA<StudyBookletText>());
    });

    test('a div-wrapped svg element becomes a StudyBookletSvgFigure', () {
      const svg =
          '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40"/></svg>';
      final pieces = StudyBookletPdfGenerator.solutionPieces(
        'ব্যাখ্যা শুরু।\n\n<div class="svg-diagram" style="margin:14px 0;">$svg</div>\n\nব্যাখ্যা শেষ।',
      );

      expect(pieces, hasLength(3));
      expect(pieces[0], isA<StudyBookletText>());
      expect(pieces[1], isA<StudyBookletSvgFigure>());
      expect((pieces[1] as StudyBookletSvgFigure).svg, svg);
      expect(pieces[2], isA<StudyBookletText>());
    });
  });

  group('StudyBookletQuestionItem', () {
    test('solutionText is the prose alone, joined, without figures', () {
      const item = StudyBookletQuestionItem(
        questionNumber: '1',
        title: 'Q',
        pieces: [
          StudyBookletText('প্রথম।'),
          StudyBookletFigure(PpcSpec(xMax: 100, yMax: 80)),
          StudyBookletText('দ্বিতীয়।'),
        ],
      );

      expect(item.solutionText, 'প্রথম।\n\nদ্বিতীয়।');
    });
  });

  test('generateBookletPdf draws a question with a chart into a valid PDF',
      () async {
    final pieces = StudyBookletPdfGenerator.solutionPieces(
      'ব্যাখ্যা।\n\n$_chart\n\nসমাপ্তি।',
    );
    final content = StudyBookletContent(
      subjectTitle: 'Economics',
      tourName: 'Study Circle',
      chapters: [
        StudyBookletChapterItem(
          number: 1,
          title: 'Production',
          questions: [
            StudyBookletQuestionItem(
              questionNumber: '1',
              title: 'Question 1: Production possibility',
              pieces: pieces,
            ),
          ],
        ),
      ],
    );

    final bytes = await generator.generateBookletPdf(content, isBengali: true);

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });
}
