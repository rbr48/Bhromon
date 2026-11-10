import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_finding_checks_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The checks sheet an admin opens on a finding: who checked and what they said, and a withdraw that asks first and
// then takes the check back for its maker.

class _FakeChecksRepo extends TourGroupRepository {
  _FakeChecksRepo(this.checks);

  final List<StudyFindingCheck> checks;
  final List<String> withdrawn = [];

  @override
  Future<List<StudyFindingCheck>> loadFindingChecks(
    String tourId,
    String subjectId,
    String findingId,
  ) async =>
      List.of(checks);

  @override
  Future<void> withdrawOtherFindingCheck(
    String tourId,
    String subjectId,
    String findingId,
    StudyFindingCheck check,
  ) async {
    withdrawn.add(check.email);
    checks.removeWhere((c) => c.email == check.email);
  }
}

Future<void> _pump(WidgetTester tester, TourGroupRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('bn')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: StudyFindingChecksSheet(
        repository: repo,
        tourId: 'T',
        subjectId: 'phy',
        findingId: 'f1',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'the checks show who checked, what they said, and the note of a challenge',
      (tester) async {
    await _pump(
      tester,
      _FakeChecksRepo([
        StudyFindingCheck(email: 'a@x.com', verdict: FindingVerdict.confirm),
        StudyFindingCheck(
          email: 'b@x.com',
          verdict: FindingVerdict.challenge,
          note: 'The sample was too warm.',
        ),
      ]),
    );

    expect(find.text('a@x.com confirmed it'), findsOneWidget);
    expect(find.text('b@x.com challenged it'), findsOneWidget);
    expect(find.text('The sample was too warm.'), findsOneWidget);
    expect(find.byIcon(Icons.undo_rounded), findsNWidgets(2));
  });

  testWidgets(
      'withdrawing asks first, then takes the check back and shows the list again',
      (tester) async {
    final repo = _FakeChecksRepo([
      StudyFindingCheck(email: 'a@x.com', verdict: FindingVerdict.confirm),
      StudyFindingCheck(email: 'b@x.com', verdict: FindingVerdict.confirm),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.undo_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Withdraw this check?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.withdrawn, isEmpty);

    await tester.tap(find.byIcon(Icons.undo_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repo.withdrawn, ['a@x.com']);
    expect(find.text('a@x.com confirmed it'), findsNothing);
    expect(find.text('b@x.com confirmed it'), findsOneWidget);
  });

  testWidgets('a finding no one has checked says so', (tester) async {
    await _pump(tester, _FakeChecksRepo(const []));

    expect(find.text('No one has checked this yet.'), findsOneWidget);
    expect(find.byIcon(Icons.undo_rounded), findsNothing);
  });
}
