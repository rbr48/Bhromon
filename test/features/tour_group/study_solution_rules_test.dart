import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_solution_rules.dart';
import 'package:flutter_test/flutter_test.dart';

StudyMaterial _material({
  String title = 'Solutions',
  StudyMaterialKind kind = StudyMaterialKind.note,
  String? body,
  String? url,
  String? fileName,
  int? sizeBytes,
}) =>
    StudyMaterial(
      id: 'm',
      title: title,
      kind: kind,
      bookId: 'b1',
      chapterId: 'c1',
      status: StudyMaterialStatus.published,
      body: body,
      url: url,
      fileName: fileName,
      sizeBytes: sizeBytes,
    );

const _mdUrl =
    'https://bhromon.fun/media/T/study/0123456789abcdef0123456789abcdef.md';

void main() {
  group('which materials open as a solution', () {
    test('a note with text opens', () {
      expect(isReadableSolution(_material(body: 'Answer one.')), isTrue);
    });

    test('a note with no text does not open', () {
      expect(isReadableSolution(_material(body: null)), isFalse);
      expect(isReadableSolution(_material(body: '   ')), isFalse);
    });

    test('a Markdown file with an address opens', () {
      expect(
        isReadableSolution(_material(
          kind: StudyMaterialKind.file,
          url: _mdUrl,
          fileName: 'Solutions.md',
        )),
        isTrue,
      );
    });

    test('a Markdown file with no address does not open', () {
      expect(
        isReadableSolution(_material(
          kind: StudyMaterialKind.file,
          fileName: 'Solutions.md',
        )),
        isFalse,
      );
    });

    test('a PDF, a link or an audio file does not open', () {
      expect(
        isReadableSolution(_material(
          kind: StudyMaterialKind.file,
          url: _mdUrl,
          fileName: 'Paper.pdf',
        )),
        isFalse,
      );
      expect(
        isReadableSolution(_material(
          kind: StudyMaterialKind.link,
          url: 'https://example.com/solutions',
        )),
        isFalse,
      );
      expect(
        isReadableSolution(_material(
          kind: StudyMaterialKind.audio,
          url: _mdUrl,
          fileName: 'Talk.md',
        )),
        isFalse,
      );
    });
  });

  group('where the reader gets a solution', () {
    test('a note gives its text', () {
      final source = solutionSource(_material(body: 'Answer one.'), null);
      expect(source.rawContent, 'Answer one.');
      expect(source.fileUrl, isNull);
      expect(source.paired, isNull);
    });

    test('a Markdown file gives its address, and the reader fetches it', () {
      final source = solutionSource(
        _material(
          kind: StudyMaterialKind.file,
          url: _mdUrl,
          fileName: 'Solutions.md',
        ),
        null,
      );
      expect(source.rawContent, isNull);
      expect(source.fileUrl, _mdUrl);
    });

    test('the other language pairs only when its text is a note', () {
      final english = _material(title: 'English', body: 'Answer one.');
      final bangla = _material(title: 'বাংলা', body: 'উত্তর এক।');
      final banglaFile = _material(
        title: 'বাংলা',
        kind: StudyMaterialKind.file,
        url: _mdUrl,
        fileName: 'bangla.md',
      );

      expect(solutionSource(english, bangla).paired, same(bangla));
      expect(solutionSource(english, banglaFile).paired, isNull);
    });
  });

  group('the language of a solution', () {
    test('a Bengali word in the title, or Bangla in the file name, is Bangla',
        () {
      expect(isBanglaSolution(_material(title: '৯৮তম বিপিই - মাস্টার সমাধান')),
          isTrue);
      expect(
        isBanglaSolution(_material(
          title: 'Solutions',
          fileName: 'Solutions_Bangla.md',
        )),
        isTrue,
      );
    });

    test('an English title is English', () {
      expect(isBanglaSolution(_material(title: 'Master Solutions (English)')),
          isFalse);
    });
  });
}
