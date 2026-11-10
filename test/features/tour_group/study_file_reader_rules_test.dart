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

  group('which study files open in the app', () {
    const folder = 'https://bhromon.fun/media/T/study/';
    const name = '0123456789abcdef0123456789abcdef.pdf';

    test("a file in this group's study folder does", () {
      expect(isStudyFolderFile('$folder$name', 'T'), isTrue);
    });

    test('a signed address of such a file does too', () {
      expect(isStudyFolderFile('$folder$name?u=abc&s=def', 'T'), isTrue);
    });

    test('another group, folder or host, or a deeper path, does not', () {
      expect(isStudyFolderFile('https://bhromon.fun/media/U/study/$name', 'T'),
          isFalse);
      expect(isStudyFolderFile('https://bhromon.fun/media/T/posts/$name', 'T'),
          isFalse);
      expect(isStudyFolderFile('https://example.com/media/T/study/$name', 'T'),
          isFalse);
      expect(isStudyFolderFile('${folder}sub/$name', 'T'), isFalse);
    });

    test('an empty name or an empty group does not count', () {
      expect(isStudyFolderFile(folder, 'T'), isFalse);
      expect(isStudyFolderFile('$folder$name', ''), isFalse);
    });
  });
}
