import 'package:bhromon/features/tour_group/domain/services/study_booklet_pdf_generator.dart';
import 'package:flutter_test/flutter_test.dart';

// A figure whose labels carry arrows, subscripts or Bengali used to stop the whole booklet. The
// built-in font cannot draw those characters, and the error came when the document was saved, after
// the figure had been placed, so the booklet failed with no page to show.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'a booklet with a figure whose labels carry arrows and Bengali is laid out',
      () async {
    final fonts = await StudyBookletPdfGenerator.loadFonts();
    const content = StudyBookletContent(
      subjectTitle: 'Principles of Economics',
      tourName: 'Probe Circle',
      scopedToChapter: true,
      chapters: [
        StudyBookletChapterItem(
          number: 1,
          title: 'Demand',
          questions: [
            StudyBookletQuestionItem(
              questionNumber: '1',
              title: 'Demand shift',
              pieces: [
                StudyBookletSvgFigure(
                  '<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">'
                  '<text x="10" y="20">D₁ → D₂ (ΔQ) চাহিদা</text></svg>',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final bytes = await StudyBookletPdfGenerator.layoutJob(
      StudyBookletJob(
        content: content,
        isBengali: true,
        regularFont: fonts.regular,
        boldFont: fonts.bold,
      ),
      pauseBetweenChapters: false,
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
