import 'package:bhromon/features/tour_group/data/study_pack_pdf.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_summary_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_pack_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The study pack as a PDF. The bundled Bengali fonts load in the test as they do for the tour record, so a pack with
// Bengali text makes a real PDF file.

const _labels = StudyPackLabels(
  summaries: 'Chapter summaries',
  answers: 'Accepted answers',
  glossary: 'Glossary',
  recaps: 'Session recaps',
  materials: 'Published materials',
  covered: 'Covered',
  hard: 'Hard',
  openQuestions: 'Open question',
  link: 'Link',
  footer: 'From the study pack in Bhromon.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a study pack with Bengali text makes a PDF file', () async {
    final pack = buildStudyPack(
      book: const StudyBook(id: 'b1', title: 'আনা কারেনিনা'),
      chapters: [
        const StudyChapter(
            id: 'c1', number: 1, title: 'প্রথম ভাগ', pinnedSummaryId: 'r1'),
      ],
      revisionsByChapter: {
        'c1': [
          StudySummaryRevision(
            id: 'r1',
            text: 'আনা ও ভ্রনস্কি স্টেশনে দেখা করেন।',
            editorEmail: 'a@x.com',
            createdAt: DateTime(2026, 2, 1),
          ),
        ],
      },
      acceptedAnswers: const [],
      glossary: const [],
      sessions: const [],
      materials: const [],
    );

    final bytes = await buildStudyPackPdf(pack, _labels);

    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
