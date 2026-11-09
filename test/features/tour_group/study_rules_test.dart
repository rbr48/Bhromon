import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// The study or book club's book list and reading plan (E2EE is not involved). The rules
// here mirror the ones in firestore.rules, so a change to one needs the other.

ReadingSession _session(String id, DateTime startsAt) => ReadingSession(
      id: id,
      title: 'Session $id',
      startsAt: startsAt,
    );

StudyBook _book(String id, String title, StudyBookStatus status) => StudyBook(
      id: id,
      title: title,
      status: status,
    );

void main() {
  group('titles', () {
    test('a title needs text once trimmed', () {
      expect(isValidStudyTitle(''), isFalse);
      expect(isValidStudyTitle('   '), isFalse);
      expect(isValidStudyTitle('  Chapters 1 to 3 '), isTrue);
    });

    test('a title can be as long as the limit, and no longer', () {
      expect(isValidStudyTitle('a' * kStudyTitleMax), isTrue);
      expect(isValidStudyTitle('a' * (kStudyTitleMax + 1)), isFalse);
    });
  });

  group('who may change an item', () {
    test('its creator may', () {
      expect(
        canEditStudyItem(
            createdByEmail: 'a@x.com', currentEmail: 'a@x.com', isAdmin: false),
        isTrue,
      );
    });

    test('an admin may, even for someone else\'s item', () {
      expect(
        canEditStudyItem(
            createdByEmail: 'a@x.com', currentEmail: 'b@x.com', isAdmin: true),
        isTrue,
      );
    });

    test('another member may not', () {
      expect(
        canEditStudyItem(
            createdByEmail: 'a@x.com', currentEmail: 'b@x.com', isAdmin: false),
        isFalse,
      );
    });

    test('an item with no creator can only be changed by an admin', () {
      expect(
        canEditStudyItem(createdByEmail: '', currentEmail: '', isAdmin: false),
        isFalse,
      );
      expect(
        canEditStudyItem(createdByEmail: '', currentEmail: '', isAdmin: true),
        isTrue,
      );
    });
  });

  group('the reading plan', () {
    final now = DateTime(2026, 11, 8, 18);

    test('upcoming sessions come soonest first, and past ones latest first',
        () {
      final split = splitSessions([
        _session('late', DateTime(2026, 11, 20, 18)),
        _session('past-old', DateTime(2026, 10, 1, 18)),
        _session('soon', DateTime(2026, 11, 9, 18)),
        _session('past-new', DateTime(2026, 11, 7, 18)),
      ], now);

      expect(split.upcoming.map((s) => s.id), ['soon', 'late']);
      expect(split.past.map((s) => s.id), ['past-new', 'past-old']);
    });

    test('a session starting exactly now is still to come', () {
      final split = splitSessions([_session('now', now)], now);

      expect(split.upcoming.map((s) => s.id), ['now']);
      expect(split.past, isEmpty);
    });
  });

  group('the book list', () {
    test('books are grouped by status, in reading order, each sorted by title',
        () {
      final groups = groupStudyBooks([
        _book('1', 'Zorba', StudyBookStatus.finished),
        _book('2', 'anna karenina', StudyBookStatus.reading),
        _book('3', 'Beloved', StudyBookStatus.toRead),
        _book('4', 'Atonement', StudyBookStatus.reading),
      ]);

      expect(
        [
          for (final s in kStudyBookSectionOrder)
            groups[s]!.map((b) => b.id).toList()
        ],
        [
          ['2', '4'],
          ['3'],
          ['1'],
        ],
      );
    });

    test('a status with no books still has an empty section', () {
      final groups = groupStudyBooks(const []);

      expect(groups.keys, containsAll(StudyBookStatus.values));
      expect(groups[StudyBookStatus.finished], isEmpty);
    });

    test('proposals and declined books are kept out of the status sections',
        () {
      final books = [
        _book('1', 'Zorba', StudyBookStatus.toRead),
        const StudyBook(
          id: '2',
          title: 'Sapiens',
          approval: StudyBookApproval.proposed,
        ),
        const StudyBook(
          id: '3',
          title: 'Dune',
          approval: StudyBookApproval.declined,
          declineNote: 'Too long',
        ),
      ];

      expect(
        groupStudyBooks(books)[StudyBookStatus.toRead]!
            .map((b) => b.id)
            .toList(),
        ['1'],
      );
      expect(studyBookProposals(books).map((b) => b.id).toList(), ['2']);
      expect(studyBookDeclined(books).map((b) => b.id).toList(), ['3']);
    });

    test('proposals are sorted by title, ignoring case', () {
      final proposals = studyBookProposals(const [
        StudyBook(
          id: '1',
          title: 'beloved',
          approval: StudyBookApproval.proposed,
        ),
        StudyBook(
          id: '2',
          title: 'Atonement',
          approval: StudyBookApproval.proposed,
        ),
      ]);

      expect(proposals.map((b) => b.id).toList(), ['2', '1']);
    });

    test('a book stored with no approval is listed, as it was before approvals',
        () {
      final book =
          StudyBook.fromMap('4', {'title': 'Emma', 'status': 'reading'});

      expect(book!.approval, StudyBookApproval.listed);
      expect(groupStudyBooks([book])[StudyBookStatus.reading], [book]);
    });
  });

  group('reading stored records', () {
    test('a book with no title is dropped', () {
      expect(
        StudyBook.fromMap('x', {'title': '   ', 'status': 'reading'}),
        isNull,
      );
    });

    test('an unknown status reads as to read, and blank optional text as none',
        () {
      final book = StudyBook.fromMap('x', {
        'title': 'Emma',
        'status': 'paused',
        'author': '',
        'statusByEmail': '',
      });

      expect(book, isNotNull);
      expect(book!.status, StudyBookStatus.toRead);
      expect(book.author, '');
      expect(book.statusByEmail, isNull);
    });

    test('a session without a start is dropped', () {
      expect(
        ReadingSession.fromMap(
            'x', {'title': 'Chapter 1', 'startsAt': '2026-11-09'}),
        isNull,
      );
    });

    test('a session keeps its book and place when they are set', () {
      final session = ReadingSession.fromMap('x', {
        'title': 'Chapter 1',
        'startsAt': DateTime(2026, 11, 9, 18),
        'bookId': 'b1',
        'place': 'Library',
      });

      expect(session, isNotNull);
      expect(session!.bookId, 'b1');
      expect(session.place, 'Library');
    });
  });
}
