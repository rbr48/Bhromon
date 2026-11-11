import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/study_reading_position.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_material_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_book_chapters_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_chapter_editor.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_vote_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The chapters of a listed book, the votes on a proposal, and the chapter editor, with a fake
// repository that records each change. Dates are far enough ahead that the tests do not depend
// on the day they run. The rules these screens follow are tested on the emulator in
// functions/tests/study_chapters_rules.test.js.

class _FakeChapterRepo extends TourGroupRepository {
  _FakeChapterRepo({
    this.chapters = const [],
    this.marks = const {},
    this.materials = const [],
    this.role,
    this.votes = StudyVoteTally.none,
  });

  final List<StudyChapter> chapters;
  final Map<String, StudyReadMark> marks;
  final List<StudyMaterial> materials;
  final TourRole? role;
  final StudyVoteTally votes;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudyChapter>> watchStudyChapters(String tourId, String bookId) =>
      Stream.value(chapters);

  @override
  Stream<List<StudyMaterial>> watchStudyMaterials(
          String tourId, String bookId) =>
      Stream.value(materials);

  @override
  Stream<Map<String, StudyReadMark>> watchMyReadMarks(
    String tourId,
    String bookId,
  ) =>
      Stream.value(marks);

  @override
  Stream<StudyVoteTally> watchStudyBookVotes(String tourId, String bookId) =>
      Stream.value(votes);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) =>
      Stream.value(const []);

  @override
  Future<void> markStudyChapterRead(
    String tourId,
    String bookId,
    String chapterId, {
    required bool counted,
  }) async {
    calls.add('read $chapterId counted=$counted');
  }

  @override
  Future<void> unmarkStudyChapterRead(
    String tourId,
    String bookId,
    String chapterId,
  ) async {
    calls.add('unread $chapterId');
  }

  @override
  Future<void> setStudyChapterReadCounted(
    String tourId,
    String bookId,
    String chapterId, {
    required bool counted,
  }) async {
    calls.add('counted $chapterId $counted');
  }

  @override
  Future<void> setStudyReadingPace(
    String tourId,
    String bookId, {
    required List<StudyChapter> chapters,
    required DateTime start,
    required int perWeek,
  }) async {
    calls.add('pace $perWeek ${chapters.length}');
  }

  @override
  Future<void> setStudyBookVote(
    String tourId,
    String bookId, {
    required bool voted,
  }) async {
    calls.add('vote $voted');
  }
}

/// The reading position kept in memory, so a test sees what the screen saved.
class _FakePosition extends StudyReadingPosition {
  _FakePosition();

  int? number;

  @override
  Future<int?> load({required String tourId, required String bookId}) async =>
      number;

  @override
  Future<void> save({
    required String tourId,
    required String bookId,
    required int? chapterNumber,
  }) async {
    number = chapterNumber;
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

const _book =
    StudyBook(id: 'b1', title: 'Anna Karenina', createdByEmail: 'admin@x.com');

final _chapters = [
  StudyChapter(
    id: 'c2',
    number: 2,
    title: 'Second',
    pageFrom: 21,
    pageTo: 40,
    dueOn: DateTime(2030, 3, 15),
  ),
  StudyChapter(
    id: 'c1',
    number: 1,
    title: 'First',
    pageFrom: 1,
    pageTo: 20,
    dueOn: DateTime(2030, 3, 1),
    guide: const ['Why does the first line matter?'],
  ),
];

void main() {
  group('the chapters of a book', () {
    testWidgets(
        'a member sees the chapters in order, with pages, due dates and guide questions',
        (tester) async {
      final repo = _FakeChapterRepo(chapters: _chapters);
      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: _FakePosition(),
        ),
      );

      expect(find.text('Chapter 1 · First'), findsOneWidget);
      expect(find.text('Chapter 2 · Second'), findsOneWidget);
      expect(find.textContaining('pp. 1–20'), findsOneWidget);
      expect(find.textContaining('Due 1 Mar 2030'), findsOneWidget);
      expect(find.text('Next: chapter 1'), findsOneWidget);
      // A member cannot add a chapter.
      expect(find.text('Add chapter'), findsNothing);

      await tester.tap(find.textContaining('Guide questions'));
      await tester.pumpAndSettle();
      expect(find.text('Why does the first line matter?'), findsOneWidget);
    });

    testWidgets(
        'renders official syllabus blueprint card with interactive module selection',
        (tester) async {
      const lpgbBook = StudyBook(
        id: 'b_lpgb',
        title: 'Laws & Practice of General Banking (LPGB)',
        createdByEmail: 'admin@x.com',
      );
      final repo = _FakeChapterRepo(chapters: _chapters);
      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: lpgbBook,
          repository: repo,
          position: _FakePosition(),
        ),
      );

      // Verify blueprint card header and module chips exist
      expect(find.text('Official Syllabus & Blueprint'), findsOneWidget);
      expect(find.text('All Modules'), findsOneWidget);
      expect(find.text('Module A'), findsOneWidget);
      expect(find.text('Module B'), findsOneWidget);
      expect(find.text('Module C'), findsOneWidget);

      // Tap Module A to inspect module description
      await tester.tap(find.text('Module A'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Module A: Legal & Regulatory Framework'),
        findsOneWidget,
      );

      // Tap 'All Modules' button to reset selection
      await tester.tap(find.widgetWithText(TextButton, 'All Modules'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Module A: Legal & Regulatory Framework'),
        findsNothing,
      );
    });

    testWidgets('a member marks a chapter read in their own name',
        (tester) async {
      final repo = _FakeChapterRepo(chapters: _chapters);
      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: _FakePosition(),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['read c1 counted=false']);
    });

    testWidgets(
        'a member who has read a chapter can count it in the group total',
        (tester) async {
      final repo = _FakeChapterRepo(chapters: _chapters, marks: {
        'c1': StudyReadMark(chapterId: 'c1', readAt: DateTime(2030, 1, 1)),
      });
      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: _FakePosition(),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count in the group total'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['counted c1 true']);
    });

    testWidgets('a member keeps their place in the book on this device',
        (tester) async {
      final position = _FakePosition();
      final repo = _FakeChapterRepo(chapters: _chapters);
      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: position,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I am on this chapter'));
      await tester.pumpAndSettle();

      expect(position.number, 2);
      expect(find.text('You are on chapter 2'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('an admin sets the reading pace for the chapters',
        (tester) async {
      final repo = _FakeChapterRepo(chapters: _chapters, role: TourRole.admin);
      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: _FakePosition(),
        ),
      );

      expect(find.text('Add chapter'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.timeline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Reading pace'), findsWidgets);

      await tester.tap(find.text('Set due dates'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['pace 2 2']);
    });

    testWidgets(
        'a chapter offers one-tap solutions for a PDF and a note, never for audio',
        (tester) async {
      // The audio file comes first, so a rule that let it through would show it as the English button.
      const audioSol = StudyMaterial(
        id: 'm0',
        title: 'Chapter 1 lecture (audio)',
        kind: StudyMaterialKind.audio,
        bookId: 'b1',
        chapterId: 'c1',
        status: StudyMaterialStatus.published,
        url:
            'https://bhromon.fun/media/T/study/0123456789abcdef0123456789abcdef.mp3',
        fileName: 'Chapter1_Lecture.mp3',
        sizeBytes: 2048,
      );
      // An uploaded PDF: the viewer fetches it from its address, so it has no body here.
      const englishSol = StudyMaterial(
        id: 'm1',
        title: '98th BPE - Master Solutions (English)',
        kind: StudyMaterialKind.file,
        bookId: 'b1',
        chapterId: 'c1',
        status: StudyMaterialStatus.published,
        url:
            'https://bhromon.fun/media/T/study/fedcba9876543210fedcba9876543210.pdf',
        fileName: 'JAIBB_Accounting_98th_BPE_Solutions.pdf',
        sizeBytes: 90000,
      );
      // A note has its text and no file size.
      const banglaSol = StudyMaterial(
        id: 'm2',
        title: '৯৮তম বিপিই - মাস্টার সমাধান (বাংলা)',
        kind: StudyMaterialKind.note,
        bookId: 'b1',
        chapterId: 'c1',
        status: StudyMaterialStatus.published,
        body: 'বাংলা সমাধান টেক্সট',
      );

      final repo = _FakeChapterRepo(
        chapters: _chapters,
        materials: [audioSol, englishSol, banglaSol],
      );

      await _pump(
        tester,
        StudyBookChaptersScreen(
          tourId: 'T',
          book: _book,
          repository: repo,
          position: _FakePosition(),
        ),
      );

      // The larger English file is the one offered, beside the Bangla one.
      expect(find.text('English'), findsOneWidget);
      expect(find.text('88 KB'), findsOneWidget);
      expect(find.text('2 KB'), findsNothing);
      expect(find.text('বাংলা'), findsOneWidget);
      expect(find.text('🇬🇧'), findsNothing);
      expect(find.text('🇧🇩'), findsNothing);
    });
  });

  group('votes on a proposal', () {
    testWidgets('a member sees the count and says they would read the book',
        (tester) async {
      final repo =
          _FakeChapterRepo(votes: const StudyVoteTally(count: 3, mine: false));
      await _pump(
        tester,
        Scaffold(
          body: StudyVoteRow(tourId: 'T', bookId: 'p1', repository: repo),
        ),
      );

      expect(find.text('3 would read this'), findsOneWidget);
      await tester.tap(find.text('I would read this'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['vote true']);
    });

    testWidgets('a member who has voted can take the vote back',
        (tester) async {
      final repo =
          _FakeChapterRepo(votes: const StudyVoteTally(count: 1, mine: true));
      await _pump(
        tester,
        Scaffold(
          body: StudyVoteRow(tourId: 'T', bookId: 'p1', repository: repo),
        ),
      );

      await tester.tap(find.text('Take my vote back'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['vote false']);
    });
  });

  group('the chapter editor', () {
    testWidgets(
        'it refuses a blank title and a page range that runs backwards, then saves',
        (tester) async {
      StudyChapterDraft? saved;
      var opened = false;
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = true;
                saved =
                    await showStudyChapterEditor(context, suggestedNumber: 1);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);

      // The number is pre-filled with 1, so only the title is missing.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Give the chapter a title'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(find.byType(TextField).at(1), 'Part one');
      await tester.enterText(find.byType(TextField).at(2), '20');
      await tester.enterText(find.byType(TextField).at(3), '10');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check the pages'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(find.byType(TextField).at(3), '25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.number, 1);
      expect(saved?.title, 'Part one');
      expect(saved?.pageFrom, 20);
      expect(saved?.pageTo, 25);
    });
  });
}
