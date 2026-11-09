import 'package:bhromon/features/tour_group/domain/models/study_models.dart';
import 'package:bhromon/features/tour_group/domain/services/study_room_rules.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingSession _session({
  String id = 's1',
  DateTime? startsAt,
  DateTime? timerStartsAt,
  int? timerSeconds,
}) =>
    ReadingSession(
      id: id,
      title: 'Chapters 1 to 3',
      startsAt: startsAt ?? DateTime(2030, 1, 1, 18),
      timerStartsAt: timerStartsAt,
      timerSeconds: timerSeconds,
    );

void main() {
  // The session starts at 18:00, so it is taken to end at 20:00, and its room closes the next evening.
  final start = DateTime(2030, 1, 1, 18);
  final assumedEnd = DateTime(2030, 1, 1, 20);
  final roomCloses = DateTime(2030, 1, 2, 20);

  group('when a session is taken to end', () {
    test('two hours after its start, with no focus timer', () {
      expect(sessionEndsAt(_session()), assumedEnd);
    });

    test('at the end of its focus timer, when the timer runs later', () {
      final long = _session(
        timerStartsAt: DateTime(2030, 1, 1, 19, 30),
        timerSeconds: 3600,
      );
      expect(sessionEndsAt(long), DateTime(2030, 1, 1, 20, 30));
    });

    test('a shorter focus timer does not shorten it', () {
      final short = _session(timerStartsAt: start, timerSeconds: 600);
      expect(sessionEndsAt(short), assumedEnd);
    });
  });

  group('the study room', () {
    test('is open from the start of the session, not before', () {
      expect(
        studyRoomOpen(_session(), now: DateTime(2030, 1, 1, 17, 59)),
        isFalse,
      );
      expect(studyRoomOpen(_session(), now: start), isTrue);
    });

    test('closes 24 hours after the session is taken to end', () {
      final justBefore = roomCloses.subtract(const Duration(seconds: 1));
      expect(studyRoomOpen(_session(), now: justBefore), isTrue);
      expect(studyRoomClosed(_session(), now: justBefore), isFalse);
      expect(studyRoomOpen(_session(), now: roomCloses), isFalse);
      expect(studyRoomClosed(_session(), now: roomCloses), isTrue);
    });

    test('has a channel named after its session', () {
      expect(studyRoomChannelId('s1'), 'study_s1');
    });
  });

  group('the group calendar', () {
    test('lists the sessions whose room has not closed, soonest first', () {
      final later = _session(id: 'later', startsAt: DateTime(2030, 2, 1, 18));
      final sooner =
          _session(id: 'sooner', startsAt: DateTime(2030, 1, 15, 18));
      final closed =
          _session(id: 'closed', startsAt: DateTime(2029, 12, 1, 18));
      final listed = calendarSessions(
        [later, closed, sooner],
        now: DateTime(2030, 1, 1, 12),
      );
      expect([for (final session in listed) session.id], ['sooner', 'later']);
    });
  });

  test(
      'the calendar marks the day of each session it lists, and no day of a closed one',
      () {
    final now = DateTime(2030, 1, 10, 12);
    final open = _session(id: 'open', startsAt: DateTime(2030, 1, 12, 18));
    final closed = _session(id: 'closed', startsAt: DateTime(2030, 1, 2, 18));

    final days = calendarSessionDays([open, closed], now: now);

    expect(days, {DateTime(2030, 1, 12)});
  });
}
