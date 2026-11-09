// The parts of a reading session that Phase 4 adds: a member's answer (going, maybe or cannot) and check-in,
// the recap whose open questions become threads, and the limits the rules check. The session itself is in
// study_models.dart. Answers live under tours/{id}/reading_sessions/{id}/rsvps/{email}.

/// The limits of a session's text and its timer, as firestore.rules checks them.
class StudySessionLimits {
  const StudySessionLimits._();

  static const int agendaMax = 500;
  static const int linkMax = 2000;
  static const int recapTextMax = 1000;
  static const int openQuestionMax = 10;
  static const int openQuestionLength = 300;
  static const int threadTitleMax = 120;
  static const int threadBodyMax = 2000;
  static const int timerMinSeconds = 60;
  static const int timerMaxSeconds = 14400;

  /// The focus timer a session starts with: 25 minutes.
  static const int focusSeconds = 25 * 60;
}

/// A member's answer to a session. Stored by name.
enum StudySessionResponse {
  going,
  maybe,
  cannot;

  static StudySessionResponse? fromName(Object? raw) {
    for (final response in StudySessionResponse.values) {
      if (response.name == raw) return response;
    }
    return null;
  }
}

/// What the recap says about a session that has started: what was covered, what was hard, and the questions
/// still open. Each open question becomes a thread on the session's book.
class StudySessionRecap {
  const StudySessionRecap({
    this.covered = '',
    this.hard = '',
    this.openQuestions = const [],
  });

  final String covered;
  final String hard;
  final List<String> openQuestions;

  bool get isEmpty => covered.isEmpty && hard.isEmpty && openQuestions.isEmpty;

  /// The fields written for the recap. An empty part is stored as null.
  Map<String, dynamic> toFields() => {
        'covered': covered.isEmpty ? null : covered,
        'hard': hard.isEmpty ? null : hard,
        'openQuestions': openQuestions.isEmpty ? null : openQuestions,
      };

  /// Reads a stored recap. Returns null when there is none. Blank questions are left out.
  static StudySessionRecap? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final questions = raw['openQuestions'];
    return StudySessionRecap(
      covered: (raw['covered'] as String?)?.trim() ?? '',
      hard: (raw['hard'] as String?)?.trim() ?? '',
      openQuestions: questions is List
          ? [
              for (final question in questions)
                if (question is String && question.trim().isNotEmpty)
                  question.trim(),
            ]
          : const [],
    );
  }
}

/// A member's answer to a session, and when they checked in, if they did.
class StudySessionRsvp {
  const StudySessionRsvp({
    required this.email,
    required this.response,
    this.checkedInAt,
  });

  final String email;
  final StudySessionResponse response;

  /// When the member checked in. Null when they have not.
  final DateTime? checkedInAt;

  bool get isCheckedIn => checkedInAt != null;

  /// Reads one stored answer. Returns null when it has no answer, so a damaged one is left out.
  static StudySessionRsvp? fromMap(String email, Map<String, dynamic> map) {
    final response = StudySessionResponse.fromName(map['response']);
    if (response == null) return null;
    final checked = map['checkedInAt'];
    return StudySessionRsvp(
      email: email,
      response: response,
      checkedInAt: checked is DateTime ? checked : null,
    );
  }
}
