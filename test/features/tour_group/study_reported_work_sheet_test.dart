import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_reported_work_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// An admin's list of the reported workings across a subject's problems, oldest report first. An admin restores a
// working to the group, or removes it after confirming. Both leave the list at once.

class _FakeWorkRepo extends TourGroupRepository {
  _FakeWorkRepo({required this.reported});

  /// The reported workings, by problem id. A working is taken out when an admin restores or removes it.
  final Map<String, List<StudyProblemSolution>> reported;
  final List<String> calls = [];

  @override
  String get currentEmail => 'admin@x.com';

  @override
  Stream<List<StudyProblem>> watchStudyProblems(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(_problems);

  @override
  Future<Map<String, List<StudyProblemSolution>>> loadReportedWork(
    String tourId,
    String subjectId,
    List<String> problemIds,
  ) async =>
      {
        for (final entry in reported.entries)
          if (problemIds.contains(entry.key) && entry.value.isNotEmpty)
            entry.key: List.of(entry.value),
      };

  @override
  Future<void> restoreStudyWork(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
  ) async {
    calls.add('restore $problemId $solverEmail');
    reported[problemId]?.removeWhere((w) => w.solverEmail == solverEmail);
  }

  @override
  Future<void> deleteStudyWork(
    String tourId,
    String subjectId,
    String problemId,
    String solverEmail,
  ) async {
    calls.add('delete $problemId $solverEmail');
    reported[problemId]?.removeWhere((w) => w.solverEmail == solverEmail);
  }
}

final _problems = [
  const StudyProblem(id: 'p1', text: 'Find the mean', title: 'Mean'),
  const StudyProblem(id: 'p2', text: 'Find the median'),
];

/// Ben reported his working on 1 November and Ana hers on 2 November, so Ben's report is the older and comes first.
Map<String, List<StudyProblemSolution>> _reported() => {
      'p1': [
        StudyProblemSolution(
          solverEmail: 'ana@x.com',
          text: 'Add them and divide',
          reportedAt: DateTime(2026, 11, 2),
        ),
      ],
      'p2': [
        StudyProblemSolution(
          solverEmail: 'ben@x.com',
          text: 'Sort them first',
          reportedAt: DateTime(2026, 11, 1),
        ),
      ],
    };

Future<void> _open(WidgetTester tester, _FakeWorkRepo repo) async {
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
            onPressed: () => showStudyReportedWorkSheet(
              context,
              repository: repo,
              tourId: 't1',
              subjectId: 's1',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  // The localizations load asynchronously, so the page is built only after the frames settle.
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The card of one solver's working in the list.
Finder _cardOf(String email) =>
    find.ancestor(of: find.text('By $email'), matching: find.byType(Card));

void main() {
  testWidgets(
      'lists the reported workings with their problems, the oldest report first',
      (tester) async {
    await _open(tester, _FakeWorkRepo(reported: _reported()));

    expect(find.text('Mean'), findsOneWidget);
    expect(find.text('Find the median'), findsOneWidget);
    expect(find.text('By ana@x.com'), findsOneWidget);
    expect(find.text('By ben@x.com'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('By ben@x.com')).dy,
      lessThan(tester.getTopLeft(find.text('By ana@x.com')).dy),
    );
  });

  testWidgets('an admin restores a reported working, and it leaves the list',
      (tester) async {
    final repo = _FakeWorkRepo(reported: _reported());
    await _open(tester, repo);

    await tester.tap(find.descendant(
        of: _cardOf('ana@x.com'), matching: find.text('Restore')));
    await tester.pumpAndSettle();

    expect(repo.calls, ['restore p1 ana@x.com']);
    expect(find.text('By ana@x.com'), findsNothing);
    expect(find.text('By ben@x.com'), findsOneWidget);
    expect(find.text('Restored.'), findsOneWidget);
  });

  testWidgets(
      'removing a reported working asks first, and removes it only once confirmed',
      (tester) async {
    final repo = _FakeWorkRepo(reported: _reported());
    await _open(tester, repo);

    // Declining the confirmation keeps the working.
    await tester.tap(find.descendant(
        of: _cardOf('ben@x.com'), matching: find.text('Remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(find.text('By ben@x.com'), findsOneWidget);

    // Confirming removes it, and it leaves the list.
    await tester.tap(find.descendant(
        of: _cardOf('ben@x.com'), matching: find.text('Remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Remove')));
    await tester.pumpAndSettle();

    expect(repo.calls, ['delete p2 ben@x.com']);
    expect(find.text('By ben@x.com'), findsNothing);
    expect(find.text('Post removed.'), findsOneWidget);
  });

  testWidgets('with no working reported, the sheet says so', (tester) async {
    await _open(tester, _FakeWorkRepo(reported: const {}));

    expect(find.text('No working has been reported.'), findsOneWidget);
  });
}
