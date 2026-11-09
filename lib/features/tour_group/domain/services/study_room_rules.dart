// The study room and the group calendar for a reading session, as pure rules. A session opens a voice room
// on VoiceRoomService for its meeting. The room opens when the session starts, holds six people, and closes
// 24 hours after the session is taken to end. The group calendar lists the sessions whose room has not
// closed yet.

import '../models/study_models.dart';
import '../models/study_session_models.dart';
import 'study_session_rules.dart';

/// When a session is taken to end: its start plus [StudySessionLimits.assumedLength], or the end of its
/// focus timer when the timer runs later.
DateTime sessionEndsAt(ReadingSession session) {
  final assumed = session.startsAt.add(StudySessionLimits.assumedLength);
  final timerStart = session.timerStartsAt;
  final timerSeconds = session.timerSeconds;
  if (timerStart == null || timerSeconds == null) return assumed;
  final timerEnd = timerStart.add(Duration(seconds: timerSeconds));
  return timerEnd.isAfter(assumed) ? timerEnd : assumed;
}

/// Whether the study room has closed: [StudySessionLimits.roomGrace] after the session is taken to end.
bool studyRoomClosed(ReadingSession session, {required DateTime now}) =>
    !now.isBefore(sessionEndsAt(session).add(StudySessionLimits.roomGrace));

/// Whether the study room is open: from the session's start until it closes.
bool studyRoomOpen(ReadingSession session, {required DateTime now}) =>
    sessionHasStarted(session, now: now) && !studyRoomClosed(session, now: now);

/// The voice channel that holds a session's study room. Its seats and signals sit under the tour's channels,
/// which the rules check by membership alone.
String studyRoomChannelId(String sessionId) => 'study_$sessionId';

/// The sessions the group calendar lists: those whose study room has not closed, soonest first.
List<ReadingSession> calendarSessions(
  List<ReadingSession> sessions, {
  required DateTime now,
}) {
  final listed = [
    for (final session in sessions)
      if (!studyRoomClosed(session, now: now)) session,
  ];
  listed.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return listed;
}

/// The days the group calendar marks for study sessions: the day of each session it lists. A day is a date at
/// midnight, as the calendar's own days are.
Set<DateTime> calendarSessionDays(
  List<ReadingSession> sessions, {
  required DateTime now,
}) =>
    {
      for (final session in calendarSessions(sessions, now: now))
        DateTime(session.startsAt.year, session.startsAt.month,
            session.startsAt.day),
    };
