import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_session_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/pages/study_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// One reading session: the answers, the check-in, and the recap. A fake repository records each change. The
// rules these screens follow are tested on the emulator in functions/tests/study_sessions_rules.test.js.

class _FakeSessionRepo extends TourGroupRepository {
  _FakeSessionRepo({this.session, this.role});

  final ReadingSession? session;
  final List<StudySessionRsvp> answers = const [];
  final TourRole? role;
  final List<String> calls = [];

  @override
  String get currentEmail => 'ben@x.com';

  @override
  Future<TourRole?> myRole(String tourId) async => role;

  @override
  Stream<List<ReadingSession>> watchReadingSessions(String tourId) {
    final current = session;
    return Stream.value([if (current != null) current]);
  }

  @override
  Stream<List<StudySessionRsvp>> watchSessionRsvps(
    String tourId,
    String sessionId,
  ) =>
      Stream.value(answers);

  @override
  Future<void> setSessionAnswer(
    String tourId,
    String sessionId,
    StudySessionResponse response,
  ) async {
    calls.add('answer ${response.name}');
  }

  @override
  Future<void> checkInToSession(String tourId, String sessionId) async {
    calls.add('checkin');
  }

  @override
  Future<void> saveSessionRecap(
    String tourId,
    ReadingSession session,
    StudySessionRecap recap, {
    required List<String> newQuestions,
  }) async {
    calls.add('recap ${newQuestions.length}');
  }
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  // A new key gives each page its own app. Without it, a second page in the same test keeps the first page's
  // route, because the navigator only reads `home` when it is first built.
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
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

/// Taps a control after scrolling it into view.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

final _future = ReadingSession(
  id: 's1',
  title: 'Chapters 1 to 3',
  startsAt: DateTime(2099, 1, 1, 18),
  createdByEmail: 'ana@x.com',
  bookId: 'b1',
  agenda: 'Read chapter one and note the train scene.',
);

final _started = ReadingSession(
  id: 's1',
  title: 'Chapters 1 to 3',
  startsAt: DateTime(2000, 1, 1, 18),
  createdByEmail: 'ben@x.com',
  bookId: 'b1',
);

void main() {
  group('a reading session', () {
    testWidgets('a member sees the agenda and answers the session',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final repo = _FakeSessionRepo(session: _future, role: TourRole.member);
      await _pump(
        tester,
        StudySessionScreen(tourId: 'T', session: _future, repository: repo),
      );

      expect(find.text('Read chapter one and note the train scene.'),
          findsOneWidget);
      expect(find.text('The study room opens when the session starts.'),
          findsOneWidget);
      await _tap(tester, find.text('Going (0)'));

      expect(repo.calls, ['answer going']);
    });

    testWidgets('check-in is offered once the session has started, not before',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final early = _FakeSessionRepo(session: _future, role: TourRole.member);
      await _pump(
        tester,
        StudySessionScreen(tourId: 'T', session: _future, repository: early),
      );
      expect(find.text('The session has not started yet.'), findsOneWidget);
      expect(find.text('The study room opens when the session starts.'),
          findsOneWidget);
      expect(find.text('I am here'), findsNothing);

      final late = _FakeSessionRepo(session: _started, role: TourRole.member);
      await _pump(
        tester,
        StudySessionScreen(tourId: 'T', session: _started, repository: late),
      );
      expect(find.text('The study room has closed.'), findsOneWidget);
      await _tap(tester, find.text('I am here'));

      expect(late.calls, ['checkin']);
    });

    testWidgets('the creator writes the recap, and each new question is saved',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final repo = _FakeSessionRepo(session: _started, role: TourRole.member);
      await _pump(
        tester,
        StudySessionScreen(tourId: 'T', session: _started, repository: repo),
      );

      await _tap(tester, find.text('Write the recap'));
      // The dialog's fields: what was covered, what was hard, and the open questions.
      await tester.enterText(
          find.byType(TextField).at(2), 'Why the train?\nWho is Vronsky?');
      await _tap(tester, find.text('Save'));

      expect(repo.calls, ['recap 2']);
    });
  });
}
