// The quizzes of a study book: a quiz on one chapter, its questions, and a member's private attempt. Admins
// write a quiz; members propose questions, and an admin approves each one before it joins the quiz. A quiz's
// takerCount counts members, never scores. The attempt is stored under the member's email and read by that
// member only (tours/{id}/study_books/{id}/quizzes/{id}/attempts/{email}).

/// The limits a quiz, its questions and its attempts are checked against, as firestore.rules checks them.
class StudyQuizLimits {
  const StudyQuizLimits._();

  static const int titleMax = 120;
  static const int questionMax = 300;
  static const int choiceMax = 150;
  static const int choicesMin = 2;
  static const int choicesMax = 5;
  static const int answerMax = 1000;
  static const int explanationMax = 1000;
}

/// The three kinds of question a quiz holds.
enum StudyQuestionType {
  /// One answer out of two to five choices.
  single,

  /// True (index 0) or false (index 1).
  trueFalse,

  /// Written in the member's own words. The member sees the model answer and marks their own work.
  explain;

  /// An unknown stored type reads as no question at all.
  static StudyQuestionType? fromName(Object? raw) {
    for (final type in StudyQuestionType.values) {
      if (type.name == raw) return type;
    }
    return null;
  }
}

/// A quiz on one chapter of a book.
class StudyQuiz {
  const StudyQuiz({
    required this.id,
    required this.chapterId,
    required this.title,
    this.createdByEmail = '',
    this.takerCount = 0,
  });

  final String id;

  /// The chapter the quiz covers.
  final String chapterId;

  final String title;

  /// The admin who wrote the quiz.
  final String createdByEmail;

  /// How many members have taken the quiz. Nothing about who or how well.
  final int takerCount;

  /// The fields written when a quiz is added. The taker count starts at zero.
  Map<String, dynamic> toFields() => {
        'chapterId': chapterId,
        'title': title,
        'createdByEmail': createdByEmail,
        'takerCount': takerCount,
      };

  /// Reads one stored quiz. Returns null when it has no title or chapter, so a damaged quiz does not
  /// break the list.
  static StudyQuiz? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final chapterId = (map['chapterId'] as String?)?.trim() ?? '';
    if (title.isEmpty || chapterId.isEmpty) return null;
    return StudyQuiz(
      id: id,
      chapterId: chapterId,
      title: title,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      takerCount: (map['takerCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One question of a quiz. A single-answer question carries its choices and the index of the right one.
/// A true-or-false question carries the index of its answer. An explain question carries a model answer.
/// Every question carries an explanation, which is shown after the member answers.
class StudyQuizQuestion {
  const StudyQuizQuestion({
    required this.id,
    required this.type,
    required this.text,
    required this.explanation,
    this.choices = const [],
    this.answerIndex,
    this.modelAnswer = '',
    this.approved = false,
    this.proposedByEmail = '',
  });

  final String id;
  final StudyQuestionType type;
  final String text;
  final String explanation;

  /// The choices of a single-answer question. Empty for the other kinds.
  final List<String> choices;

  /// The index of the right answer, for the single and true-or-false kinds. Null for explain.
  final int? answerIndex;

  /// The model answer of an explain question. Empty for the other kinds.
  final String modelAnswer;

  /// Whether an admin has approved the question. Only approved questions are in the quiz.
  final bool approved;

  /// The member who proposed the question.
  final String proposedByEmail;

  /// The fields written for a question. Fields the kind does not use are stored as null.
  Map<String, dynamic> toFields() => {
        'type': type.name,
        'text': text,
        'explanation': explanation,
        'choices': type == StudyQuestionType.single ? choices : null,
        'answerIndex': type == StudyQuestionType.explain ? null : answerIndex,
        'modelAnswer': type == StudyQuestionType.explain ? modelAnswer : null,
        'approved': approved,
        'proposedByEmail': proposedByEmail,
      };

  /// Reads one stored question. Returns null when it has no kind, text or explanation.
  static StudyQuizQuestion? fromMap(String id, Map<String, dynamic> map) {
    final type = StudyQuestionType.fromName(map['type']);
    final text = (map['text'] as String?)?.trim() ?? '';
    final explanation = (map['explanation'] as String?)?.trim() ?? '';
    if (type == null || text.isEmpty || explanation.isEmpty) return null;
    final rawChoices = map['choices'];
    final choices = rawChoices is List
        ? [
            for (final choice in rawChoices)
              if (choice is String && choice.trim().isNotEmpty) choice.trim(),
          ]
        : <String>[];
    return StudyQuizQuestion(
      id: id,
      type: type,
      text: text,
      explanation: explanation,
      choices: choices,
      answerIndex: (map['answerIndex'] as num?)?.toInt(),
      modelAnswer: (map['modelAnswer'] as String?)?.trim() ?? '',
      approved: map['approved'] == true,
      proposedByEmail: (map['proposedByEmail'] as String?) ?? '',
    );
  }
}

/// A member's private record on one quiz: the best score, the last score and how many attempts they made,
/// each as a percentage or a count. Only the member reads it.
class StudyQuizAttempt {
  const StudyQuizAttempt({
    required this.best,
    required this.last,
    required this.attempts,
  });

  /// The best score so far, as a whole percentage from 0 to 100.
  final int best;

  /// The score of the latest attempt, as a whole percentage from 0 to 100.
  final int last;

  /// How many attempts the member has made, from 1.
  final int attempts;

  Map<String, dynamic> toFields() => {
        'best': best,
        'last': last,
        'attempts': attempts,
      };

  /// Reads a stored attempt. Returns null when a score or the count is missing or out of range.
  static StudyQuizAttempt? fromMap(Map<String, dynamic> map) {
    final best = (map['best'] as num?)?.toInt();
    final last = (map['last'] as num?)?.toInt();
    final attempts = (map['attempts'] as num?)?.toInt();
    if (best == null || last == null || attempts == null) return null;
    if (best < 0 || best > 100 || last < 0 || last > 100 || attempts < 1) {
      return null;
    }
    return StudyQuizAttempt(best: best, last: last, attempts: attempts);
  }
}
