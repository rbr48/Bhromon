import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_challenge_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_subject_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_challenge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// One subject's weekly challenge: this week's task, who joined, and the member's own progress. Members join and leave
// while the week runs, and an admin sets the week's challenge.

class _FakeChallengeRepo extends TourGroupRepository {
  _FakeChallengeRepo({
    this.role,
    this.challenge,
    this.joins = const {},
    this.done = 0,
  });

  final TourRole? role;
  final StudyChallenge? challenge;
  final Set<String> joins;
  final int done;
  final List<String> calls = [];

  @override
  String get currentEmail => 'me@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

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
  Future<void> joinStudyChallenge(
    String tourId,
    String subjectId,
    String weekKey,
  ) async {
    calls.add('join $weekKey');
  }

  @override
  Future<void> leaveStudyChallenge(
    String tourId,
    String subjectId,
    String weekKey,
  ) async {
    calls.add('leave $weekKey');
  }

  @override
  Future<void> setStudyChallenge(
    String tourId,
    String subjectId,
    StudyChallenge challenge,
  ) async {
    calls.add(
        'set ${challenge.weekKey} ${challenge.kind.name} ${challenge.target}');
  }
}

const _subject = StudySubject(id: 's1', title: 'Statistics 101');

const _module = StudyModuleSettings(
  key: StudyModuleKey.challenges,
  enabled: true,
  name: 'Weekly challenge',
  postPolicy: StudyPostPolicy.admins,
);

/// The Tuesday of the week that starts on 2026-11-09.
final _tuesday = DateTime(2026, 11, 10, 9);

const _problemsChallenge = StudyChallenge(
  weekKey: '2026-11-09',
  kind: ChallengeKind.problems,
  target: 5,
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

StudyChallengeScreen _screen(_FakeChallengeRepo repo) => StudyChallengeScreen(
      tourId: 't1',
      subject: _subject,
      settings: _module,
      repository: repo,
      today: _tuesday,
      cardsReviewed: (from, to) async => 0,
    );

void main() {
  testWidgets(
      'with no challenge set, a member is told so and sees no set button',
      (tester) async {
    final repo = _FakeChallengeRepo(role: TourRole.member);
    await _pump(tester, _screen(repo));

    expect(
        find.text('No challenge has been set for this week.'), findsOneWidget);
    expect(find.text('Set the challenge for this week'), findsNothing);
  });

  testWidgets(
      'a member who has not joined sees the task and joins it, and then sees the join count',
      (tester) async {
    final repo = _FakeChallengeRepo(
      role: TourRole.member,
      challenge: _problemsChallenge,
    );
    await _pump(tester, _screen(repo));

    expect(find.text('Work out 5 problems this week.'), findsOneWidget);
    expect(find.text('Join to track your work on this challenge.'),
        findsOneWidget);
    expect(find.text('0 members have joined.'), findsOneWidget);

    await tester.tap(find.text('Join this challenge'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['join 2026-11-09']);
    expect(find.text('You joined the challenge.'), findsOneWidget);
    expect(find.text('Leave this challenge'), findsOneWidget);
    expect(find.text('1 members have joined.'), findsOneWidget);
  });

  testWidgets(
      'a member who has joined sees their own progress, and no one else\'s',
      (tester) async {
    final repo = _FakeChallengeRepo(
      role: TourRole.member,
      challenge: _problemsChallenge,
      joins: const {'me@x.com', 'b@x.com'},
      done: 3,
    );
    await _pump(tester, _screen(repo));

    expect(find.text('3 of 5 done.'), findsOneWidget);
    expect(find.text('2 members have joined.'), findsOneWidget);
    expect(find.text('Leave this challenge'), findsOneWidget);
    expect(find.text('Join this challenge'), findsNothing);
  });

  testWidgets('an admin sets the week\'s challenge, and it is saved',
      (tester) async {
    final repo = _FakeChallengeRepo(role: TourRole.admin);
    await _pump(tester, _screen(repo));

    await tester.tap(find.text('Set the challenge for this week'));
    await tester.pumpAndSettle();

    expect(find.text('The challenge for this week'), findsOneWidget);
    await tester.tap(find.text('Save challenge'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['set 2026-11-09 problems 5']);
    expect(find.text('Challenge saved.'), findsOneWidget);
  });
}
