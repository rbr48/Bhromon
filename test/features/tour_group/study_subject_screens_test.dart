import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_module_posts_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_subject_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_subjects_screen.dart';
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
    this.role,
  });

  final List<StudySubject> subjects;
  final Map<StudyModuleKey, StudyModuleSettings> modules;
  final List<StudyPost> posts;

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
        'an admin sees every module, the modules not yet built as coming soon, and can customise',
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
      expect(find.text('Coming soon'), findsWidgets);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
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
}
