import 'package:bhromon/features/tour_group/data/study_booklet_isolate.dart';
import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

// The chapter screen lays booklets out through layoutBookletJob. The layout itself is checked in
// study_booklet_pdf_generator_test.dart; these check the background run around it.

const _content = StudyBookletContent(
  subjectTitle: 'Principles of Economics',
  tourName: 'Probe Circle',
  inviteCode: 'PROBE2026',
  chapters: [
    StudyBookletChapterItem(
      number: 1,
      title: 'First',
      questions: [
        StudyBookletQuestionItem(
          questionNumber: '1',
          title: 'Question 1',
          pieces: [StudyBookletText('A short model answer.')],
        ),
      ],
    ),
    StudyBookletChapterItem(
      number: 2,
      title: 'Second',
      questions: [
        StudyBookletQuestionItem(
          questionNumber: '1',
          title: 'Question 1',
          pieces: [StudyBookletText('Another short answer.')],
        ),
      ],
    ),
  ],
);

Future<StudyBookletJob> _job() async {
  final fonts = await StudyBookletPdfGenerator.loadFonts();
  return StudyBookletJob(
    content: _content,
    isBengali: true,
    regularFont: fonts.regular,
    boldFont: fonts.bold,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layoutBookletJob', () {
    test('lays the booklet out in the background and reports each chapter',
        () async {
      final reported = <(int, int)>[];

      final bytes = await layoutBookletJob(
        await _job(),
        onProgress: (done, total) => reported.add((done, total)),
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(reported, [(0, 2), (1, 2), (2, 2)]);
    });

    test('a booklet cancelled before it starts is not laid out', () async {
      await expectLater(
        layoutBookletJob(await _job(), isCancelled: () => true),
        throwsA(isA<StudyBookletCancelled>()),
      );
    });
  });
}
