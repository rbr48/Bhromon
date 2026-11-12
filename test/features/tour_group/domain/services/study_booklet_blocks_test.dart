import 'dart:typed_data';

import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bengali solution prose of about [chars] characters, one sentence per line.
String _prose(int chars) {
  const sentence =
      'ব্যাংক কোম্পানি আইন ১৯৯১ এবং বাংলাদেশ ব্যাংকের নির্দেশনাবলী অনুসারে তফসিলি ব্যাংকের লাইসেন্সিং প্রক্রিয়া সম্পন্ন হয়।';
  final buf = StringBuffer();
  var i = 0;
  while (buf.length < chars) {
    buf.writeln('$sentence ($i)');
    i++;
  }
  return buf.toString();
}

/// The number of pages in a PDF file, counted from its page objects.
int _pageCount(Uint8List bytes) => RegExp(r'/Type\s*/Page(?!s)')
    .allMatches(String.fromCharCodes(bytes))
    .length;

/// The lines a block takes on the page, estimated the way the generator estimates them.
int _estimatedLines(String block) {
  var lines = 0;
  for (final line in block.split('\n')) {
    lines += line.isEmpty ? 1 : (line.length / 80).ceil();
  }
  return lines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StudyBookletPdfGenerator.proseBlocks', () {
    test('keeps every line in order, so the blocks join back to the text', () {
      const text = 'প্রথম লাইন\nদ্বিতীয় লাইন\n\nতৃতীয় লাইন';
      final blocks = StudyBookletPdfGenerator.proseBlocks(text);
      expect(blocks.join('\n'), text);
    });

    test('a short text is one block', () {
      expect(StudyBookletPdfGenerator.proseBlocks('a\nb'), ['a\nb']);
    });

    test('an empty text is one empty block', () {
      expect(StudyBookletPdfGenerator.proseBlocks(''), ['']);
    });

    test('every block stays within the line budget', () {
      final blocks = StudyBookletPdfGenerator.proseBlocks(_prose(60000));
      expect(blocks.length, greaterThan(1));
      for (final block in blocks) {
        expect(_estimatedLines(block), lessThanOrEqualTo(24));
      }
    });

    test('a line longer than a block is cut at spaces and loses no words', () {
      final words = [for (var i = 0; i < 900; i++) 'শব্দ$i'];
      final blocks = StudyBookletPdfGenerator.proseBlocks(words.join(' '));
      expect(blocks.length, greaterThan(1));
      final kept = blocks
          .join(' ')
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      expect(kept, words);
      for (final block in blocks) {
        expect(_estimatedLines(block), lessThanOrEqualTo(24));
      }
    });
  });

  test('a question with a long solution lays out across pages, not failing',
      () async {
    // Before the blocks, a solution this long was one block taller than a page. The layout
    // retried it on every new page and gave up with a PdfTooBigPageException after 20.
    final content = StudyBookletContent(
      subjectTitle: 'Probe',
      tourName: 'Probe',
      chapters: [
        StudyBookletChapterItem(
          number: 1,
          title: 'Chapter',
          questions: [
            StudyBookletQuestionItem(
              questionNumber: '1',
              title: 'Q1',
              pieces: [StudyBookletText(_prose(60000))],
            ),
          ],
        ),
      ],
    );

    final bytes = await const StudyBookletPdfGenerator()
        .generateBookletPdf(content, isBengali: true);

    expect(_pageCount(bytes), greaterThan(3));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
