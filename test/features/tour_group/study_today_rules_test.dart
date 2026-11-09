import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_today_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_subject_rules.dart';
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

    // The Today card counts only the subjects the group studies, so a proposal and an archived
    // subject never put their exam on the card.
    test('a proposed, declined or archived subject has no countdown', () {
      final subjects = [
        StudySubject(
            id: 'p',
            title: 'Proposed',
            examDate: DateTime(2026, 11, 11),
            approval: StudyBookApproval.proposed),
        StudySubject(
            id: 'd',
            title: 'Declined',
            examDate: DateTime(2026, 11, 11),
            approval: StudyBookApproval.declined),
        StudySubject(
            id: 'a',
            title: 'Archived',
            examDate: DateTime(2026, 11, 11),
            archived: true),
        StudySubject(
            id: 'l', title: 'Listed', examDate: DateTime(2026, 11, 20)),
      ];
      expect(nearestExam(activeStudySubjects(subjects), today)?.id, 'l');
      expect(nearestExam(activeStudySubjects(subjects.take(3)), today), isNull);
    });
  });

  group('the order of the Today card', () {
    test('outside exam mode the deadline leads, and the challenge comes last',
        () {
      expect(todayCardLineOrder(examMode: false), [
        TodayCardLine.exam,
        TodayCardLine.deadline,
        TodayCardLine.problemSet,
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
        TodayCardLine.problemSet,
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

  group('the problem set on the Today card', () {
    final now = DateTime(2026, 11, 10, 9);
    final dueSoon = DateTime(2026, 11, 12);
    final earlier = DateTime(2026, 11, 11);

    StudyProblem problem(String id, String setId,
            {bool shown = true, String by = 'b@x.com'}) =>
        StudyProblem(
          id: id,
          text: 'Solve $id',
          setId: setId,
          shown: shown,
          createdByEmail: by,
        );

    StudyProblemSet set(String id, String title, DateTime? due) =>
        StudyProblemSet(id: id, title: title, dueAt: due);

    DueProblemSet? pick({
      required List<StudyProblemSet> sets,
      required List<StudyProblem> problems,
      Set<String> worked = const {},
      bool admin = false,
    }) =>
        nextDueProblemSet(
          sets: sets,
          problems: problems,
          workedIds: worked,
          viewerEmail: 'me@x.com',
          isAdmin: admin,
          now: now,
        );

    test('the set due sooner comes first', () {
      final line = pick(
        sets: [set('s1', 'Week 3', dueSoon), set('s2', 'Week 2', earlier)],
        problems: [problem('p1', 's1'), problem('p2', 's2')],
      );
      expect(line?.set.id, 's2');
      expect(line?.total, 1);
      expect(line?.worked, 0);
    });

    test('a set the viewer has fully worked is skipped for the next one', () {
      final line = pick(
        sets: [set('s1', 'Week 2', earlier), set('s2', 'Week 3', dueSoon)],
        problems: [problem('p1', 's1'), problem('p2', 's2')],
        worked: {'p1'},
      );
      expect(line?.set.id, 's2');
    });

    test(
        'the counts are over the problems the viewer can see, and an admin sees more',
        () {
      final sets = [set('s1', 'Week 3', dueSoon)];
      final problems = [
        problem('p1', 's1'),
        problem('p2', 's1', shown: false),
        problem('p3', 's1'),
      ];
      final member = pick(sets: sets, problems: problems, worked: {'p3'});
      expect(member?.total, 2);
      expect(member?.worked, 1);
      final admin =
          pick(sets: sets, problems: problems, worked: {'p3'}, admin: true);
      expect(admin?.total, 3);
      expect(admin?.worked, 1);
    });

    test(
        'nothing is shown for a set not due soon, undated, empty, or fully worked',
        () {
      final line = pick(
        sets: [
          set('later', 'Later', DateTime(2026, 11, 20)),
          set('past', 'Past', DateTime(2026, 11, 9)),
          set('undated', 'Undated', null),
          set('empty', 'Empty', dueSoon),
          set('done', 'Done', dueSoon),
        ],
        problems: [
          problem('p1', 'later'),
          problem('p2', 'past'),
          problem('p3', 'undated'),
          problem('p4', 'done'),
        ],
        worked: {'p4'},
      );
      expect(line, isNull);
    });

    test(
        'a viewer\'s own due date replaces the set\'s, for whether it is due soon and for the date shown',
        () {
      // The set is due in ten days for everyone, but the viewer's own date for it is in two.
      final line = nextDueProblemSet(
        sets: [set('s1', 'Week 3', DateTime(2026, 11, 20))],
        problems: [problem('p1', 's1')],
        workedIds: const {},
        viewerEmail: 'me@x.com',
        isAdmin: false,
        now: now,
        ownDueBySetId: {'s1': dueSoon},
      );
      expect(line?.set.id, 's1');
      expect(line?.due, dueSoon);
    });

    test(
        'a later own date takes a set out of the window, even when the set is due soon for everyone else',
        () {
      final line = nextDueProblemSet(
        sets: [set('s1', 'Week 3', dueSoon)],
        problems: [problem('p1', 's1')],
        workedIds: const {},
        viewerEmail: 'me@x.com',
        isAdmin: false,
        now: now,
        ownDueBySetId: {'s1': DateTime(2026, 11, 25)},
      );
      expect(line, isNull);
    });

    test(
        'the order follows the viewer\'s own dates, so a set due sooner for everyone can come after one due sooner for the viewer',
        () {
      // Week 1 is due on 11 Nov for everyone, but the viewer's own date for it is 13 Nov; Week 2 is due on 12 Nov.
      final line = nextDueProblemSet(
        sets: [set('s1', 'Week 1', earlier), set('s2', 'Week 2', dueSoon)],
        problems: [problem('p1', 's1'), problem('p2', 's2')],
        workedIds: const {},
        viewerEmail: 'me@x.com',
        isAdmin: false,
        now: now,
        ownDueBySetId: {'s1': DateTime(2026, 11, 13)},
      );
      expect(line?.set.id, 's2');
    });
  });
}
