import 'dart:convert';
import 'dart:io';

import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

// Every graph of the POE atlas is a figure a solution can carry. Each one must lay out in a booklet.
// Before the label fix, 78 of the 95 stopped the booklet with "Contains invalid characters".

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every POE atlas graph lays out in a booklet', () async {
    final atlas = jsonDecode(
      File('assets/study/poe_graph_atlas.json').readAsStringSync(),
    ) as List<dynamic>;
    final fonts = await StudyBookletPdfGenerator.loadFonts();
    final failed = <String>[];

    for (final entry in atlas) {
      final graph = entry as Map<String, dynamic>;
      final content = StudyBookletContent(
        subjectTitle: 'Principles of Economics',
        tourName: 'Probe Circle',
        scopedToChapter: true,
        chapters: [
          StudyBookletChapterItem(
            number: 1,
            title: 'Graph',
            questions: [
              StudyBookletQuestionItem(
                questionNumber: '1',
                title: 'Graph',
                pieces: [StudyBookletSvgFigure(graph['svg'] as String)],
              ),
            ],
          ),
        ],
      );
      try {
        await StudyBookletPdfGenerator.layoutJob(
          StudyBookletJob(
            content: content,
            isBengali: true,
            regularFont: fonts.regular,
            boldFont: fonts.bold,
          ),
          pauseBetweenChapters: false,
        );
      } catch (error) {
        failed.add('${graph['id']}: $error');
      }
    }

    expect(failed, isEmpty, reason: failed.join('\n'));
  });
}
