import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/models/study_session_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_session_rules.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingSession _session({
  DateTime? startsAt,
  String by = 'ana@x.com',
  DateTime? timerStartsAt,
  int? timerSeconds,
  StudySessionRecap? recap,
}) =>
    ReadingSession(
      id: 's1',
      title: 'Chapters 1 to 3',
      startsAt: startsAt ?? DateTime(2030, 1, 1, 18),
      createdByEmail: by,
      timerStartsAt: timerStartsAt,
      timerSeconds: timerSeconds,
      recap: recap,
    );

void main() {
  final before = DateTime(2030, 1, 1, 17);
  final after = DateTime(2030, 1, 1, 19);

  group('when a session starts', () {
    test('it has not started before its start, and has from its start on', () {
      expect(sessionHasStarted(_session(), now: before), isFalse);
      expect(
          sessionHasStarted(_session(), now: DateTime(2030, 1, 1, 18)), isTrue);
      expect(sessionHasStarted(_session(), now: after), isTrue);
    });
  });

  group('the shared focus timer', () {
    test('with no timer, nothing is left', () {
      expect(focusTimeLeft(_session(), now: after), isNull);
    });

    test('it counts down from the shared start, so every phone agrees', () {
      final running = _session(
        timerStartsAt: DateTime(2030, 1, 1, 18),
        timerSeconds: 1500,
      );
      expect(
        focusTimeLeft(running, now: DateTime(2030, 1, 1, 18, 10)),
        const Duration(minutes: 15),
      );
    });

    test('after its end, nothing is left', () {
      final ended = _session(
        timerStartsAt: DateTime(2030, 1, 1, 18),
        timerSeconds: 60,
      );
      expect(focusTimeLeft(ended, now: after), Duration.zero);
    });
  });

  group('who may do what', () {
    test(
        'the creator or an admin writes the recap, once the session has started',
        () {
      expect(
        canWriteRecap(_session(),
            viewerEmail: 'ana@x.com', isAdmin: false, now: after),
        isTrue,
      );
      expect(
        canWriteRecap(_session(),
            viewerEmail: 'ana@x.com', isAdmin: false, now: before),
        isFalse,
      );
      expect(
        canWriteRecap(_session(),
            viewerEmail: 'ben@x.com', isAdmin: false, now: after),
        isFalse,
      );
      expect(
        canWriteRecap(_session(),
            viewerEmail: 'ben@x.com', isAdmin: true, now: after),
        isTrue,
      );
    });

    test('a member checks in once, and only after the session has started', () {
      const going = StudySessionRsvp(
        email: 'ben@x.com',
        response: StudySessionResponse.going,
      );
      final checked = StudySessionRsvp(
        email: 'ben@x.com',
        response: StudySessionResponse.going,
        checkedInAt: after,
      );
      expect(canCheckIn(_session(), answer: going, now: before), isFalse);
      expect(canCheckIn(_session(), answer: going, now: after), isTrue);
      expect(canCheckIn(_session(), answer: checked, now: after), isFalse);
      expect(canCheckIn(_session(), answer: null, now: after), isTrue);
    });

    test('the creator or an admin runs the timer', () {
      expect(canRunTimer(_session(), viewerEmail: 'ana@x.com', isAdmin: false),
          isTrue);
      expect(canRunTimer(_session(), viewerEmail: 'ben@x.com', isAdmin: false),
          isFalse);
      expect(canRunTimer(_session(), viewerEmail: 'ben@x.com', isAdmin: true),
          isTrue);
    });
  });

  group('the open questions', () {
    test('blank ones are dropped and the rest are trimmed', () {
      expect(
        cleanOpenQuestions(['  Why the train? ', '', '   ']),
        ['Why the train?'],
      );
    });

    test('at most ten, and each at most 300 characters', () {
      expect(openQuestionsProblem(List.generate(10, (i) => 'q$i')), isNull);
      expect(
        openQuestionsProblem(List.generate(11, (i) => 'q$i')),
        StudyRecapProblem.tooMany,
      );
      expect(openQuestionsProblem(['x' * 300]), isNull);
      expect(openQuestionsProblem(['x' * 301]), StudyRecapProblem.tooLong);
    });
  });

  group('the answers', () {
    test('they are counted by response, and the check-ins apart', () {
      final tally = tallySessionAnswers([
        StudySessionRsvp(
          email: 'a@x.com',
          response: StudySessionResponse.going,
          checkedInAt: after,
        ),
        const StudySessionRsvp(
            email: 'b@x.com', response: StudySessionResponse.going),
        const StudySessionRsvp(
            email: 'c@x.com', response: StudySessionResponse.maybe),
      ]);
      expect(tally.going, 2);
      expect(tally.maybe, 1);
      expect(tally.cannot, 0);
      expect(tally.checkedIn, 1);
    });
  });

  group('the meeting link', () {
    test('empty means none; anything else must be an https address with a host',
        () {
      expect(isSessionLinkValid(''), isTrue);
      expect(isSessionLinkValid('https://meet.example.com/room'), isTrue);
      expect(isSessionLinkValid('http://meet.example.com'), isFalse);
      expect(isSessionLinkValid('meet.example.com'), isFalse);
    });
  });

  group('the record', () {
    test('a stored recap reads back, and its blank questions are left out', () {
      final recap = StudySessionRecap.fromMap({
        'covered': ' Chapter 1 ',
        'openQuestions': ['Why?', '  ', 'How?'],
      });
      expect(recap, isNotNull);
      expect(recap!.covered, 'Chapter 1');
      expect(recap.openQuestions, ['Why?', 'How?']);
    });

    test('an answer needs a known response', () {
      expect(StudySessionRsvp.fromMap('a@x.com', {'response': 'yes'}), isNull);
      expect(
        StudySessionRsvp.fromMap('a@x.com', {'response': 'going'})!.response,
        StudySessionResponse.going,
      );
    });
  });
}
