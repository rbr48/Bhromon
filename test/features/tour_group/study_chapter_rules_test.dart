import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_chapter_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The chapters of a study book: their due dates from a reading pace, their order, the next
// chapter to read, the guide questions, and the page ranges. The rules here mirror the ones in
// firestore.rules, so a change to one needs the other.

StudyChapter _chapter(String id, int number,
        {DateTime? due, String title = ''}) =>
    StudyChapter(
      id: id,
      number: number,
      title: title.isEmpty ? 'Part $number' : title,
      dueOn: due,
    );

void main() {
  group('due dates from a reading pace', () {
    test(
        'a chapter is due on the last day of its week, counting the start as day one',
        () {
      final dues = chapterDueDates(
        start: DateTime(2026, 11, 2, 15, 30),
        perWeek: 2,
        count: 5,
      );
      expect(dues, [
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 15),
        DateTime(2026, 11, 15),
        DateTime(2026, 11, 22),
      ]);
    });

    test('one chapter a week falls due a week apart', () {
      final dues = chapterDueDates(
        start: DateTime(2026, 1, 1),
        perWeek: 1,
        count: 3,
      );
      expect(dues, [
        DateTime(2026, 1, 7),
        DateTime(2026, 1, 14),
        DateTime(2026, 1, 21),
      ]);
    });

    test('a pace outside the limits is brought inside them', () {
      final tooFew =
          chapterDueDates(start: DateTime(2026, 1, 1), perWeek: 0, count: 2);
      expect(tooFew, [DateTime(2026, 1, 7), DateTime(2026, 1, 14)]);
      final tooMany =
          chapterDueDates(start: DateTime(2026, 1, 1), perWeek: 99, count: 15);
      expect(tooMany.first, DateTime(2026, 1, 7));
      expect(tooMany.last, DateTime(2026, 1, 7 + 7));
    });

    test('no chapters, no dates', () {
      expect(chapterDueDates(start: DateTime(2026, 1, 1), perWeek: 2, count: 0),
          isEmpty);
    });

    test('a due date crosses the end of a month', () {
      final dues =
          chapterDueDates(start: DateTime(2026, 1, 28), perWeek: 3, count: 4);
      expect(dues.first, DateTime(2026, 2, 3));
      expect(dues.last, DateTime(2026, 2, 10));
    });
  });

  group('order and the next chapter', () {
    test('chapters sort by number, then by title', () {
      final sorted = sortStudyChapters([
        _chapter('c', 2, title: 'Zeta'),
        _chapter('a', 1),
        _chapter('b', 2, title: 'Alpha'),
      ]);
      expect(sorted.map((c) => c.id), ['a', 'b', 'c']);
    });

    test('the next chapter is the first one not read', () {
      final chapters = sortStudyChapters(
          [_chapter('a', 1), _chapter('b', 2), _chapter('c', 3)]);
      expect(nextUnreadChapter(chapters, {'a'})?.id, 'b');
      expect(nextUnreadChapter(chapters, {'a', 'c'})?.id, 'b');
    });

    test('no next chapter once every chapter is read', () {
      final chapters = [_chapter('a', 1), _chapter('b', 2)];
      expect(nextUnreadChapter(chapters, {'a', 'b'}), isNull);
    });
  });

  group('overdue chapters', () {
    final today = DateTime(2026, 11, 9, 23, 59);

    test('a chapter due before today and not read is overdue', () {
      final late = _chapter('a', 1, due: DateTime(2026, 11, 8, 18));
      expect(isChapterOverdue(late, read: false, today: today), isTrue);
    });

    test('due today is not overdue, and counted on dates only', () {
      final due = _chapter('a', 1, due: DateTime(2026, 11, 9, 0, 1));
      expect(isChapterOverdue(due, read: false, today: today), isFalse);
    });

    test('a read chapter is never overdue, and a chapter with no date is not',
        () {
      final late = _chapter('a', 1, due: DateTime(2026, 11, 1));
      expect(isChapterOverdue(late, read: true, today: today), isFalse);
      expect(isChapterOverdue(_chapter('b', 2), read: false, today: today),
          isFalse);
    });
  });

  group('guide questions and pages', () {
    test('guide questions are trimmed, blanks dropped, and capped at the limit',
        () {
      expect(cleanGuideQuestions(['  Why?  ', '', '   ', 'How?']),
          ['Why?', 'How?']);
      expect(
        cleanGuideQuestions(['1', '2', '3', '4', '5', '6', '7']),
        ['1', '2', '3', '4', '5'],
      );
    });

    test(
        'a page range is blank, or both pages with the last not before the first',
        () {
      expect(validPageRange(null, null), isTrue);
      expect(validPageRange(1, 20), isTrue);
      expect(validPageRange(21, 21), isTrue);
      expect(validPageRange(20, 10), isFalse);
      expect(validPageRange(5, null), isFalse);
      expect(validPageRange(null, 9), isFalse);
      expect(validPageRange(0, 5), isFalse);
      expect(validPageRange(1, StudyChapter.pageMax + 1), isFalse);
    });

    test('a chapter number is 1 to 500', () {
      expect(validChapterNumber(1), isTrue);
      expect(validChapterNumber(StudyChapter.numberMax), isTrue);
      expect(validChapterNumber(0), isFalse);
      expect(validChapterNumber(StudyChapter.numberMax + 1), isFalse);
    });
  });

  group('reading the stored chapter', () {
    test('a chapter with no usable number or title is not read', () {
      expect(StudyChapter.fromMap('x', {'title': 'Part', 'number': 0}), isNull);
      expect(StudyChapter.fromMap('x', {'number': 2, 'title': '  '}), isNull);
      expect(StudyChapter.fromMap('x', {'title': 'Part'}), isNull);
    });

    test('guide questions past the limit are dropped, and damaged ones skipped',
        () {
      final read = StudyChapter.fromMap('x', {
        'number': 3,
        'title': 'Part three',
        'guide': ['One', '  ', 7, 'Two', 'Three', 'Four', 'Five', 'Six'],
      });
      expect(read?.guide, ['One', 'Two', 'Three', 'Four', 'Five']);
    });

    test('a chapter reads its pages and its due date', () {
      final due = DateTime(2026, 11, 15);
      final read = StudyChapter.fromMap('x', {
        'number': 1,
        'title': 'Part one',
        'pageFrom': 1,
        'pageTo': 20,
        'dueOn': due,
      });
      expect(read?.pageFrom, 1);
      expect(read?.pageTo, 20);
      expect(read?.dueOn, due);
    });

    test(
        'a chapter writes empty optional values as null, and guide questions as a list',
        () {
      final fields =
          const StudyChapter(id: '', number: 2, title: 'Two').toFields();
      expect(fields['pageFrom'], isNull);
      expect(fields['pageTo'], isNull);
      expect(fields['dueOn'], isNull);
      expect(fields['guide'], isEmpty);
    });
  });

  group('read marks and sessions', () {
    test(
        'a read mark that exists is a read, even before the server has its time',
        () {
      final mark = StudyReadMark.fromMap('c1', {'counted': true});
      expect(mark.chapterId, 'c1');
      expect(mark.readAt, isNull);
      expect(mark.counted, isTrue);
    });

    test('an uncounted mark is the default', () {
      expect(StudyReadMark.fromMap('c1', {}).counted, isFalse);
    });

    test(
        'a session reads the chapters it names, up to the limit, and skips damaged ones',
        () {
      final session = ReadingSession.fromMap('s1', {
        'title': 'Chapters 1 and 2',
        'startsAt': DateTime(2026, 11, 20, 18),
        'chapterIds': ['c1', '', 4, 'c2'],
      });
      expect(session?.chapterIds, ['c1', 'c2']);
    });

    test('a session writes its chapters, or null when it names none', () {
      final named = ReadingSession(
        id: '',
        title: 'Plan',
        startsAt: DateTime(2026, 11, 20),
        chapterIds: const ['c1'],
      ).toFields();
      expect(named['chapterIds'], ['c1']);
      final none = ReadingSession(
        id: '',
        title: 'Plan',
        startsAt: DateTime(2026, 11, 20),
      ).toFields();
      expect(none['chapterIds'], isNull);
    });

    test('an empty tally has no votes and no vote of the member', () {
      expect(StudyVoteTally.none.count, 0);
      expect(StudyVoteTally.none.mine, isFalse);
    });
  });
}
