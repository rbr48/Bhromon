import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_finding_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_findings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The shared findings of a subject. A member sees how a finding was checked and how many members
// confirmed or challenged it, confirms it, and takes their own check back. The fake repository
// records the checks it is asked to make; the real one writes the check and its count together.

class _FakeFindingsRepo extends TourGroupRepository {
  _FakeFindingsRepo({
    required this.role,
    required this.findings,
    this.myChecks = const {},
  });

  final TourRole? role;
  final List<StudyFinding> findings;
  final Map<String, StudyFindingCheck> myChecks;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

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
      {
        for (final id in findingIds)
          if (myChecks[id] != null) id: myChecks[id]!,
      };

  @override
  Future<void> checkStudyFinding(
    String tourId,
    String subjectId,
    String findingId, {
    required FindingVerdict verdict,
    String note = '',
  }) async {
    calls.add('${verdict.name} $findingId ${note.isEmpty ? '-' : note}');
  }

  @override
  Future<void> withdrawStudyFindingCheck(
    String tourId,
    String subjectId,
    String findingId,
    FindingVerdict verdict,
  ) async {
    calls.add('withdraw $findingId ${verdict.name}');
  }
}

const _subject = StudySubject(id: 's1', title: 'Statistics 101');

const _module = StudyModuleSettings(
  key: StudyModuleKey.findings,
  enabled: true,
  name: 'Shared findings',
  postPolicy: StudyPostPolicy.members,
);

/// A finding by another member, checked by two members and challenged by one.
final _others = StudyFinding(
  id: 'f1',
  text: 'The sample gives 4.2 at 25 degrees.',
  method: 'Repeated three times on the bench.',
  createdByEmail: 'b@x.com',
  createdAt: DateTime(2026, 11, 1, 10),
  confirmCount: 2,
  challengeCount: 1,
);

/// A finding by the signed-in member.
final _mine = StudyFinding(
  id: 'f2',
  text: 'The second column is the one to use.',
  method: 'Checked against the answer key.',
  createdByEmail: 'me@x.com',
  createdAt: DateTime(2026, 11, 2, 10),
);

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

StudyFindingsScreen _screen(_FakeFindingsRepo repo) => StudyFindingsScreen(
      tourId: 't1',
      subject: _subject,
      settings: _module,
      repository: repo,
    );

void main() {
  testWidgets(
      'a member sees how a finding was checked and its counts, and confirms it',
      (tester) async {
    final repo = _FakeFindingsRepo(role: TourRole.member, findings: [_others]);
    await _pump(tester, _screen(repo));

    expect(find.textContaining('Repeated three times'), findsOneWidget);
    expect(find.text('Confirmed by 2 · challenged by 1'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['confirm f1 -']);
    expect(find.text('You confirmed this'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('a member gets no check buttons on their own finding',
      (tester) async {
    final repo = _FakeFindingsRepo(role: TourRole.member, findings: [_mine]);
    await _pump(tester, _screen(repo));

    expect(
        find.textContaining('Checked against the answer key'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Challenge'), findsNothing);
  });

  testWidgets('a member takes their own check back, and can check again',
      (tester) async {
    final repo = _FakeFindingsRepo(
      role: TourRole.member,
      findings: [_others],
      myChecks: {
        'f1': const StudyFindingCheck(
          email: 'me@x.com',
          verdict: FindingVerdict.challenge,
          note: 'Old key',
        ),
      },
    );
    await _pump(tester, _screen(repo));

    expect(find.text('You challenged this'), findsOneWidget);

    await tester.tap(find.text('Withdraw my check'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['withdraw f1 challenge']);
    expect(find.text('You challenged this'), findsNothing);
    expect(find.text('Challenge'), findsOneWidget);
  });
}
