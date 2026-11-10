import 'package:bhromon/features/tour_group/domain/services/study_file_reader_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which reader opens a study file', () {
    test('a Markdown or text file opens in the Markdown reader', () {
      expect(studyFileReader('Solutions.md'), StudyFileReader.markdown);
      expect(studyFileReader('notes.txt'), StudyFileReader.markdown);
      expect(studyFileReader('run.log'), StudyFileReader.markdown);
    });

    test('a PDF opens in the PDF viewer, whatever its letter case', () {
      expect(studyFileReader('Paper.PDF'), StudyFileReader.pdf);
    });

    test('an address is read by its path, not its query', () {
      const url =
          'https://bhromon.fun/media/T/study/0123456789abcdef0123456789abcdef.pdf?u=abc&s=def';
      expect(studyFileReader(url), StudyFileReader.pdf);
    });

    test('other files are not read in the app', () {
      expect(studyFileReader('Talk.mp3'), StudyFileReader.none);
      expect(studyFileReader('Slides.pptx'), StudyFileReader.none);
      expect(studyFileReader('https://example.com/page'), StudyFileReader.none);
    });

    test('a name that only contains .pdf is not a PDF', () {
      expect(studyFileReader('pdf-notes.docx'), StudyFileReader.none);
    });
  });
}
