import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_thread_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_problem_screen.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_problems_screen.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/group_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// One problem: its reference solution once it has opened, the member's own working, and the working of
// the others, which a member sees and reviews only after submitting their own. The fake repository
// records the calls it is asked to make; the real one writes them through the rules.

class _FakeProblemRepo extends TourGroupRepository {
  _FakeProblemRepo({
    required this.role,
    this.myWork = const {},
    this.reference,
    this.workList = const [],
    this.problemList = const [],
    this.setList = const [],
  });

  final TourRole? role;

  /// The signed-in member's own working, by problem id.
  final Map<String, StudyProblemSolution> myWork;
  final StudyReferenceSolution? reference;

  /// Everyone's working on the problem, as the stream reports it.
  final List<StudyProblemSolution> workList;

  /// The problems of the subject, and its problem sets, as the streams report them.
  final List<StudyProblem> problemList;
  final List<StudyProblemSet> setList;

  /// The signed-in member's review of each working, by the solver's email.
  final Map<String, StudyWorkReview> reviews = const {};
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Future<Map<String, StudyProblemSolution>> loadMyWork(
    String tourId,
    String subjectId,
    List<String> problemIds,
  ) async =>
      {
        for (final id in problemIds)
          if (myWork[id] != null) id: myWork[id]!,
      };

  @override
  Future<StudyReferenceSolution?> loadStudyReference(
    String tourId,
    String subjectId,
    String problemId,
  ) async {
    calls.add('reference');
    return reference;
  }

  @override
  Stream<List<StudyProblemSolution>> watchStudyWork(
    String tourId,
    String subjectId,
    String problemId,
  ) =>
      Stream.value(workList);

  @override
  Future<Map<String, StudyWorkReview>> loadMyWorkReviews(
    String tourId,
    String subjectId,
    String problemId,
    List<String> solverEmails,
  ) async =>
      {
        for (final email in solverEmails)
          if (reviews[email] != null) email: reviews[email]!,
      };

  @override
  Future<void> reviewStudyWork(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail, {
    required WorkVerdict verdict,
    String note = '',
  }) async {
    calls.add(
        'review $solverEmail ${verdict.name} ${note.isEmpty ? '-' : note}');
  }

  @override
  Future<void> reportStudyProblem(
    String tourId,
    String subjectId,
    String problemId, {
    required StudyReportReason reason,
  }) async {
    calls.add('report problem $problemId ${reason.name}');
  }

  @override
  Future<void> restoreStudyProblem(
    String tourId,
    String subjectId,
    String problemId,
  ) async {
    calls.add('restore problem $problemId');
  }

  @override
  Future<void> reportStudyWork(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail, {
    required StudyReportReason reason,
  }) async {
    calls.add('report work $solverEmail ${reason.name}');
  }

  @override
  Future<void> restoreStudyWork(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
  ) async {
    calls.add('restore work $solverEmail');
  }

  @override
  Stream<List<StudyProblem>> watchStudyProblems(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(problemList);

  @override
  Stream<List<StudyProblemSet>> watchStudyProblemSets(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(setList);

  @override
  Future<void> setStudyProblemSet(
    String tourId,
    String subjectId,
    String problemId,
    String? setId,
  ) async {
    calls.add('set problem $problemId ${setId ?? 'none'}');
  }
}

const _subject = StudySubject(id: 's1', title: 'Statistics 101');

const _module = StudyModuleSettings(
  key: StudyModuleKey.problems,
  enabled: true,
  name: 'Problems',
  postPolicy: StudyPostPolicy.members,
);

/// A problem whose reference solution opened in the past.
final _released = StudyProblem(
  id: 'p1',
  text: 'Find the mean of 2, 4 and 9.',
  title: 'Mean',
  createdByEmail: 'admin@x.com',
  createdAt: DateTime(2026, 11, 1),
  releaseAt: DateTime(2020, 1, 1),
);

/// A problem whose reference solution opens far in the future.
final _scheduled = StudyProblem(
  id: 'p2',
  text: 'Prove the claim.',
  createdByEmail: 'admin@x.com',
  createdAt: DateTime(2026, 11, 1),
  releaseAt: DateTime(2999, 1, 1),
);

/// The signed-in member's own working on the problem.
const _mine = StudyProblemSolution(
  solverEmail: 'me@x.com',
  text: 'My answer is 5.',
  rightCount: 0,
  gapCount: 0,
);

/// Another member's working, which has no reviews yet.
const _theirs = StudyProblemSolution(
  solverEmail: 'b@x.com',
  text: 'Working of b@x.com',
);

Future<void> _pump(WidgetTester tester, Widget page) async {
  // Unmount the page of an earlier pump first, so this one starts from its own initState.
  await tester.pumpWidget(const SizedBox());
  // A tall surface, so that every card of the page is built and can be found.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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

StudyProblemScreen _screen(_FakeProblemRepo repo, StudyProblem problem) =>
    StudyProblemScreen(
      tourId: 't1',
      subject: _subject,
      settings: _module,
      problem: problem,
      repository: repo,
    );

/// The problems list of the subject, the screen a member opens from the problem solving module.
StudyProblemsScreen _listScreen(_FakeProblemRepo repo) => StudyProblemsScreen(
      tourId: 't1',
      subject: _subject,
      settings: _module,
      repository: repo,
    );

/// Pumps the problems list of the subject.
Future<void> _pumpList(WidgetTester tester, _FakeProblemRepo repo) =>
    _pump(tester, _listScreen(repo));

/// A page with one button that opens [page] over it, so a test can press system back on [page].
class _OpenOver extends StatelessWidget {
  const _OpenOver({required this.page});

  final WidgetBuilder page;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: page),
            ),
            child: const Text('Open the page'),
          ),
        ),
      );
}

void main() {
  testWidgets(
      'a member who has not submitted their working sees the locked note, not the others\' working',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.member,
      workList: [_theirs],
    );
    await _pump(tester, _screen(repo, _released));

    expect(find.text('Submit working'), findsOneWidget);
    expect(
      find.textContaining('Submit your own working first'),
      findsOneWidget,
    );
    expect(find.text('Working of b@x.com'), findsNothing);
  });

  testWidgets(
      'a member who has submitted sees the others\' working, reviews it, and gets no buttons on their own',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.member,
      myWork: {'p1': _mine},
      workList: [_mine, _theirs],
    );
    await _pump(tester, _screen(repo, _released));

    expect(find.text('Working of b@x.com'), findsOneWidget);
    expect(find.text('Looks right'), findsOneWidget);
    expect(find.text('Found a gap'), findsOneWidget);

    await tester.tap(find.text('Looks right'));
    await tester.pumpAndSettle();

    expect(
      repo.calls.where((call) => call.startsWith('review')),
      ['review b@x.com right -'],
    );
    expect(find.text('You marked this right'), findsOneWidget);
    expect(find.text('Looks right'), findsNothing);
  });

  testWidgets(
      'the reference solution is read and marked as reviewed once its release day has come, and hidden before',
      (tester) async {
    final opened = _FakeProblemRepo(
      role: TourRole.member,
      reference: const StudyReferenceSolution(
        text: 'The answer is 5.',
        reviewedByEmail: 'admin@x.com',
      ),
    );
    await _pump(tester, _screen(opened, _released));

    expect(find.text('The answer is 5.'), findsOneWidget);
    expect(find.text('Reviewed by an admin'), findsOneWidget);

    final waiting = _FakeProblemRepo(
      role: TourRole.member,
      reference: const StudyReferenceSolution(
        text: 'The answer is 5.',
        reviewedByEmail: 'admin@x.com',
      ),
    );
    await _pump(tester, _screen(waiting, _scheduled));

    expect(find.text('The answer is 5.'), findsNothing);
    expect(find.textContaining('The answer opens on'), findsOneWidget);
    // The page does not even ask for a reference it may not read yet.
    expect(waiting.calls, isNot(contains('reference')));
  });
  testWidgets(
      'an admin with no working of their own sees the review buttons on a member\'s working, and reviews it',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.admin,
      workList: [_theirs],
    );
    await _pump(tester, _screen(repo, _released));

    expect(find.text('Working of b@x.com'), findsOneWidget);
    expect(find.text('Looks right'), findsOneWidget);
    expect(find.text('Found a gap'), findsOneWidget);

    await tester.tap(find.text('Looks right'));
    await tester.pumpAndSettle();

    expect(
      repo.calls.where((call) => call.startsWith('review')),
      ['review b@x.com right -'],
    );
  });

  testWidgets(
      'a member reports a problem someone else wrote, for the reason they choose',
      (tester) async {
    final repo = _FakeProblemRepo(role: TourRole.member);
    await _pump(tester, _screen(repo, _released));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report this problem'));
    await tester.pumpAndSettle();
    expect(find.text('Why are you reporting this problem?'), findsOneWidget);
    await tester.tap(find.text('It is unclear'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('report problem p1 unclear'));
  });

  testWidgets(
      'a member cannot report their own problem, so the menu has no report item',
      (tester) async {
    final repo = _FakeProblemRepo(role: TourRole.member);
    final own = StudyProblem(
      id: 'p3',
      text: 'My own problem.',
      createdByEmail: 'me@x.com',
      createdAt: DateTime(2026, 11, 1),
      releaseAt: DateTime(2020, 1, 1),
    );
    await _pump(tester, _screen(repo, own));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Report this problem'), findsNothing);
    expect(repo.calls.where((call) => call.startsWith('report')), isEmpty);
  });

  testWidgets('an admin sees a reported problem as hidden, and restores it',
      (tester) async {
    final repo = _FakeProblemRepo(role: TourRole.admin);
    final reported = StudyProblem(
      id: 'p1',
      text: 'Find the mean of 2, 4 and 9.',
      title: 'Mean',
      createdByEmail: 'admin@x.com',
      createdAt: DateTime(2026, 11, 1),
      releaseAt: DateTime(2020, 1, 1),
      shown: false,
      reportCount: 2,
      reportedAt: DateTime(2026, 11, 8),
    );
    await _pump(tester, _screen(repo, reported));

    expect(
        find.text(
            'Reported. It is hidden from members until an admin decides.'),
        findsOneWidget);
    expect(find.text('Reports so far: 2'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('restore problem p1'));
  });

  testWidgets(
      'a member does not see a reported working, and reports a peer\'s working for a reason they choose',
      (tester) async {
    final hidden = StudyProblemSolution(
      solverEmail: 'c@x.com',
      text: 'Hidden working of c@x.com',
      reportCount: 1,
      reportedAt: DateTime(2026, 11, 8),
    );
    final repo = _FakeProblemRepo(
      role: TourRole.member,
      myWork: {'p1': _mine},
      workList: [_mine, _theirs, hidden],
    );
    await _pump(tester, _screen(repo, _released));

    expect(find.text('Hidden working of c@x.com'), findsNothing);
    expect(find.text('Working of b@x.com'), findsOneWidget);

    await tester.tap(find.text('Report this working'));
    await tester.pumpAndSettle();
    expect(find.text('Why are you reporting this working?'), findsOneWidget);
    await tester.tap(find.text('It is wrong'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('report work b@x.com wrong'));
  });

  testWidgets(
      'an admin sees a reported working with its notice, and restores it',
      (tester) async {
    final reported = StudyProblemSolution(
      solverEmail: 'b@x.com',
      text: 'Working of b@x.com',
      reportCount: 1,
      reportedAt: DateTime(2026, 11, 8),
    );
    final repo = _FakeProblemRepo(role: TourRole.admin, workList: [reported]);
    await _pump(tester, _screen(repo, _released));

    expect(find.text('Working of b@x.com'), findsOneWidget);
    expect(
      find.text(
          'Reported. Other members cannot see this working until an admin decides.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('restore work b@x.com'));
  });

  testWidgets(
      'the problems list groups problems under their sets, nearest due first, and lists the rest under other problems',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.member,
      setList: [
        StudyProblemSet(
            id: 's-one', title: 'Week one', dueAt: DateTime(2999, 1, 1)),
        StudyProblemSet(
            id: 's-zero', title: 'Week zero', dueAt: DateTime(2020, 1, 1)),
      ],
      problemList: [
        StudyProblem(
          id: 'pa',
          text: 'A problem in week one',
          createdByEmail: 'admin@x.com',
          createdAt: DateTime(2026, 11, 1),
          releaseAt: DateTime(2020, 1, 1),
          setId: 's-one',
        ),
        StudyProblem(
          id: 'pb',
          text: 'A problem in week zero',
          createdByEmail: 'admin@x.com',
          createdAt: DateTime(2026, 11, 1),
          releaseAt: DateTime(2020, 1, 1),
          setId: 's-zero',
        ),
        StudyProblem(
          id: 'pc',
          text: 'A loose problem',
          createdByEmail: 'admin@x.com',
          createdAt: DateTime(2026, 11, 1),
          releaseAt: DateTime(2020, 1, 1),
        ),
      ],
    );
    await _pumpList(tester, repo);

    expect(find.text('Week zero'), findsOneWidget);
    expect(find.text('Week one'), findsOneWidget);
    expect(find.textContaining('Overdue'), findsOneWidget);
    expect(find.text('0 of 1 worked'), findsNWidgets(2));
    expect(find.text('Other problems'), findsOneWidget);
    expect(find.text('A loose problem'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Week zero')).dy,
      lessThan(tester.getTopLeft(find.text('Week one')).dy),
    );
  });

  testWidgets(
      'a set with no problems yet says so, even when the group has no problems',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.member,
      setList: [const StudyProblemSet(id: 's-empty', title: 'Empty set')],
    );
    await _pumpList(tester, repo);

    expect(find.text('Empty set'), findsOneWidget);
    expect(find.text('No problems in this set yet.'), findsOneWidget);
  });

  testWidgets(
      'an admin opens the problem sets from the list, and sees the sets there',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.admin,
      setList: [
        StudyProblemSet(
            id: 's-one', title: 'Week one', dueAt: DateTime(2999, 1, 1))
      ],
    );
    await _pumpList(tester, repo);

    await tester.tap(find.byIcon(Icons.library_books_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Add a set'), findsOneWidget);
    expect(find.text('Week one'), findsWidgets);
  });

  testWidgets(
      'an admin puts a problem into a set from its menu, and the page then names the set',
      (tester) async {
    final repo = _FakeProblemRepo(
      role: TourRole.admin,
      setList: [const StudyProblemSet(id: 's-one', title: 'Week one')],
    );
    await _pump(tester, _screen(repo, _released));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Put this problem in a set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week one'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('set problem p1 s-one'));
    expect(find.text('Set: Week one'), findsOneWidget);
  });

  testWidgets(
      'StudyProblemsScreen and StudyProblemScreen have GroupPopScope and GroupBackButton',
      (tester) async {
    final repo = _FakeProblemRepo(role: TourRole.member);
    await _pump(tester, _screen(repo, _released));

    // The problem page has the pop scope and the back button.
    expect(find.byType(GroupPopScope), findsOneWidget);
    expect(find.byType(GroupBackButton), findsOneWidget);

    // The problems list has them too.
    await _pumpList(tester, repo);

    expect(find.byType(GroupPopScope), findsOneWidget);
    expect(find.byType(GroupBackButton), findsOneWidget);
  });

  testWidgets(
      'system back and the back arrow both close a problem screen opened over another route',
      (tester) async {
    final repo = _FakeProblemRepo(role: TourRole.member);
    await _pump(tester, _OpenOver(page: (_) => _screen(repo, _released)));

    // System back takes the screen off the stack and shows the page under it.
    await tester.tap(find.text('Open the page'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyProblemScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(StudyProblemScreen), findsNothing);
    expect(find.text('Open the page'), findsOneWidget);

    // The back arrow in the app bar does the same.
    await tester.tap(find.text('Open the page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GroupBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(StudyProblemScreen), findsNothing);
    expect(find.text('Open the page'), findsOneWidget);
  });

  testWidgets(
      'system back and the back arrow both close the problems list opened over another route',
      (tester) async {
    final repo = _FakeProblemRepo(role: TourRole.member);
    await _pump(tester, _OpenOver(page: (_) => _listScreen(repo)));

    await tester.tap(find.text('Open the page'));
    await tester.pumpAndSettle();
    expect(find.byType(StudyProblemsScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(StudyProblemsScreen), findsNothing);
    expect(find.text('Open the page'), findsOneWidget);

    await tester.tap(find.text('Open the page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GroupBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(StudyProblemsScreen), findsNothing);
    expect(find.text('Open the page'), findsOneWidget);
  });
}
