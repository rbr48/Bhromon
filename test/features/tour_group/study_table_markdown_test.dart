import 'package:bhromon/features/tour_group/domain/services/study_table_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

// Tables in study text: how a grid is written as markdown, read back, found at a cursor, and inserted on
// lines of its own. The chat reads the same syntax, so these rules are the ones the renderer relies on.

void main() {
  group('writing a table', () {
    test('a grid is a header, a separator and one line per row', () {
      final md = studyTableMarkdown([
        ['Date', 'Amount'],
        ['1 Jan', '40,000'],
        ['2 Jan', ''],
      ]);
      expect(md,
          '| Date | Amount |\n| --- | --- |\n| 1 Jan | 40,000 |\n| 2 Jan |  |');
    });

    test('a pipe in a cell is escaped, and a line break becomes a space', () {
      final md = studyTableMarkdown([
        ['Item', 'Note'],
        ['tea | snacks', 'first\nsecond'],
      ]);
      expect(md, contains(r'| tea \| snacks | first second |'));
    });

    test('a new table is two columns with a header and one body row', () {
      expect(newStudyTable(), [
        ['', ''],
        ['', ''],
      ]);
    });
  });

  group('reading a table back', () {
    test('what was written reads back as the same grid', () {
      final grid = [
        ['Date', 'Note'],
        ['1 Jan', 'tea | snacks'],
        ['2 Jan', ''],
      ];
      final lines = studyTableMarkdown(grid).split('\n');
      expect(parseStudyTableLines(lines), [
        ['Date', 'Note'],
        ['1 Jan', 'tea | snacks'],
        ['2 Jan', ''],
      ]);
    });

    test('a table without a separator line is not a table', () {
      expect(parseStudyTableLines(['| a | b |', '| c | d |']), isNull);
    });

    test('a line that does not start and end with a pipe is not a table', () {
      expect(
        parseStudyTableLines(['| a | b |', '| --- | --- |', 'c | d']),
        isNull,
      );
    });

    test('a short row is padded and a long row is cut to the header width', () {
      expect(
        parseStudyTableLines([
          '| a | b |',
          '| --- | --- |',
          '| 1 |',
          '| 2 | 3 | 4 |',
        ]),
        [
          ['a', 'b'],
          ['1', ''],
          ['2', '3'],
        ],
      );
    });
  });

  group('finding the table at a cursor', () {
    const text = 'Intro line\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\nAfter';

    test('an offset inside the table gives its block and grid', () {
      final offset = text.indexOf('1 | 2');
      final block = studyTableAt(text, offset);
      expect(block, isNotNull);
      expect(text.substring(block!.start, block.end),
          '| a | b |\n| --- | --- |\n| 1 | 2 |');
      expect(block.rows, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('an offset outside any table gives nothing', () {
      expect(studyTableAt(text, 2), isNull);
      expect(studyTableAt(text, text.indexOf('After')), isNull);
    });

    test('with two tables, the one under the offset is chosen', () {
      const two = '| a |\n| --- |\n| 1 |\n\n| x |\n| --- |\n| 9 |';
      final block = studyTableAt(two, two.indexOf('9'));
      expect(block!.rows, [
        ['x'],
        ['9'],
      ]);
    });

    test('a single line that starts with a pipe is not a table', () {
      expect(studyTableAt('| just a line |', 3), isNull);
    });
  });

  group('putting a table into text', () {
    test('an insert in the middle of a line goes on lines of its own', () {
      final edit = replaceStudyRange('Before After', 7, 7, '| a |');
      expect(edit.text, 'Before \n| a |\nAfter');
      expect(edit.cursor, 'Before \n| a |'.length);
    });

    test('no extra line break is added where one is already there', () {
      final edit = replaceStudyRange('Line\n', 5, 5, '| a |');
      expect(edit.text, 'Line\n| a |');
    });

    test('a replace swaps the old table for the new one', () {
      const old = 'Head\n| a |\n| --- |\n| 1 |\nTail';
      final block = studyTableAt(old, old.indexOf('1'))!;
      final edit =
          replaceStudyRange(old, block.start, block.end, '| b |\n| --- |');
      expect(edit.text, 'Head\n| b |\n| --- |\nTail');
    });
  });
}
