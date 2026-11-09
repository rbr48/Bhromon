import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_problem_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// Problem solving: a problem with a reference solution that opens on its release day, and the members'
// own working, which they review each other's of, but only after submitting their own. The rules are pure:
// no database.

StudyProblem _problem(
  String id, {
  DateTime? releaseAt,
  bool shown = true,
  bool pinned = false,
  String by = 'a@x.com',
  DateTime? at,
}) =>
    StudyProblem(
      id: id,
      text: 'Problem $id',
      createdByEmail: by,
      createdAt: at,
      releaseAt: releaseAt,
      shown: shown,
      pinned: pinned,
    );

StudyProblemSolution _work(String email, {int right = 0, int gap = 0}) =>
    StudyProblemSolution(
      solverEmail: email,
      text: 'Working of $email',
      rightCount: right,
      gapCount: gap,
    );

void main() {
  group('when the reference solution opens', () {
    test('it has no release day until one is set, and opens on that day', () {
      final day = DateTime(2026, 11, 10);
      expect(referenceOpen(releaseAt: null, now: day), isFalse);
      expect(referenceOpen(releaseAt: day, now: DateTime(2026, 11, 9, 23)),
          isFalse);
      expect(referenceOpen(releaseAt: day, now: day), isTrue);
      expect(
          referenceOpen(releaseAt: day, now: DateTime(2026, 11, 11)), isTrue);
    });

    test(
        'the status says whether a release day is set, and whether it has come',
        () {
      final day = DateTime(2026, 11, 10);
      expect(
        referenceStatus(problem: _problem('p'), now: day),
        ReferenceStatus.noRelease,
      );
      expect(
        referenceStatus(
          problem: _problem('p', releaseAt: day),
          now: DateTime(2026, 11, 9),
        ),
        ReferenceStatus.scheduled,
      );
      expect(
        referenceStatus(problem: _problem('p', releaseAt: day), now: day),
        ReferenceStatus.open,
      );
    });
  });

  group('who may read the reference solution', () {
    test(
        'an admin always may; a member only once the problem is shown and the day has come',
        () {
      final day = DateTime(2026, 11, 10);
      final now = DateTime(2026, 11, 11);
      expect(
        canSeeReference(
            problem: _problem('p'), isAdmin: true, now: DateTime(2026)),
        isTrue,
      );
      expect(
        canSeeReference(
            problem: _problem('p', releaseAt: day), isAdmin: false, now: now),
        isTrue,
      );
      expect(
        canSeeReference(
          problem: _problem('p', releaseAt: day),
          isAdmin: false,
          now: DateTime(2026, 11, 9),
        ),
        isFalse,
      );
      expect(
        canSeeReference(
          problem: _problem('p', releaseAt: day, shown: false),
          isAdmin: false,
          now: now,
        ),
        isFalse,
      );
      expect(
        canSeeReference(problem: _problem('p'), isAdmin: false, now: now),
        isFalse,
      );
    });
  });

  group('who may review a working', () {
    test('a member reviews a peer after submitting their own, and once', () {
      expect(
        canReviewWork(
          solverEmail: 'b@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: true,
          viewerHasReview: false,
        ),
        isTrue,
      );
      expect(
        canReviewWork(
          solverEmail: 'b@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: false,
          viewerHasReview: false,
        ),
        isFalse,
      );
      expect(
        canReviewWork(
          solverEmail: 'b@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: true,
          viewerHasReview: true,
        ),
        isFalse,
      );
    });

    test('nobody reviews their own working', () {
      expect(
        canReviewWork(
          solverEmail: 'a@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: true,
          viewerHasReview: false,
        ),
        isFalse,
      );
      expect(
        canReviewWork(
          solverEmail: 'a@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: false,
          viewerHasReview: false,
          viewerIsAdmin: true,
        ),
        isFalse,
      );
    });

    test(
        'an admin reviews a peer\'s working without a working of their own, and once',
        () {
      expect(
        canReviewWork(
          solverEmail: 'b@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: false,
          viewerHasReview: false,
          viewerIsAdmin: true,
        ),
        isTrue,
      );
      expect(
        canReviewWork(
          solverEmail: 'b@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: false,
          viewerHasReview: true,
          viewerIsAdmin: true,
        ),
        isFalse,
      );
    });
  });

  group('the standing of a working', () {
    test('unreviewed, right so far, gaps found, or mixed, by the counts', () {
      expect(workStanding(_work('b@x.com')), WorkStanding.unreviewed);
      expect(workStanding(_work('b@x.com', right: 2, gap: 1)),
          WorkStanding.rightSoFar);
      expect(workStanding(_work('b@x.com', right: 1, gap: 2)),
          WorkStanding.gapsFound);
      expect(
          workStanding(_work('b@x.com', right: 1, gap: 1)), WorkStanding.mixed);
    });
  });

  group('what a viewer sees and in what order', () {
    test(
        'a problem waiting for an admin is seen by its author and an admin only',
        () {
      final waiting = _problem('w', shown: false, by: 'a@x.com');
      List<StudyProblem> seen(String who, {bool admin = false}) =>
          visibleStudyProblems(
            problems: [waiting],
            viewerEmail: who,
            isAdmin: admin,
          );
      expect(seen('a@x.com'), hasLength(1));
      expect(seen('b@x.com'), isEmpty);
      expect(seen('b@x.com', admin: true), hasLength(1));
    });

    test(
        'pinned first, then the newest, and a problem with no time yet comes first',
        () {
      final old = DateTime(2026, 10, 1);
      final recent = DateTime(2026, 11, 1);
      final sorted = sortStudyProblems([
        _problem('old', at: old),
        _problem('pinned', pinned: true, at: old),
        _problem('new', at: recent),
        _problem('fresh'),
      ]);
      expect(sorted.map((p) => p.id), ['pinned', 'fresh', 'new', 'old']);
    });
  });

  group('stored records', () {
    test(
        'a problem needs a statement, a working needs text, and a review needs a known verdict',
        () {
      expect(StudyProblem.fromMap('p', {'text': '  '}), isNull);
      expect(StudyReferenceSolution.fromMap({'text': ''}), isNull);
      expect(StudyProblemSolution.fromMap('a@x.com', {'text': ' '}), isNull);
      expect(StudyWorkReview.fromMap('b@x.com', {'verdict': 'maybe'}), isNull);
      expect(
        StudyWorkReview.fromMap(
            'b@x.com', {'verdict': 'gap', 'note': ' Off by one '})?.note,
        'Off by one',
      );
    });

    test(
        'the counts of a working never read below zero, and a problem keeps its release day',
        () {
      final day = DateTime(2026, 11, 10);
      final work = StudyProblemSolution.fromMap(
        'a@x.com',
        {'text': 'Done', 'rightCount': -1, 'gapCount': 2},
      );
      expect(work?.rightCount, 0);
      expect(work?.gapCount, 2);
      expect(work?.reviewCount, 2);
      expect(
        StudyProblem.fromMap('p', {'text': 'Solve it', 'releaseAt': day})
            ?.releaseAt,
        day,
      );
    });
  });

  group('reporting a problem or a working', () {
    test(
        'a member reports a shown problem that someone else wrote, and not their own or a waiting one',
        () {
      final byAdmin = _problem('p', by: 'admin@x.com');
      expect(
          canReportProblem(problem: byAdmin, viewerEmail: 'a@x.com'), isTrue);
      expect(canReportProblem(problem: byAdmin, viewerEmail: 'admin@x.com'),
          isFalse);
      final waiting = _problem('p', shown: false, by: 'admin@x.com');
      expect(
          canReportProblem(problem: waiting, viewerEmail: 'a@x.com'), isFalse);
    });

    test(
        'a working is reported by a peer who has submitted their own, or by an admin, never by its author',
        () {
      expect(
        canReportWork(
            solverEmail: 'b@x.com',
            viewerEmail: 'a@x.com',
            viewerHasWork: true),
        isTrue,
      );
      expect(
        canReportWork(
            solverEmail: 'b@x.com',
            viewerEmail: 'a@x.com',
            viewerHasWork: false),
        isFalse,
      );
      expect(
        canReportWork(
          solverEmail: 'b@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: false,
          viewerIsAdmin: true,
        ),
        isTrue,
      );
      expect(
        canReportWork(
          solverEmail: 'a@x.com',
          viewerEmail: 'a@x.com',
          viewerHasWork: true,
          viewerIsAdmin: true,
        ),
        isFalse,
      );
    });

    test(
        'a reported working is hidden from members other than its author, and the admins still see it',
        () {
      final reported = StudyProblemSolution(
        solverEmail: 'b@x.com',
        text: 'Working',
        reportCount: 1,
        reportedAt: DateTime(2026, 11, 9),
      );
      expect(
          workVisibleTo(work: reported, viewerEmail: 'a@x.com', isAdmin: false),
          isFalse);
      expect(
          workVisibleTo(work: reported, viewerEmail: 'b@x.com', isAdmin: false),
          isTrue);
      expect(
          workVisibleTo(work: reported, viewerEmail: 'a@x.com', isAdmin: true),
          isTrue);
      expect(
          workVisibleTo(
              work: _work('b@x.com'), viewerEmail: 'a@x.com', isAdmin: false),
          isTrue);
    });

    test(
        'the reports read from the store: a count never reads below zero, and a report needs a time',
        () {
      final reported = StudyProblem.fromMap('p', {
        'text': 'Solve it',
        'reportCount': 2,
        'reportedAt': DateTime(2026, 11, 9),
        'shown': false,
      });
      expect(reported?.reportCount, 2);
      expect(reported?.isReported, isTrue);
      final clean =
          StudyProblem.fromMap('p', {'text': 'Solve it', 'reportCount': -3});
      expect(clean?.reportCount, 0);
      expect(clean?.isReported, isFalse);
      final work = StudyProblemSolution.fromMap('a@x.com', {
        'text': 'Done',
        'reportCount': 1,
        'reportedAt': 'not a time',
      });
      expect(work?.reportCount, 1);
      expect(work?.isReported, isFalse);
    });

    test(
        'an admin reviews the reported problems that are hidden, the oldest report first',
        () {
      final older = StudyProblem(
        id: 'old',
        text: 'Old',
        shown: false,
        reportCount: 1,
        reportedAt: DateTime(2026, 11, 2),
      );
      final newer = StudyProblem(
        id: 'new',
        text: 'New',
        shown: false,
        reportCount: 1,
        reportedAt: DateTime(2026, 11, 5),
      );
      final restored = StudyProblem(
        id: 'restored',
        text: 'Restored',
        reportCount: 1,
        reportedAt: DateTime(2026, 11, 1),
      );
      const plain = StudyProblem(id: 'plain', text: 'Plain', shown: false);
      expect(
        reportedProblemsForReview([newer, plain, older, restored])
            .map((p) => p.id),
        ['old', 'new'],
      );
    });
  });
}
