import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_problem_screen.dart';
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
  });

  final TourRole? role;

  /// The signed-in member's own working, by problem id.
  final Map<String, StudyProblemSolution> myWork;
  final StudyReferenceSolution? reference;

  /// Everyone's working on the problem, as the stream reports it.
  final List<StudyProblemSolution> workList;

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

    expect(repo.calls, ['review b@x.com right -']);
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
}
