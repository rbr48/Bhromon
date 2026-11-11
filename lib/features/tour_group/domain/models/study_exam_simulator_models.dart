// Models for the timed exam simulator for IBB JAIBB and AIBB promotion exams.
// Pure offline data structures with JSON serialization support.

/// Whether the candidate has written anything for a question.
enum ExamQuestionStatus {
  unattempted,
  answered;

  static ExamQuestionStatus fromName(Object? raw) =>
      ExamQuestionStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => ExamQuestionStatus.unattempted,
      );
}

/// A question in the exam paper.
class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.number,
    required this.prompt,
    this.heading = '',
    this.marks = 20,
    this.modelAnswer = '',
    this.moduleCode,
  });

  final String id;
  final int number;

  /// The question statement the candidate answers.
  final String prompt;

  /// The paper's heading for the question, such as "Question 2 [Marks: 20]".
  final String heading;
  final int marks;

  /// The examiner's model answer. Shown only at review, never during the exam.
  final String modelAnswer;
  final String? moduleCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'prompt': prompt,
        if (heading.isNotEmpty) 'heading': heading,
        'marks': marks,
        if (modelAnswer.isNotEmpty) 'modelAnswer': modelAnswer,
        if (moduleCode != null) 'moduleCode': moduleCode,
      };

  static ExamQuestion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final number = (raw['number'] as num?)?.toInt();
    final prompt = raw['prompt'];
    if (id is! String || id.isEmpty || number == null || prompt is! String) {
      return null;
    }
    final marks = (raw['marks'] as num?)?.toInt() ?? 20;
    return ExamQuestion(
      id: id,
      number: number,
      prompt: prompt,
      heading: raw['heading'] as String? ?? '',
      marks: marks < 1 ? 20 : marks,
      modelAnswer: raw['modelAnswer'] as String? ?? '',
      moduleCode: raw['moduleCode'] as String?,
    );
  }
}

/// A candidate's attempt in the exam simulator.
///
/// The clock is the wall clock: the attempt ends at [endsAt], whether or not the app was
/// open in between. The paper's full marks are the sum of its question marks, so a
/// percentage and the pass decision are always about the paper that was sat.
class ExamAttempt {
  const ExamAttempt({
    required this.id,
    required this.tourId,
    required this.bookId,
    required this.chapterId,
    required this.paperTitle,
    required this.durationMinutes,
    required this.startedAt,
    this.paperMarks = 100,
    this.submittedAt,
    this.elapsedSeconds = 0,
    this.isCompleted = false,
    this.draftAnswers = const {},
    this.scores = const {},
    this.notes = '',
  });

  final String id;
  final String tourId;
  final String bookId;
  final String chapterId;
  final String paperTitle;
  final int durationMinutes;
  final DateTime startedAt;

  /// The full marks of the paper: the sum of its question marks. Attempts saved before
  /// this was stored were all out of 100.
  final int paperMarks;
  final DateTime? submittedAt;
  final int elapsedSeconds;
  final bool isCompleted;

  /// Candidate draft notes and outlines per question id.
  final Map<String, String> draftAnswers;

  /// Self-awarded marks per question id.
  final Map<String, int> scores;

  /// Candidate's post-exam reflection or notes.
  final String notes;

  /// When the exam time is over.
  DateTime get endsAt => startedAt.add(Duration(minutes: durationMinutes));

  /// The time left at [now], never negative.
  Duration remainingAt(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether the exam time is over at [now].
  bool isOverAt(DateTime now) => !now.isBefore(endsAt);

  /// Still open for the candidate: not handed in yet.
  bool get isOpen => !isCompleted && submittedAt == null;

  int get totalPossibleMarks => paperMarks;

  int get totalMarks => paperMarks;

  int get totalAwardedMarks =>
      scores.values.fold<int>(0, (sum, score) => sum + score);

  int get totalScore => totalAwardedMarks;

  /// The percentage of the full marks. For display only: the pass decision is [isPassed].
  double get scorePercentage => totalPossibleMarks > 0
      ? totalAwardedMarks * 100 / totalPossibleMarks
      : 0.0;

  double get percentage => scorePercentage;

  /// The pass mark, in percent of the full marks. IBB regulation clause 27 (JAIBB and AIBB, July 2023 edition,
  /// revised by the 155th Council on 13-03-2025): "The pass marks are 45 out of the full marks of 100 in each of
  /// the subjects of JAIBB and AIBB Examinations."
  static const int passPercent = 45;

  /// Compared in whole numbers, so a score is never rounded up over the mark.
  bool get isPassed {
    if (totalPossibleMarks <= 0) return false;
    return totalAwardedMarks * 100 >= passPercent * totalPossibleMarks;
  }

  /// A question is answered once the candidate has written something for it.
  ExamQuestionStatus questionStatus(String questionId) {
    final text = draftAnswers[questionId]?.trim() ?? '';
    return text.isEmpty
        ? ExamQuestionStatus.unattempted
        : ExamQuestionStatus.answered;
  }

  /// How many of [questionIds] are answered.
  int answeredCount(Iterable<String> questionIds) => questionIds
      .where((id) => questionStatus(id) == ExamQuestionStatus.answered)
      .length;

  ExamAttempt copyWith({
    int? elapsedSeconds,
    bool? isCompleted,
    DateTime? submittedAt,
    Map<String, String>? draftAnswers,
    Map<String, int>? scores,
    String? notes,
    int? paperMarks,
  }) =>
      ExamAttempt(
        id: id,
        tourId: tourId,
        bookId: bookId,
        chapterId: chapterId,
        paperTitle: paperTitle,
        durationMinutes: durationMinutes,
        startedAt: startedAt,
        paperMarks: paperMarks ?? this.paperMarks,
        submittedAt: submittedAt ?? this.submittedAt,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        isCompleted: isCompleted ?? this.isCompleted,
        draftAnswers: draftAnswers ?? this.draftAnswers,
        scores: scores ?? this.scores,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tourId': tourId,
        'bookId': bookId,
        'chapterId': chapterId,
        'paperTitle': paperTitle,
        'durationMinutes': durationMinutes,
        'startedAt': startedAt.toIso8601String(),
        'paperMarks': paperMarks,
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
        'elapsedSeconds': elapsedSeconds,
        'isCompleted': isCompleted,
        'draftAnswers': draftAnswers,
        'scores': scores,
        'notes': notes,
      };

  /// Reads an attempt. A value of the wrong type is left out rather than failing the whole
  /// attempt, and a missing or impossible value takes its default.
  static ExamAttempt? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final startedRaw = raw['startedAt'];
    if (id is! String || id.isEmpty || startedRaw is! String) return null;
    final startedAt = DateTime.tryParse(startedRaw);
    if (startedAt == null) return null;
    final submittedRaw = raw['submittedAt'];
    final durationMinutes = (raw['durationMinutes'] as num?)?.toInt() ?? 180;
    final paperMarks = (raw['paperMarks'] as num?)?.toInt() ?? 100;

    return ExamAttempt(
      id: id,
      tourId: raw['tourId'] as String? ?? '',
      bookId: raw['bookId'] as String? ?? '',
      chapterId: raw['chapterId'] as String? ?? '',
      paperTitle: raw['paperTitle'] as String? ?? '',
      durationMinutes: durationMinutes.clamp(1, 600).toInt(),
      startedAt: startedAt,
      paperMarks: paperMarks.clamp(1, 1000).toInt(),
      submittedAt:
          submittedRaw is String ? DateTime.tryParse(submittedRaw) : null,
      elapsedSeconds: (raw['elapsedSeconds'] as num?)?.toInt() ?? 0,
      isCompleted: raw['isCompleted'] == true,
      draftAnswers: _stringMap(raw['draftAnswers']),
      scores: _intMap(raw['scores']),
      notes: raw['notes'] as String? ?? '',
    );
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is String) '${entry.key}': entry.value as String,
    };
  }

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
    };
  }
}
