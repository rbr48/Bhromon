import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_books_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_reading_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The study group's book list and reading plan, with a fake repository that records each
// change. The rules these screens follow are in firestore.rules and are tested on the
// emulator in functions/tests/study_rules.test.js.

class _FakeStudyRepo extends TourGroupRepository {
  _FakeStudyRepo({this.books = const [], this.sessions = const []});

  final List<StudyBook> books;
  final List<ReadingSession> sessions;
  final List<String> calls = [];

  /// The signed-in member. The books and sessions in these tests are by this person
  /// or by someone else, as their creator fields say.
  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => null;

  @override
  Stream<List<StudyBook>> watchStudyBooks(String tourId) => Stream.value(books);

  @override
  Stream<List<ReadingSession>> watchReadingSessions(String tourId) =>
      Stream.value(sessions);

  @override
  Future<void> addStudyBook(
    String tourId, {
    required String title,
    String author = '',
    String notes = '',
    StudyBookStatus status = StudyBookStatus.toRead,
  }) async {
    calls.add('add $title');
  }

  @override
  Future<void> setStudyBookStatus(
    String tourId,
    String bookId,
    StudyBookStatus status,
  ) async {
    calls.add('status $bookId ${status.name}');
  }

  @override
  Future<void> addReadingSession(
    String tourId, {
    required String title,
    required DateTime startsAt,
    String? bookId,
    String place = '',
    String notes = '',
  }) async {
    calls.add('plan $title');
  }
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: page,
  ));
  await tester.pumpAndSettle();
}

final _books = [
  const StudyBook(
    id: 'b1',
    title: 'Emma',
    author: 'Jane Austen',
    status: StudyBookStatus.reading,
    createdByEmail: 'me@x.com',
  ),
  const StudyBook(
    id: 'b2',
    title: 'Anna Karenina',
    status: StudyBookStatus.toRead,
    createdByEmail: 'other@x.com',
  ),
  const StudyBook(
    id: 'b3',
    title: 'Middlemarch',
    status: StudyBookStatus.finished,
    createdByEmail: 'other@x.com',
  ),
];

void main() {
  group('the book list', () {
    testWidgets('books are shown in their status sections', (tester) async {
      await _pump(
          tester,
          StudyBooksScreen(
            tourId: 't1',
            repository: _FakeStudyRepo(books: _books),
          ));

      expect(find.text('Emma'), findsOneWidget);
      expect(find.text('Anna Karenina'), findsOneWidget);
      expect(find.text('Middlemarch'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('To read'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
    });

    testWidgets('an empty list says how to start', (tester) async {
      await _pump(
          tester,
          StudyBooksScreen(
            tourId: 't1',
            repository: _FakeStudyRepo(),
          ));

      expect(find.text('No books yet. Add the first book the group will read.'),
          findsOneWidget);
    });

    testWidgets(
        'the creator of a book can edit and remove it, another member cannot',
        (tester) async {
      await _pump(
          tester,
          StudyBooksScreen(
            tourId: 't1',
            repository: _FakeStudyRepo(books: _books),
          ));

      // Sections come in reading order, so the first menu belongs to Emma, mine.
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(
          find.widgetWithText(PopupMenuItem<String>, 'Edit'), findsOneWidget);
      expect(
          find.widgetWithText(PopupMenuItem<String>, 'Remove'), findsOneWidget);
    });

    testWidgets('another member sees only the status options on a book',
        (tester) async {
      await _pump(
          tester,
          StudyBooksScreen(
            tourId: 't1',
            repository: _FakeStudyRepo(books: _books),
          ));

      // The second menu belongs to Anna Karenina, by someone else.
      await tester.tap(find.byType(PopupMenuButton<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PopupMenuItem<String>, 'Reading'),
          findsOneWidget);
      expect(find.widgetWithText(PopupMenuItem<String>, 'Edit'), findsNothing);
      expect(
          find.widgetWithText(PopupMenuItem<String>, 'Remove'), findsNothing);
    });

    testWidgets('any member moves a book to another status, under their name',
        (tester) async {
      final repo = _FakeStudyRepo(books: _books);
      await _pump(tester, StudyBooksScreen(tourId: 't1', repository: repo));

      await tester.tap(find.byType(PopupMenuButton<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Reading'));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('status b2 reading'));
    });

    testWidgets('adding a book needs a title', (tester) async {
      final repo = _FakeStudyRepo();
      await _pump(tester, StudyBooksScreen(tourId: 't1', repository: repo));

      await tester.tap(find.text('Add book'));
      await tester.pumpAndSettle();
      expect(find.text('New book'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Add a title for the book.'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.byType(TextField).first, 'Sapiens');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['add Sapiens']);
    });
  });

  group('the reading plan', () {
    final now = DateTime.now();
    final sessions = [
      ReadingSession(
        id: 's1',
        title: 'Chapters 1 to 3',
        startsAt: now.add(const Duration(days: 3)),
        createdByEmail: 'me@x.com',
      ),
      ReadingSession(
        id: 's2',
        title: 'Introduction',
        startsAt: now.subtract(const Duration(days: 10)),
        createdByEmail: 'other@x.com',
      ),
    ];

    testWidgets('upcoming and past sessions are shown in their own sections',
        (tester) async {
      await _pump(
          tester,
          StudyReadingScreen(
            tourId: 't1',
            repository: _FakeStudyRepo(sessions: sessions),
          ));

      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);
      expect(find.text('Chapters 1 to 3'), findsOneWidget);
      expect(find.text('Introduction'), findsOneWidget);
    });

    testWidgets('only the creator of a session gets its menu', (tester) async {
      await _pump(
          tester,
          StudyReadingScreen(
            tourId: 't1',
            repository: _FakeStudyRepo(sessions: sessions),
          ));

      // One session is mine; the other was planned by someone else and has no menu.
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('adding a session records it under the planner',
        (tester) async {
      final repo = _FakeStudyRepo();
      await _pump(tester, StudyReadingScreen(tourId: 't1', repository: repo));

      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();
      expect(find.text('New session'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Chapter 4');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['plan Chapter 4']);
    });
  });
}
