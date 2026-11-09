import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_today_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_today_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The Today card of a subject, and of a study group's home: what needs the member today.

StudyDeadline _deadline(String chapter, DateTime due) => StudyDeadline(
      chapterId: 'c-$chapter',
      bookTitle: 'Book',
      chapterTitle: chapter,
      dueOn: due,
    );

void main() {
  group('exam mode', () {
    test('it starts fourteen days before the exam, with the exam day included',
        () {
      expect(examModeOn(14), isTrue);
      expect(examModeOn(1), isTrue);
      expect(examModeOn(0), isTrue);
    });

    test('it is off further out, for an exam that has passed, and with no exam',
        () {
      expect(examModeOn(15), isFalse);
      expect(examModeOn(-1), isFalse);
      expect(examModeOn(null), isFalse);
    });
  });

  group('findings waiting for the member\'s check', () {
    test('a shown finding, not the member\'s own, without their check', () {
      final findings = [
        const StudyFinding(
          id: 'f1',
          text: 'a',
          method: 'm',
          createdByEmail: 'b@x.com',
        ),
        const StudyFinding(
          id: 'f2',
          text: 'b',
          method: 'm',
          createdByEmail: 'c@x.com',
        ),
        const StudyFinding(
          id: 'f3',
          text: 'mine',
          method: 'm',
          createdByEmail: 'me@x.com',
        ),
        const StudyFinding(
          id: 'f4',
          text: 'waiting for an admin',
          method: 'm',
          createdByEmail: 'b@x.com',
          shown: false,
        ),
        const StudyFinding(
          id: 'f5',
          text: 'd',
          method: 'm',
          createdByEmail: 'd@x.com',
        ),
      ];
      expect(
        findingsWaitingForCheck(
          findings: findings,
          viewerEmail: 'me@x.com',
          checkedIds: const {'f2'},
        ),
        2,
      );
    });

    test('nothing waits when the member has checked everything', () {
      expect(
        findingsWaitingForCheck(
          findings: const [
            StudyFinding(
                id: 'f1', text: 'a', method: 'm', createdByEmail: 'b@x.com'),
          ],
          viewerEmail: 'me@x.com',
          checkedIds: const {'f1'},
        ),
        0,
      );
    });
  });

  group('the next deadline', () {
    final today = DateTime(2026, 11, 10, 15);

    test('nothing is next when no chapter is due', () {
      expect(nextStudyDeadline(const [], today), isNull);
    });

    test('a chapter due before today is overdue, and is not the next', () {
      final overdue = _deadline('Old', DateTime(2026, 11, 8));
      expect(nextStudyDeadline([overdue], today), isNull);
    });

    test('the earliest due day from today on is the next', () {
      final next = nextStudyDeadline([
        _deadline('Late', DateTime(2026, 11, 20)),
        _deadline('Soon', DateTime(2026, 11, 12)),
        _deadline('Overdue', DateTime(2026, 11, 8)),
      ], today);
      expect(next?.chapterTitle, 'Soon');
    });

    test(
        'between chapters due the same day, the one whose title comes first is next',
        () {
      final next = nextStudyDeadline([
        _deadline('Dee', DateTime(2026, 11, 12, 18)),
        _deadline('Bee', DateTime(2026, 11, 12, 9)),
      ], today);
      expect(next?.chapterTitle, 'Bee');
    });

    test('a chapter due today is still the next', () {
      final next = nextStudyDeadline(
          [_deadline('Today', DateTime(2026, 11, 10))], today);
      expect(next?.chapterTitle, 'Today');
    });
  });

  group('the nearest exam across subjects', () {
    final today = DateTime(2026, 11, 10);

    test('the subject with the nearest exam to come is chosen', () {
      final nearest = nearestExam([
        StudySubject(id: 's1', title: 'Far', examDate: DateTime(2026, 11, 20)),
        StudySubject(id: 's2', title: 'Near', examDate: DateTime(2026, 11, 12)),
        StudySubject(id: 's3', title: 'Past', examDate: DateTime(2026, 11, 1)),
        const StudySubject(id: 's4', title: 'No exam'),
      ], today);
      expect(nearest?.id, 's2');
    });

    test('no subject is chosen when no exam is still to come', () {
      expect(
        nearestExam([
          StudySubject(
              id: 's1', title: 'Past', examDate: DateTime(2026, 11, 1)),
          const StudySubject(id: 's2', title: 'No exam'),
        ], today),
        isNull,
      );
    });

    test('an exam today is still to come', () {
      final nearest = nearestExam([
        StudySubject(
            id: 's1', title: 'Today', examDate: DateTime(2026, 11, 10)),
      ], today);
      expect(nearest?.id, 's1');
    });
  });

  group('the order of the Today card', () {
    test('outside exam mode the deadline leads, and the challenge comes last',
        () {
      expect(todayCardLineOrder(examMode: false), [
        TodayCardLine.exam,
        TodayCardLine.deadline,
        TodayCardLine.findings,
        TodayCardLine.cards,
        TodayCardLine.challenge,
      ]);
    });

    test(
        'in exam mode the cards due and the deadline come before the findings and the challenge',
        () {
      expect(todayCardLineOrder(examMode: true), [
        TodayCardLine.exam,
        TodayCardLine.cards,
        TodayCardLine.deadline,
        TodayCardLine.findings,
        TodayCardLine.challenge,
      ]);
    });

    test('each mode lists every line exactly once', () {
      for (final examMode in [true, false]) {
        final order = todayCardLineOrder(examMode: examMode);
        expect(order.toSet(), TodayCardLine.values.toSet());
        expect(order.length, TodayCardLine.values.length);
      }
    });
  });
}
