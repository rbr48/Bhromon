import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_problem_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/study/study_member_deadlines_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// An admin's list of a problem set's members, with the date each one has for the set. A date an admin set for a
// member is shown as theirs; the others show the set's date. Only active members are listed.

class _FakeDeadlineRepo extends TourGroupRepository {
  _FakeDeadlineRepo({required this.deadlines, required this.members});

  final List<StudyMemberDeadline> deadlines;
  final List<TourMember> members;
  final List<String> calls = [];

  @override
  String get currentEmail => 'admin@x.com';

  @override
  Stream<List<StudyMemberDeadline>> watchMemberDeadlines(
    String tourId,
    String subjectId,
    String setId,
  ) =>
      Stream.value(deadlines);

  @override
  Stream<List<TourMember>> watchMembers(String tourId) => Stream.value(members);

  @override
  Future<void> setStudyMemberDeadline(
    String tourId,
    String subjectId,
    String setId,
    String email, {
    required DateTime dueAt,
  }) async {
    calls.add('set $email ${dueAt.year}-${dueAt.month}-${dueAt.day}');
  }

  @override
  Future<void> clearStudyMemberDeadline(
    String tourId,
    String subjectId,
    String setId,
    String email,
  ) async {
    calls.add('clear $email');
  }
}

final _set = StudyProblemSet(
  id: 'set1',
  title: 'Week 3',
  dueAt: DateTime(2026, 11, 12),
);

TourMember _member(String email, String name, TourMemberStatus status) =>
    TourMember(
      tourId: 't1',
      email: email,
      displayName: name,
      role: TourRole.member,
      status: status,
      joinedAt: DateTime(2026, 11, 1),
    );

Future<void> _open(WidgetTester tester, _FakeDeadlineRepo repo) async {
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
            onPressed: () => showStudyMemberDeadlinesSheet(
              context,
              repository: repo,
              tourId: 't1',
              subjectId: 's1',
              set: _set,
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

final _members = [
  _member('ana@x.com', 'Ana', TourMemberStatus.active),
  _member('ben@x.com', 'Ben', TourMemberStatus.active),
  _member('cy@x.com', 'Cy', TourMemberStatus.invited),
];

void main() {
  testWidgets(
      'each active member shows the date they have for the set: their own when one is set, the set\'s otherwise',
      (tester) async {
    await _open(
      tester,
      _FakeDeadlineRepo(
        deadlines: [
          StudyMemberDeadline(
            email: 'ana@x.com',
            dueAt: DateTime(2026, 11, 18),
            setByEmail: 'admin@x.com',
          ),
        ],
        members: _members,
      ),
    );

    expect(find.text('Their date: 18 Nov 2026'), findsOneWidget);
    expect(find.text('Set date: 12 Nov 2026'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    // An invited member is not yet in the group, so has no date to keep.
    expect(find.text('Cy'), findsNothing);
  });

  testWidgets(
      'taking away a member\'s own date uses the set\'s date again, and says so',
      (tester) async {
    final repo = _FakeDeadlineRepo(
      deadlines: [
        StudyMemberDeadline(
          email: 'ana@x.com',
          dueAt: DateTime(2026, 11, 18),
          setByEmail: 'admin@x.com',
        ),
      ],
      members: _members,
    );
    await _open(tester, repo);

    // Only a member with a date of their own has the button that takes it away.
    expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();

    expect(repo.calls, ['clear ana@x.com']);
    expect(
        find.text('This member uses the set\'s date again.'), findsOneWidget);
  });

  testWidgets('a date picked for a member is saved for that member only',
      (tester) async {
    final repo = _FakeDeadlineRepo(deadlines: const [], members: _members);
    await _open(tester, repo);

    final benRow = find.widgetWithText(ListTile, 'Ben');
    await tester.tap(find.descendant(
        of: benRow, matching: find.byIcon(Icons.event_outlined)));
    await tester.pumpAndSettle();
    // The picker opens on the set's date, so accepting it saves that day for Ben.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['set ben@x.com 2026-11-12']);
    expect(find.text('Date saved for this member.'), findsOneWidget);
  });
}
