import 'package:bhromon/features/tour_group/domain/models/study_glossary_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_session_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_summary_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_pack_rules.dart';
import 'package:bhromon/features/tour_group/domain/services/study_progress_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The progress of a study group: a member's streak in weeks, the group's totals as counts, the revision of a chapter
// summary the group reads, and the study pack built from what the group shares. The rules are pure: no database.

void main() {
  // 2026-11-09 is a Monday, so the weeks below start on Mondays: Oct 19, Oct 26, Nov 2 and Nov 9.
  final today = DateTime(2026, 11, 11);

  group('weeks and streaks', () {
    test('a week starts on its Monday, at local midnight', () {
      expect(studyWeekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
      expect(studyWeekStart(DateTime(2026, 11, 11, 15, 30)),
          DateTime(2026, 11, 9));
      expect(studyWeekStart(DateTime(2026, 11, 15, 23)), DateTime(2026, 11, 9));
    });

    test('a run of weeks that reaches this week counts all of them', () {
      final streak = studyStreak([
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 28),
        DateTime(2026, 11, 4),
        DateTime(2026, 11, 10),
      ], today: today);
      expect(streak.current, 4);
      expect(streak.best, 4);
    });

    test('a skipped week breaks the run', () {
      final streak = studyStreak([
        DateTime(2026, 10, 21),
        DateTime(2026, 11, 4),
        DateTime(2026, 11, 10),
      ], today: today);
      expect(streak.current, 2);
      expect(streak.best, 2);
    });

    test('a run that stopped last week still counts until this week is over',
        () {
      final streak = studyStreak([
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 28),
        DateTime(2026, 11, 4),
      ], today: today);
      expect(streak.current, 3);
      expect(streak.best, 3);
    });

    test('a run that stopped two weeks ago has ended, and its best stays', () {
      final streak = studyStreak([DateTime(2026, 10, 28)], today: today);
      expect(streak.current, 0);
      expect(streak.best, 1);
    });

    test(
        'a missed week ends the run quietly, and the best run stays on the record',
        () {
      final streak = studyStreak([
        DateTime(2026, 10, 6),
        DateTime(2026, 10, 13),
        DateTime(2026, 10, 20),
        DateTime(2026, 11, 10),
      ], today: today);
      expect(streak.current, 1);
      expect(streak.best, 3);
    });

    test('no study at all is no streak', () {
      final streak = studyStreak(const [], today: today);
      expect(streak.current, 0);
      expect(streak.best, 0);
    });
  });

  group('the revision the group reads', () {
    final older = StudySummaryRevision(
      id: 'r1',
      text: 'Old',
      editorEmail: 'a@x.com',
      createdAt: DateTime(2026, 2, 1),
    );
    final newer = StudySummaryRevision(
      id: 'r2',
      text: 'New',
      editorEmail: 'b@x.com',
      createdAt: DateTime(2026, 3, 1),
    );

    test('the newest revision is shown until an admin pins one', () {
      final shown = summaryShownToGroup([older, newer]);
      expect(shown.revision?.id, 'r2');
      expect(shown.pinned, isFalse);
    });

    test('a pinned revision is shown even when a newer one exists', () {
      final shown = summaryShownToGroup([older, newer], pinnedId: 'r1');
      expect(shown.revision?.id, 'r1');
      expect(shown.pinned, isTrue);
    });

    test('when the pinned revision is gone, the newest is shown', () {
      final shown = summaryShownToGroup([older, newer], pinnedId: 'deleted');
      expect(shown.revision?.id, 'r2');
      expect(shown.pinned, isFalse);
    });

    test('a chapter with no revisions shows nothing', () {
      final shown = summaryShownToGroup(const []);
      expect(shown.revision, isNull);
    });

    test('revisions are listed newest first, and one with no time sorts last',
        () {
      const undated = StudySummaryRevision(
          id: 'r3', text: 'Undated', editorEmail: 'c@x.com');
      final ids =
          newestFirst([older, undated, newer]).map((r) => r.id).toList();
      expect(ids, ['r2', 'r1', 'r3']);
    });
  });

  group('questions answered within three days', () {
    final asked = DateTime(2026, 11, 1, 9);

    test('an answer counts when it comes within three days, and not after', () {
      final count = questionsAnsweredWithin([
        (asked: asked, firstAnswer: asked.add(const Duration(days: 2))),
        (asked: asked, firstAnswer: asked.add(const Duration(days: 3))),
        (
          asked: asked,
          firstAnswer: asked.add(const Duration(days: 3, minutes: 1))
        ),
        (asked: asked, firstAnswer: null),
        (asked: asked, firstAnswer: asked.subtract(const Duration(hours: 1))),
      ]);
      expect(count, 2);
    });
  });

  group('group totals are counts', () {
    test(
        'three accounts: only counted reads add to a chapter, and takers are kept as they are',
        () {
      final asked = DateTime(2026, 11, 1, 9);
      final totals = groupTotals(
        countedReadFlags: {
          // Account A counted chapter one, account B did not, and account C counted it.
          'c1': [true, false, true],
          'c2': [false],
        },
        takersByQuiz: {'q1': 3},
        questions: [
          (asked: asked, firstAnswer: asked.add(const Duration(days: 1))),
          (asked: asked, firstAnswer: null),
        ],
      );
      expect(totals.chaptersCounted, {'c1': 2, 'c2': 0});
      expect(totals.quizTakers, {'q1': 3});
      expect(totals.questionsAnswered, 1);
      expect(totals.questionsAsked, 2);
    });
  });

  group('the study pack', () {
    const book = StudyBook(id: 'b1', title: 'Anna Karenina');

    test(
        'holds only the pinned summaries, the accepted answers, the approved terms, the recaps and the published materials',
        () {
      final pack = buildStudyPack(
        book: book,
        chapters: [
          const StudyChapter(
              id: 'c1', number: 1, title: 'Part one', pinnedSummaryId: 'r1'),
          const StudyChapter(id: 'c2', number: 2, title: 'Part two'),
          const StudyChapter(
              id: 'c3',
              number: 3,
              title: 'Part three',
              pinnedSummaryId: 'gone'),
        ],
        revisionsByChapter: {
          'c1': [
            StudySummaryRevision(
              id: 'r1',
              text: 'Pinned summary.',
              editorEmail: 'a@x.com',
              createdAt: DateTime(2026, 2, 1),
            ),
            StudySummaryRevision(
              id: 'r2',
              text: 'Newer, not pinned.',
              editorEmail: 'b@x.com',
              createdAt: DateTime(2026, 3, 1),
            ),
          ],
          'c2': [
            StudySummaryRevision(
              id: 'r3',
              text: 'Unpinned.',
              editorEmail: 'a@x.com',
              createdAt: DateTime(2026, 2, 2),
            ),
          ],
          'c3': [
            StudySummaryRevision(
              id: 'r4',
              text: 'Pin is gone.',
              editorEmail: 'a@x.com',
              createdAt: DateTime(2026, 2, 3),
            ),
          ],
        },
        acceptedAnswers: [
          (question: 'Why does Anna travel?', answer: 'To see her brother.')
        ],
        glossary: [
          const StudyGlossaryTerm(
              id: 't1',
              term: 'Vronsky',
              definition: 'The officer.',
              approved: true),
          const StudyGlossaryTerm(
              id: 't2', term: 'Levin', definition: 'Proposed only.'),
        ],
        sessions: [
          ReadingSession(
            id: 's1',
            title: 'Week one',
            startsAt: DateTime(2026, 10, 1),
            bookId: 'b1',
            recap: const StudySessionRecap(
                covered: 'Part one',
                hard: 'The station',
                openQuestions: ['Why?']),
          ),
          ReadingSession(
            id: 's2',
            title: 'Other book',
            startsAt: DateTime(2026, 10, 2),
            bookId: 'b2',
            recap: const StudySessionRecap(covered: 'Elsewhere'),
          ),
          ReadingSession(
            id: 's3',
            title: 'Empty recap',
            startsAt: DateTime(2026, 10, 3),
            bookId: 'b1',
            recap: const StudySessionRecap(),
          ),
        ],
        materials: [
          const StudyMaterial(
            id: 'm1',
            title: 'Reading notes',
            kind: StudyMaterialKind.link,
            bookId: 'b1',
            url: 'https://example.com/notes',
            status: StudyMaterialStatus.published,
          ),
          const StudyMaterial(
            id: 'm2',
            title: 'Scan of notes',
            kind: StudyMaterialKind.image,
            bookId: 'b1',
            url: 'https://bhromon.fun/media/study/scan.jpg',
            status: StudyMaterialStatus.published,
          ),
          const StudyMaterial(
            id: 'm3',
            title: 'Pending upload',
            kind: StudyMaterialKind.file,
            bookId: 'b1',
            status: StudyMaterialStatus.pending,
          ),
          const StudyMaterial(
            id: 'm4',
            title: 'Another book',
            kind: StudyMaterialKind.link,
            bookId: 'b2',
            url: 'https://example.com/other',
            status: StudyMaterialStatus.published,
          ),
        ],
      );

      expect(pack.bookTitle, 'Anna Karenina');
      expect(pack.chapters.map((c) => c.summary), ['Pinned summary.']);
      expect(pack.answers.single.answer, 'To see her brother.');
      expect(pack.terms.map((t) => t.term), ['Vronsky']);
      expect(pack.recaps.map((r) => r.title), ['Week one']);
      expect(pack.recaps.single.openQuestions, ['Why?']);
      expect(pack.materials.map((m) => m.title),
          ['Reading notes', 'Scan of notes']);
      expect(pack.materials[0].url, 'https://example.com/notes');
      expect(pack.materials[1].url, isNull,
          reason: 'a file has a title and no link in the pack');
      expect(pack.isEmpty, isFalse);
    });

    test('a book with nothing shared yet makes an empty pack', () {
      final pack = buildStudyPack(
        book: book,
        chapters: const [],
        revisionsByChapter: const {},
        acceptedAnswers: const [],
        glossary: const [],
        sessions: const [],
        materials: const [],
      );
      expect(pack.isEmpty, isTrue);
    });
  });
}
