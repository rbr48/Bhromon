import 'package:bhromon/features/tour_group/data/tour_export_pdf.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_record_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanRecordText', () {
    test('drops emoji and collapses spaces', () {
      expect(cleanRecordText('  Hello 😀   world  '), 'Hello world');
    });

    test('keeps the zero-width joiner that Bengali conjuncts use', () {
      // ক + virama + ZWJ + ষ: a conjunct the joiner shapes.
      const conjunct = 'ক্‍ষ';

      expect(cleanRecordText(conjunct), conjunct);
    });

    test('cuts a long text with an ellipsis and the note', () {
      expect(
        cleanRecordText('abcdefghij', max: 4, cutNote: '(more)'),
        'abcd… (more)',
      );
    });

    test('cuts a long text with a bare ellipsis when there is no note', () {
      expect(cleanRecordText('abcdefghij', max: 4), 'abcd…');
    });

    test('never splits a surrogate pair when it cuts', () {
      // U+1D400 is a surrogate pair outside the emoji ranges; a cut between its halves
      // would leave a broken character.
      final text = '${'a' * 9}\u{1D400}';

      expect(cleanRecordText(text, max: 10), '${'a' * 9}…');
    });

    test('a null or empty text reads as empty', () {
      expect(cleanRecordText(null), '');
      expect(cleanRecordText('   '), '');
    });
  });

  test('every section has a heading key', () {
    for (final section in TourRecordSection.values) {
      expect(recordSectionKey(section), startsWith('pdf_section_'));
    }
  });
}
