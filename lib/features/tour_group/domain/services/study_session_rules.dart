import '../models/study_models.dart';
import '../models/study_session_models.dart';

// Pure rules for a reading session: when it starts, the shared focus timer, who may write the recap or run
// the timer, the open questions a recap carries, and the answers a session has.

/// Whether the session has started by [now].
bool sessionHasStarted(ReadingSession session, {required DateTime now}) =>
    !now.isBefore(session.startsAt);

/// The time left on the shared focus timer at [now], or null when no timer is running. Every phone counts
/// down from the same start, so everyone sees the same time.
Duration? focusTimeLeft(ReadingSession session, {required DateTime now}) {
  final started = session.timerStartsAt;
  final seconds = session.timerSeconds;
  if (started == null || seconds == null) return null;
  final left = started.add(Duration(seconds: seconds)).difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// Whether a member may write the recap: the session's creator or an admin, once it has started.
bool canWriteRecap(
  ReadingSession session, {
  required String viewerEmail,
  required bool isAdmin,
  required DateTime now,
}) =>
    (isAdmin || session.createdByEmail == viewerEmail) &&
    sessionHasStarted(session, now: now);

/// Whether a member may check in: the session has started, and they have not checked in yet.
bool canCheckIn(
  ReadingSession session, {
  required StudySessionRsvp? answer,
  required DateTime now,
}) =>
    sessionHasStarted(session, now: now) && !(answer?.isCheckedIn ?? false);

/// Whether a member may start or stop the shared timer: the session's creator or an admin.
bool canRunTimer(
  ReadingSession session, {
  required String viewerEmail,
  required bool isAdmin,
}) =>
    isAdmin || session.createdByEmail == viewerEmail;

/// The open questions with their spaces trimmed and the blank ones dropped.
List<String> cleanOpenQuestions(Iterable<String> raw) => [
      for (final question in raw)
        if (question.trim().isNotEmpty) question.trim(),
    ];

/// What is wrong with a recap's open questions.
enum StudyRecapProblem { tooMany, tooLong }

/// The problem with the open questions of a recap, or null when they are fine: at most ten.
StudyRecapProblem? openQuestionsProblem(List<String> questions) {
  if (questions.length > StudySessionLimits.openQuestionMax) {
    return StudyRecapProblem.tooMany;
  }
  return null;
}

/// How many members answered each way, and how many checked in.
class StudySessionTally {
  const StudySessionTally({
    required this.going,
    required this.maybe,
    required this.cannot,
    required this.checkedIn,
  });

  final int going;
  final int maybe;
  final int cannot;
  final int checkedIn;
}

/// Counts the answers to a session.
StudySessionTally tallySessionAnswers(Iterable<StudySessionRsvp> answers) {
  var going = 0;
  var maybe = 0;
  var cannot = 0;
  var checkedIn = 0;
  for (final answer in answers) {
    switch (answer.response) {
      case StudySessionResponse.going:
        going++;
      case StudySessionResponse.maybe:
        maybe++;
      case StudySessionResponse.cannot:
        cannot++;
    }
    if (answer.isCheckedIn) checkedIn++;
  }
  return StudySessionTally(
    going: going,
    maybe: maybe,
    cannot: cannot,
    checkedIn: checkedIn,
  );
}

/// Whether a meeting link is fine: empty (there is none), or an https address with a host.
bool isSessionLinkValid(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return true;
  final uri = Uri.tryParse(text);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}
