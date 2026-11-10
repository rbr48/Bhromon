import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_assignment_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_assignments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// The assignments screen: what a member sees, the order to work through it, marking one finished, the add button
// under each post policy, and an admin showing a waiting one.

class _FakeAssignmentRepo extends TourGroupRepository {
  _FakeAssignmentRepo({
    this.assignments = const [],
    this.doneIds = const {},
    this.role,
  });

  final List<StudyAssignment> assignments;
  final Set<String> doneIds;
  final TourRole? role;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<StudyAssignment>> watchStudyAssignments(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(assignments);

  @override
  Stream<Set<String>> watchMyFinishedAssignments(
    String tourId,
    String subjectId,
  ) =>
      Stream.value(doneIds);

  @override
  Future<void> setMyAssignmentFinished(
    String tourId,
    String subjectId,
    String assignmentId, {
    required bool finished,
  }) async {
    calls.add('finish $assignmentId $finished');
  }

  @override
  Future<void> setStudyAssignmentShown(
    String tourId,
    String subjectId,
    String assignmentId, {
    required bool shown,
  }) async {
    calls.add('show $assignmentId $shown');
  }
}

const _physics = StudySubject(
  id: 'phy',
  title: 'Physics 101',
  createdByEmail: 'admin@x.com',
);

StudyModuleSettings _module(
        {StudyPostPolicy policy = StudyPostPolicy.members}) =>
    StudyModuleSettings(
      key: StudyModuleKey.assignments,
      enabled: true,
      name: 'Assignments',
      postPolicy: policy,
    );

final _today = DateTime.now();
final _tomorrow = DateTime(_today.year, _today.month, _today.day + 1);
final _inTwoWeeks = DateTime(_today.year, _today.month, _today.day + 14);
final _yesterday = DateTime(_today.year, _today.month, _today.day - 1);

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

void main() {
  final lab1 = StudyAssignment(
    id: 'lab1',
    title: 'Lab report 1',
    dueAt: _tomorrow,
    createdByEmail: 'admin@x.com',
    createdAt: DateTime(2026, 11, 1),
  );
  final lab2 = StudyAssignment(
    id: 'lab2',
    title: 'Lab report 2',
    dueAt: _inTwoWeeks,
    createdByEmail: 'me@x.com',
    createdAt: DateTime(2026, 11, 2),
  );
  final late = StudyAssignment(
    id: 'late',
    title: 'Essay',
    dueAt: _yesterday,
    createdByEmail: 'admin@x.com',
    createdAt: DateTime(2026, 10, 20),
  );
  final waiting = StudyAssignment(
    id: 'wait',
    title: 'Draft proposal',
    shown: false,
    createdByEmail: 'me@x.com',
    createdAt: DateTime(2026, 11, 3),
  );
  final othersWaiting = StudyAssignment(
    id: 'others',
    title: 'Someone else\'s draft',
    shown: false,
    createdByEmail: 'other@x.com',
    createdAt: DateTime(2026, 11, 4),
  );

  testWidgets(
      'a member sees the shown ones and their own waiting one, not others\' waiting ones',
      (tester) async {
    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(),
        repository: _FakeAssignmentRepo(
          assignments: [lab1, lab2, waiting, othersWaiting],
        ),
      ),
    );

    expect(find.text('Lab report 1'), findsOneWidget);
    expect(find.text('Lab report 2'), findsOneWidget);
    expect(find.text('Draft proposal'), findsOneWidget);
    expect(find.text('Someone else\'s draft'), findsNothing);
  });

  testWidgets('the list puts the unfinished ones first, nearest due day first',
      (tester) async {
    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(),
        repository: _FakeAssignmentRepo(
          assignments: [lab2, lab1, late],
          doneIds: const {'late'},
        ),
      ),
    );

    final lab1Top = tester.getTopLeft(find.text('Lab report 1')).dy;
    final lab2Top = tester.getTopLeft(find.text('Lab report 2')).dy;
    final lateTop = tester.getTopLeft(find.text('Essay')).dy;
    expect(lab1Top, lessThan(lab2Top));
    expect(lab2Top, lessThan(lateTop));
  });

  testWidgets(
      'the progress line counts the finished ones, and the checkbox marks one finished',
      (tester) async {
    final repo = _FakeAssignmentRepo(
      assignments: [lab1, lab2],
      doneIds: const {'lab2'},
    );
    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(),
        repository: repo,
      ),
    );

    expect(find.text('1 of 2 done'), findsOneWidget);
    // The first checkbox is the first card in order, Lab report 1, which is not finished yet.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(repo.calls, ['finish lab1 true']);
  });

  testWidgets(
      'a passed due day reads as overdue, and a day that is near reads as due soon',
      (tester) async {
    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(),
        repository: _FakeAssignmentRepo(assignments: [late, lab1]),
      ),
    );

    expect(find.textContaining('Overdue since'), findsOneWidget);
    expect(find.textContaining('Due soon:'), findsOneWidget);
  });

  testWidgets(
      'the add button shows for a member under the members policy, and not under the admins policy',
      (tester) async {
    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(),
        repository: _FakeAssignmentRepo(),
      ),
    );
    expect(find.text('Add an assignment'), findsOneWidget);
    expect(find.text('No assignments yet.'), findsOneWidget);

    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(policy: StudyPostPolicy.admins),
        repository: _FakeAssignmentRepo(),
      ),
    );
    expect(find.text('Add an assignment'), findsNothing);
  });

  testWidgets('an admin shows a waiting assignment from its menu',
      (tester) async {
    final repo = _FakeAssignmentRepo(
      assignments: [waiting],
      role: TourRole.admin,
    );
    await _pump(
      tester,
      StudyAssignmentsScreen(
        tourId: 'T',
        subject: _physics,
        settings: _module(),
        repository: repo,
      ),
    );

    expect(find.text('Waiting for an admin'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show to members'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['show wait true']);
  });
}
