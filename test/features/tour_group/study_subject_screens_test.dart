import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_challenge_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_today_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_module_posts_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_subject_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_subjects_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_subject_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The subject list, a subject's modules and a module's posts, with a fake repository that
// records each change. The rules these screens follow are in firestore.rules and are tested
// on the emulator in functions/tests/study_subjects_rules.test.js.

class _FakeSubjectRepo extends TourGroupRepository {
  _FakeSubjectRepo({
    this.subjects = const [],
    this.modules = const {},
    this.posts = const [],
    this.books = const [],
    this.role,
  });

  final List<StudySubject> subjects;
  final Map<StudyModuleKey, StudyModuleSettings> modules;
  final List<StudyPost> posts;

  /// The books of the group, which a subject's book modules open.
  final List<StudyBook> books;

  /// The signed-in member's role. Null is an ordinary member.
  final TourRole? role;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudySubject>> watchStudySubjects(String tourId) =>
      Stream.value(subjects);

  @override
  Stream<Map<StudyModuleKey, StudyModuleSettings>> watchStudyModules(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(modules);

  @override
  Stream<List<StudyPost>> watchStudyPosts(
    String tourId,
    String subjectId,
    StudyModuleKey key,
  ) =>
      Stream.value(posts);

  @override
  Future<void> approveStudySubject(String tourId, String subjectId) async {
    calls.add('list $subjectId');
  }

  @override
  Future<void> setStudySubjectArchived(
    String tourId,
    String subjectId, {
    required bool archived,
  }) async {
    calls.add('archive $subjectId $archived');
  }

  // The Today card of a subject reads these. They are empty here, so the card says that nothing is due.
  @override
  Stream<StudyChallenge?> watchStudyChallenge(
    String tourId,
    String subjectId,
    String weekKey,
  ) =>
      Stream.value(null);

  @override
  Stream<Set<String>> watchChallengeJoins(
    String tourId,
    String subjectId,
    String weekKey,
  ) =>
      Stream.value(const {});

  @override
  Future<int> countMyChallengeTasks(
    String tourId,
    String subjectId,
    ChallengeKind kind,
    DateTime weekStart, {
    required Future<int> Function() cardsReviewed,
  }) async =>
      0;

  @override
  Future<List<StudyDeadline>> loadStudyDeadlines(String tourId) async =>
      const [];

  @override
  Stream<List<StudyFinding>> watchStudyFindings(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(const []);

  @override
  Future<Map<String, StudyFindingCheck>> loadMyFindingChecks(
    String tourId,
    String subjectId,
    List<String> findingIds,
  ) async =>
      const {};

  @override
  Stream<List<StudyProblemSet>> watchStudyProblemSets(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(const []);

  @override
  Stream<List<StudyProblem>> watchStudyProblems(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(const []);

  @override
  Future<Map<String, StudyProblemSolution>> loadMyWork(
    String tourId,
    String subjectId,
    List<String> problemIds,
  ) async =>
      const {};

  @override
  Future<Map<String, DateTime>> loadMyProblemSetDeadlines(
    String tourId,
    String subjectId,
    List<String> setIds,
  ) async =>
      const {};

  @override
  Stream<List<StudyBook>> watchStudyBooks(String tourId) => Stream.value(books);

  @override
  Future<bool> toggleStudyPostHelpful(
    String tourId,
    String subjectId,
    StudyModuleKey key,
    String postId,
  ) async {
    calls.add('helpful $postId');
    return true;
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

const _physics = StudySubject(
  id: 'phy',
  title: 'Physics 101',
  code: 'PHY 101',
  createdByEmail: 'admin@x.com',
);

/// A subject a member proposed and no admin has decided on yet.
const _chemistry = StudySubject(
  id: 'chem',
  title: 'Chemistry',
  approval: StudyBookApproval.proposed,
  createdByEmail: 'other@x.com',
);

/// A subject an admin archived. Members do not see it.
const _biology = StudySubject(
  id: 'bio',
  title: 'Biology',
  code: 'BIO 101',
  archived: true,
  createdByEmail: 'admin@x.com',
);

const _physicsWithBook = StudySubject(
  id: 'phy',
  title: 'Physics 101',
  code: 'PHY 101',
  createdByEmail: 'admin@x.com',
  bookId: 'phy-book',
);

const _physicsBook = StudyBook(
  id: 'phy-book',
  title: 'Physics Vol 1',
  createdByEmail: 'admin@x.com',
);

const _declinedBook = StudyBook(
  id: 'old-book',
  title: 'Old notes',
  createdByEmail: 'other@x.com',
  approval: StudyBookApproval.declined,
  declineNote: 'Too old',
);

StudyModuleSettings _on(StudyModuleKey key, String name) => StudyModuleSettings(
      key: key,
      enabled: true,
      name: name,
      postPolicy: StudyPostPolicy.members,
    );

const _tipsOn = StudyModuleSettings(
  key: StudyModuleKey.tips,
  enabled: true,
  name: 'Exam tips',
  postPolicy: StudyPostPolicy.members,
);

const _suggestionsOff = StudyModuleSettings(
  key: StudyModuleKey.suggestions,
  enabled: false,
  name: 'Suggestions',
  postPolicy: StudyPostPolicy.members,
);

void main() {
  group('the subject list', () {
    testWidgets(
        'a member sees the listed subjects and a proposal waiting for an admin',
        (tester) async {
      final repo = _FakeSubjectRepo(subjects: [_physics, _chemistry]);
      await _pump(tester, StudySubjectsScreen(tourId: 'T', repository: repo));

      expect(find.text('Physics 101'), findsOneWidget);
      expect(find.text('Chemistry'), findsOneWidget);
      expect(find.text('Propose a subject'), findsOneWidget);
      expect(find.text('Add this subject'), findsNothing);
    });

    testWidgets('an admin lists a proposal from the list', (tester) async {
      final repo = _FakeSubjectRepo(
        subjects: [_physics, _chemistry],
        role: TourRole.admin,
      );
      await _pump(tester, StudySubjectsScreen(tourId: 'T', repository: repo));

      expect(find.text('Add subject'), findsOneWidget);
      await tester.tap(find.text('Add this subject'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['list chem']);
    });

    testWidgets(
        'a member does not see an archived subject, and has no archive action',
        (tester) async {
      final repo = _FakeSubjectRepo(subjects: [_physics, _biology]);
      await _pump(tester, StudySubjectsScreen(tourId: 'T', repository: repo));

      expect(find.text('Physics 101'), findsOneWidget);
      expect(find.text('Biology'), findsNothing);
      expect(find.text('Archived'), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });

    testWidgets('an admin sees the archive, and restores a subject from it',
        (tester) async {
      final repo = _FakeSubjectRepo(
        subjects: [_physics, _biology],
        role: TourRole.admin,
      );
      await _pump(tester, StudySubjectsScreen(tourId: 'T', repository: repo));

      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('Biology'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['archive bio false']);
    });

    testWidgets('an admin archives a listed subject from its menu',
        (tester) async {
      final repo = _FakeSubjectRepo(
        subjects: [_physics],
        role: TourRole.admin,
      );
      await _pump(tester, StudySubjectsScreen(tourId: 'T', repository: repo));

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive subject'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['archive phy true']);
    });
  });

  group('a subject\'s modules', () {
    testWidgets(
        'a member sees only the live modules that are on, and cannot customise',
        (tester) async {
      final repo = _FakeSubjectRepo(modules: {
        StudyModuleKey.tips: _tipsOn,
        StudyModuleKey.suggestions: _suggestionsOff,
      });
      await _pump(
        tester,
        StudySubjectScreen(tourId: 'T', subject: _physics, repository: repo),
      );

      expect(find.text('Exam tips'), findsOneWidget);
      expect(find.text('Suggestions'), findsNothing);
      expect(find.text('Discussion'), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
    });

    testWidgets(
        'an admin sees every module, each one a choice, and can customise',
        (tester) async {
      final repo = _FakeSubjectRepo(
        role: TourRole.admin,
        modules: {StudyModuleKey.tips: _tipsOn},
      );
      await _pump(
        tester,
        StudySubjectScreen(tourId: 'T', subject: _physics, repository: repo),
      );

      expect(find.text('Exam tips'), findsOneWidget);
      expect(find.text('Suggestions'), findsOneWidget);
      expect(find.text('Discussion'), findsOneWidget);
      // The list is built as it scrolls, so the last modules are scrolled into view to check they are there.
      await tester.scrollUntilVisible(find.text('Assignments'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Assignments'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Quizzes'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });
    testWidgets(
        'a book module opens the subject\'s book: it shows the book, and a member can open it',
        (tester) async {
      final repo = _FakeSubjectRepo(
        modules: {
          StudyModuleKey.discussion:
              _on(StudyModuleKey.discussion, 'Discussion')
        },
        books: const [_physicsBook],
      );
      await _pump(
        tester,
        StudySubjectScreen(
            tourId: 'T', subject: _physicsWithBook, repository: repo),
      );

      final tile = find.widgetWithText(ListTile, 'Discussion');
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('Physics Vol 1')),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile, matching: find.byIcon(Icons.chevron_right_rounded)),
          findsOneWidget);
    });

    testWidgets('a member does not see a book module of a subject with no book',
        (tester) async {
      final repo = _FakeSubjectRepo(
        modules: {
          StudyModuleKey.quizzes: _on(StudyModuleKey.quizzes, 'Quizzes')
        },
      );
      await _pump(
        tester,
        StudySubjectScreen(tourId: 'T', subject: _physics, repository: repo),
      );

      expect(find.text('Quizzes'), findsNothing);
    });

    testWidgets(
        'an admin sees that a book module waits for a book, and cannot open it',
        (tester) async {
      final repo = _FakeSubjectRepo(
        role: TourRole.admin,
        modules: {
          StudyModuleKey.quizzes: _on(StudyModuleKey.quizzes, 'Quizzes')
        },
      );
      await _pump(
        tester,
        StudySubjectScreen(tourId: 'T', subject: _physics, repository: repo),
      );

      await tester.scrollUntilVisible(find.text('Quizzes'), 300,
          scrollable: find.byType(Scrollable).first);
      final tile = find.widgetWithText(ListTile, 'Quizzes');
      expect(tile, findsOneWidget);
      expect(
          find.descendant(
              of: tile,
              matching: find
                  .text('Choose a book for this subject to open this module.')),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile, matching: find.byIcon(Icons.chevron_right_rounded)),
          findsNothing);
    });
  });

  group('a module\'s posts', () {
    final posts = [
      StudyPost(
        id: 'mine',
        text: 'Revise the formulas',
        createdByEmail: 'me@x.com',
        createdAt: DateTime(2026, 11, 2),
      ),
      StudyPost(
        id: 'theirs',
        text: 'Past papers beat notes',
        createdByEmail: 'other@x.com',
        createdAt: DateTime(2026, 11, 1),
        helpfulCount: 2,
      ),
    ];

    testWidgets(
        'a member marks another member\'s post helpful, and not their own',
        (tester) async {
      final repo = _FakeSubjectRepo(posts: posts);
      await _pump(
        tester,
        StudyModulePostsScreen(
          tourId: 'T',
          subject: _physics,
          moduleKey: StudyModuleKey.tips,
          settings: _tipsOn,
          repository: repo,
        ),
      );

      // Someone else's post is marked, and the count moves with the mark.
      await tester.tap(find.text('Helpful (2)'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['helpful theirs']);

      // The member's own post has its helpful button disabled.
      final own = tester.widget<TextButton>(find.ancestor(
        of: find.text('Helpful (0)'),
        matching: find.byType(TextButton),
      ));
      expect(own.onPressed, isNull);
    });

    testWidgets(
        'a member cannot add a tip to a module that only admins post in',
        (tester) async {
      const adminsOnly = StudyModuleSettings(
        key: StudyModuleKey.tips,
        enabled: true,
        name: 'Exam tips',
        postPolicy: StudyPostPolicy.admins,
      );
      await _pump(
        tester,
        StudyModulePostsScreen(
          tourId: 'T',
          subject: _physics,
          moduleKey: StudyModuleKey.tips,
          settings: adminsOnly,
          repository: _FakeSubjectRepo(posts: posts),
        ),
      );
      expect(find.text('Add a tip'), findsNothing);
    });

    testWidgets('past papers are added with their own label, and take a link',
        (tester) async {
      await _pump(
        tester,
        StudyModulePostsScreen(
          tourId: 'T',
          subject: _physics,
          moduleKey: StudyModuleKey.papers,
          settings: _on(StudyModuleKey.papers, 'Past papers'),
          repository: _FakeSubjectRepo(role: TourRole.admin),
        ),
      );
      expect(find.text('Add a past paper'), findsOneWidget);
      expect(find.text('Add a tip'), findsNothing);
    });

    testWidgets('a past paper offers a file to attach, and a tip does not',
        (tester) async {
      await _pump(
        tester,
        StudyModulePostsScreen(
          tourId: 'T',
          subject: _physics,
          moduleKey: StudyModuleKey.papers,
          settings: _on(StudyModuleKey.papers, 'Past papers'),
          repository: _FakeSubjectRepo(role: TourRole.admin),
        ),
      );
      await tester.tap(find.text('Add a past paper'));
      await tester.pumpAndSettle();
      expect(find.text('Attach a file'), findsOneWidget);
    });

    // A separate test, so the screen starts afresh and reads the admin role itself.
    testWidgets('an admin adds a tip to a module that only admins post in',
        (tester) async {
      const adminsOnly = StudyModuleSettings(
        key: StudyModuleKey.tips,
        enabled: true,
        name: 'Exam tips',
        postPolicy: StudyPostPolicy.admins,
      );
      await _pump(
        tester,
        StudyModulePostsScreen(
          tourId: 'T',
          subject: _physics,
          moduleKey: StudyModuleKey.tips,
          settings: adminsOnly,
          repository: _FakeSubjectRepo(posts: posts, role: TourRole.admin),
        ),
      );
      expect(find.text('Add a tip'), findsOneWidget);
    });
  });

  group('the subject editor\'s book', () {
    Future<void> openEditor(
      WidgetTester tester,
      void Function(StudySubjectDraft? draft) onResult, {
      StudySubject? existing,
    }) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => onResult(await showStudySubjectEditor(
                  context,
                  existing: existing,
                  books: const [_physicsBook, _declinedBook],
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers the listed books only, and returns the one chosen',
        (tester) async {
      StudySubjectDraft? result;
      await openEditor(tester, (draft) => result = draft);

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      expect(find.text('Physics Vol 1'), findsWidgets);
      expect(find.text('Old notes'), findsNothing);
      await tester.tap(find.text('Physics Vol 1').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Physics 101');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(result?.bookId, 'phy-book');
    });

    testWidgets('a subject whose book was removed saves with no book',
        (tester) async {
      StudySubjectDraft? result;
      await openEditor(
        tester,
        (draft) => result = draft,
        existing: const StudySubject(
          id: 'phy',
          title: 'Physics 101',
          createdByEmail: 'admin@x.com',
          bookId: 'gone-book',
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result?.bookId, isNull);
    });
  });
}
