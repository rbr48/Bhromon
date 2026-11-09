import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_challenge_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_today_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_today_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The Today card: what needs a member today, on a subject and on a study group's home.

class _FakeTodayRepo extends TourGroupRepository {
  _FakeTodayRepo({
    this.challenge,
    this.joins = const {},
    this.done = 0,
    this.deadlines = const [],
    this.findings = const [],
    this.subjects = const [],
    this.problemSets = const [],
    this.problems = const [],
    this.myWork = const {},
  });

  final StudyChallenge? challenge;
  final Set<String> joins;
  final int done;
  final List<StudyDeadline> deadlines;
  final List<StudyFinding> findings;
  final List<StudySubject> subjects;
  final List<StudyProblemSet> problemSets;
  final List<StudyProblem> problems;
  final Map<String, StudyProblemSolution> myWork;

  @override
  String get currentEmail => 'me@x.com';

  @override
  Stream<StudyChallenge?> watchStudyChallenge(
    String tourId,
    String subjectId,
    String weekKey,
  ) =>
      Stream.value(challenge);

  @override
  Stream<Set<String>> watchChallengeJoins(
    String tourId,
    String subjectId,
    String weekKey,
  ) =>
      Stream.value(joins);

  @override
  Future<int> countMyChallengeTasks(
    String tourId,
    String subjectId,
    ChallengeKind kind,
    DateTime weekStart, {
    required Future<int> Function() cardsReviewed,
  }) async =>
      done;

  @override
  Future<List<StudyDeadline>> loadStudyDeadlines(String tourId) async =>
      deadlines;

  @override
  Stream<List<StudyFinding>> watchStudyFindings(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(findings);

  @override
  Future<Map<String, StudyFindingCheck>> loadMyFindingChecks(
    String tourId,
    String subjectId,
    List<String> findingIds,
  ) async =>
      const {};

  @override
  Stream<List<StudySubject>> watchStudySubjects(String tourId) =>
      Stream.value(subjects);

  @override
  Stream<List<StudyProblemSet>> watchStudyProblemSets(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(problemSets);

  @override
  Stream<List<StudyProblem>> watchStudyProblems(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(problems);

  @override
  Future<Map<String, StudyProblemSolution>> loadMyWork(
    String tourId,
    String subjectId,
    List<String> problemIds,
  ) async =>
      myWork;
}

const _subject = StudySubject(
  id: 's1',
  title: 'Statistics 101',
);

final _examSubject = StudySubject(
  id: 's1',
  title: 'Statistics 101',
  examDate: DateTime(2026, 11, 15),
);

const _findingsModule = StudyModuleSettings(
  key: StudyModuleKey.findings,
  enabled: true,
  name: 'Shared findings',
  postPolicy: StudyPostPolicy.members,
);

const _challengeModule = StudyModuleSettings(
  key: StudyModuleKey.challenges,
  enabled: true,
  name: 'Weekly challenge',
  postPolicy: StudyPostPolicy.admins,
);

const _problemsModule = StudyModuleSettings(
  key: StudyModuleKey.problems,
  enabled: true,
  name: 'Problem solving',
  postPolicy: StudyPostPolicy.members,
);

/// The Tuesday of the week that starts on 2026-11-09.
final _tuesday = DateTime(2026, 11, 10, 9);

final _twoOthersFindings = [
  const StudyFinding(
    id: 'f1',
    text: 'a result',
    method: 'a method',
    createdByEmail: 'b@x.com',
  ),
  const StudyFinding(
    id: 'f2',
    text: 'another result',
    method: 'a method',
    createdByEmail: 'c@x.com',
  ),
];

Future<void> _pump(WidgetTester tester, Widget page) async {
  // Unmount the page of an earlier pump first, so this one starts from its own initState.
  await tester.pumpWidget(const SizedBox());
  // A tall surface, so that every line of the card is built and can be found.
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
    home: Scaffold(body: SingleChildScrollView(child: page)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a subject shows its exam in exam mode, the next deadline, the findings waiting and the cards due',
      (tester) async {
    final opened = <StudyModuleSettings>[];
    final repo = _FakeTodayRepo(
      deadlines: [
        StudyDeadline(
          chapterId: 'c3',
          bookTitle: 'Book',
          chapterTitle: 'Chapter 3',
          dueOn: DateTime(2026, 11, 12),
        ),
      ],
      findings: _twoOthersFindings,
    );
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _examSubject,
        repository: repo,
        today: _tuesday,
        findingsModule: _findingsModule,
        onOpenModule: opened.add,
        cardsDue: () async => 3,
      ),
    );

    expect(
      find.text(
          'Exam mode: 5 days to go. Practise problems and read the tips first.'),
      findsOneWidget,
    );
    expect(find.text('Next due: Chapter 3 (Book), 12 Nov'), findsOneWidget);
    expect(find.text('2 findings are waiting for your check.'), findsOneWidget);
    expect(find.text('3 flashcards are due today.'), findsOneWidget);

    await tester.tap(find.text('2 findings are waiting for your check.'));
    await tester.pumpAndSettle();
    expect(opened.map((m) => m.key), [StudyModuleKey.findings]);
  });

  testWidgets('a subject with nothing due says so', (tester) async {
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _subject,
        repository: _FakeTodayRepo(),
        today: _tuesday,
        onOpenModule: (_) {},
        cardsDue: () async => 0,
      ),
    );

    expect(find.text('Nothing needs you today.'), findsOneWidget);
  });

  testWidgets('a findings line is not shown when the findings module is off',
      (tester) async {
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _subject,
        repository: _FakeTodayRepo(findings: _twoOthersFindings),
        today: _tuesday,
        onOpenModule: (_) {},
        cardsDue: () async => 0,
      ),
    );

    expect(find.text('2 findings are waiting for your check.'), findsNothing);
    expect(find.text('Nothing needs you today.'), findsOneWidget);
  });

  testWidgets(
      'a member who has not joined this week\'s open challenge is invited to join it',
      (tester) async {
    final opened = <StudyModuleSettings>[];
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _subject,
        repository: _FakeTodayRepo(
          challenge: const StudyChallenge(
            weekKey: '2026-11-09',
            kind: ChallengeKind.cards,
            target: 5,
          ),
        ),
        today: _tuesday,
        challengeModule: _challengeModule,
        onOpenModule: opened.add,
        cardsDue: () async => 0,
      ),
    );

    expect(
      find.text('A weekly challenge is open. Join it to track your work.'),
      findsOneWidget,
    );
    await tester.tap(
      find.text('A weekly challenge is open. Join it to track your work.'),
    );
    await tester.pumpAndSettle();
    expect(opened.map((m) => m.key), [StudyModuleKey.challenges]);
  });

  testWidgets('a member who has joined sees the challenge progress',
      (tester) async {
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _subject,
        repository: _FakeTodayRepo(
          challenge: const StudyChallenge(
            weekKey: '2026-11-09',
            kind: ChallengeKind.problems,
            target: 5,
          ),
          joins: const {'me@x.com'},
          done: 2,
        ),
        today: _tuesday,
        challengeModule: _challengeModule,
        onOpenModule: (_) {},
        cardsDue: () async => 0,
      ),
    );

    expect(find.text('Weekly challenge: 2 of 5 done.'), findsOneWidget);
  });

  testWidgets(
      'a study group\'s home shows the nearest exam across its subjects and the next deadline',
      (tester) async {
    await _pump(
      tester,
      StudyGroupTodayCard(
        tourId: 't1',
        repository: _FakeTodayRepo(
          subjects: [
            _examSubject,
            StudySubject(
              id: 's2',
              title: 'Physics',
              examDate: DateTime(2026, 11, 13),
            ),
          ],
          deadlines: [
            StudyDeadline(
              chapterId: 'c1',
              bookTitle: 'Book',
              chapterTitle: 'Chapter 1',
              dueOn: DateTime(2026, 11, 11),
            ),
          ],
        ),
        today: _tuesday,
        cardsDue: () async => 0,
      ),
    );

    expect(find.text('Physics: exam in 3 days'), findsOneWidget);
    expect(find.text('Next due: Chapter 1 (Book), 11 Nov'), findsOneWidget);
    expect(find.textContaining('Statistics 101'), findsNothing);
  });

  testWidgets(
      'a problem set due soon shows the viewer\'s progress, and a tap opens the problems module',
      (tester) async {
    final opened = <StudyModuleSettings>[];
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _subject,
        repository: _FakeTodayRepo(
          problemSets: [
            StudyProblemSet(
              id: 's1',
              title: 'Week 3',
              dueAt: DateTime(2026, 11, 12),
            ),
          ],
          problems: const [
            StudyProblem(id: 'p1', text: 'Solve one', setId: 's1'),
            StudyProblem(id: 'p2', text: 'Solve two', setId: 's1'),
          ],
          myWork: const {
            'p1': StudyProblemSolution(
              solverEmail: 'me@x.com',
              text: 'my working',
            ),
          },
        ),
        today: _tuesday,
        problemsModule: _problemsModule,
        onOpenModule: opened.add,
        cardsDue: () async => 0,
      ),
    );

    const line = 'Problem set Week 3 is due 12 Nov: 1 of 2 worked.';
    expect(find.text(line), findsOneWidget);

    await tester.tap(find.text(line));
    await tester.pumpAndSettle();
    expect(opened.map((m) => m.key), [StudyModuleKey.problems]);
  });

  testWidgets(
      'the problem-set line is not shown when the problems module is off',
      (tester) async {
    await _pump(
      tester,
      StudyTodayCard(
        tourId: 't1',
        subject: _subject,
        repository: _FakeTodayRepo(
          problemSets: [
            StudyProblemSet(
              id: 's1',
              title: 'Week 3',
              dueAt: DateTime(2026, 11, 12),
            ),
          ],
          problems: const [
            StudyProblem(id: 'p1', text: 'Solve one', setId: 's1'),
          ],
        ),
        today: _tuesday,
        onOpenModule: (_) {},
        cardsDue: () async => 0,
      ),
    );

    expect(find.textContaining('Problem set Week 3'), findsNothing);
  });
}
