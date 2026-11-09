import '../models/study_quiz_models.dart';

// The rules of a quiz: what a question must hold before it is saved, how an attempt is scored, what a member's
// record becomes after an attempt, and which questions a quiz shows. Nothing here reads or writes the database.

/// What is wrong with a question, or null when it is fine.
enum StudyQuestionProblem {
  emptyText,
  textTooLong,
  choicesCount,
  emptyChoice,
  choiceTooLong,
  answerMissing,
  emptyModelAnswer,
  answerTooLong,
  emptyExplanation,
  explanationTooLong,
}

/// Checks a question before it is saved: its text, its choices or answer, and its explanation. Each kind
/// checks only the fields it uses.
StudyQuestionProblem? questionProblem({
  required StudyQuestionType type,
  required String text,
  required String explanation,
  List<String> choices = const [],
  int? answerIndex,
  String modelAnswer = '',
}) {
  final trimmedText = text.trim();
  if (trimmedText.isEmpty) return StudyQuestionProblem.emptyText;
  final trimmedExplanation = explanation.trim();
  if (trimmedExplanation.isEmpty) return StudyQuestionProblem.emptyExplanation;
  switch (type) {
    case StudyQuestionType.single:
      if (choices.length < StudyQuizLimits.choicesMin ||
          choices.length > StudyQuizLimits.choicesMax) {
        return StudyQuestionProblem.choicesCount;
      }
      for (final choice in choices) {
        if (choice.trim().isEmpty) return StudyQuestionProblem.emptyChoice;
      }
      if (answerIndex == null ||
          answerIndex < 0 ||
          answerIndex >= choices.length) {
        return StudyQuestionProblem.answerMissing;
      }
      return null;
    case StudyQuestionType.trueFalse:
      if (answerIndex == null || (answerIndex != 0 && answerIndex != 1)) {
        return StudyQuestionProblem.answerMissing;
      }
      return null;
    case StudyQuestionType.explain:
      final trimmedAnswer = modelAnswer.trim();
      if (trimmedAnswer.isEmpty) return StudyQuestionProblem.emptyModelAnswer;
      return null;
  }
}

/// Whether the chosen answer is right for a single-answer or true-or-false question. An explain question is
/// marked by the member, so it has no right answer to compare with.
bool isCorrectChoice(StudyQuizQuestion question, int chosen) {
  if (question.type == StudyQuestionType.explain) return false;
  return question.answerIndex == chosen;
}

/// The score of an attempt as a whole percentage, rounded down. Zero when there are no questions.
int scorePercent({required int correct, required int total}) {
  if (total <= 0) return 0;
  final clamped = _clampInt(correct, 0, total);
  return (clamped * 100) ~/ total;
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// The record after one more attempt: the best score so far, the last score, and the count of attempts.
StudyQuizAttempt nextAttempt(StudyQuizAttempt? previous, int percent) {
  final score = _clampInt(percent, 0, 100);
  if (previous == null) {
    return StudyQuizAttempt(best: score, last: score, attempts: 1);
  }
  return StudyQuizAttempt(
    best: score > previous.best ? score : previous.best,
    last: score,
    attempts: previous.attempts + 1,
  );
}

/// The questions a quiz shows: the approved ones only, in the order given.
List<StudyQuizQuestion> quizQuestions(Iterable<StudyQuizQuestion> questions) =>
    [
      for (final question in questions)
        if (question.approved) question,
    ];

/// Whether a member may approve a proposed question. Only an admin does.
bool canApproveQuestion({required bool isAdmin}) => isAdmin;

/// Whether a member may remove a question: an admin, or the member who proposed it while it is still a
/// proposal.
bool canRemoveQuestion(
  StudyQuizQuestion question, {
  required String viewerEmail,
  required bool isAdmin,
}) {
  if (isAdmin) return true;
  return !question.approved && question.proposedByEmail == viewerEmail;
}
