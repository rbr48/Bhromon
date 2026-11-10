// Models for the 3-Hour Timed Exam Simulator for IBB JAIBB banking promotion exams.
// Pure offline data structures with JSON serialization support.

/// The status of a question in the candidate's exam tray.
enum ExamQuestionStatus {
  unattempted,
  inProgress,
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
    this.marks = 20,
    this.modelAnswer = '',
    this.moduleCode,
  });

  final String id;
  final int number;
  final String prompt;
  final int marks;
  final String modelAnswer;
  final String? moduleCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'prompt': prompt,
        'marks': marks,
        if (modelAnswer.isNotEmpty) 'modelAnswer': modelAnswer,
        if (moduleCode != null) 'moduleCode': moduleCode,
      };

  static ExamQuestion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final number = (raw['number'] as num?)?.toInt();
    final prompt = raw['prompt'];
    final marks = (raw['marks'] as num?)?.toInt() ?? 20;
    final modelAnswer = raw['modelAnswer'] as String? ?? '';
    final moduleCode = raw['moduleCode'] as String?;

    if (id is! String || id.isEmpty || number == null || prompt is! String) {
      return null;
    }

    return ExamQuestion(
      id: id,
      number: number,
      prompt: prompt,
      marks: marks,
      modelAnswer: modelAnswer,
      moduleCode: moduleCode,
    );
  }
}

/// A candidate's attempt in the exam simulator.
class ExamAttempt {
  const ExamAttempt({
    required this.id,
    required this.tourId,
    required this.bookId,
    required this.chapterId,
    required this.paperTitle,
    required this.durationMinutes,
    required this.startedAt,
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
  final DateTime? submittedAt;
  final int elapsedSeconds;
  final bool isCompleted;

  /// Candidate draft notes and outlines per question id.
  final Map<String, String> draftAnswers;

  /// Self-awarded marks per question id.
  final Map<String, int> scores;

  /// Candidate's post-exam reflection or notes.
  final String notes;

  int get totalAwardedMarks =>
      scores.values.fold<int>(0, (sum, score) => sum + score);

  int get totalPossibleMarks => 100; // Standard IBB 5 questions * 20 marks

  int get totalScore => totalAwardedMarks;

  int get totalMarks => totalPossibleMarks;

  double get scorePercentage => totalPossibleMarks > 0
      ? double.parse(
          (totalAwardedMarks / totalPossibleMarks * 100).toStringAsFixed(1))
      : 0.0;

  double get percentage => scorePercentage;

  bool get isPassed => scorePercentage >= 50.0; // IBB JAIBB pass mark is 50%

  ExamQuestionStatus questionStatus(String questionId) {
    final text = draftAnswers[questionId]?.trim() ?? '';
    if (text.isEmpty) return ExamQuestionStatus.unattempted;
    if (text.length < 50) return ExamQuestionStatus.inProgress;
    return ExamQuestionStatus.answered;
  }

  ExamAttempt copyWith({
    int? elapsedSeconds,
    bool? isCompleted,
    DateTime? submittedAt,
    Map<String, String>? draftAnswers,
    Map<String, int>? scores,
    String? notes,
  }) =>
      ExamAttempt(
        id: id,
        tourId: tourId,
        bookId: bookId,
        chapterId: chapterId,
        paperTitle: paperTitle,
        durationMinutes: durationMinutes,
        startedAt: startedAt,
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
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
        'elapsedSeconds': elapsedSeconds,
        'isCompleted': isCompleted,
        'draftAnswers': draftAnswers,
        'scores': scores,
        'notes': notes,
      };

  static ExamAttempt? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final tourId = raw['tourId'] as String? ?? '';
    final bookId = raw['bookId'] as String? ?? '';
    final chapterId = raw['chapterId'] as String? ?? '';
    final paperTitle = raw['paperTitle'] as String? ?? '';
    final durationMinutes = (raw['durationMinutes'] as num?)?.toInt() ?? 180;
    final startedRaw = raw['startedAt'];
    final submittedRaw = raw['submittedAt'];
    final elapsedSeconds = (raw['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final isCompleted = raw['isCompleted'] == true;
    final draftAnswers = (raw['draftAnswers'] as Map?)?.map(
          (k, v) => MapEntry('$k', '$v'),
        ) ??
        const {};
    final scores = (raw['scores'] as Map?)?.map(
          (k, v) => MapEntry('$k', (v as num).toInt()),
        ) ??
        const {};
    final notes = raw['notes'] as String? ?? '';

    if (id is! String || id.isEmpty || startedRaw is! String) return null;
    final startedAt = DateTime.tryParse(startedRaw);
    if (startedAt == null) return null;
    final submittedAt =
        submittedRaw is String ? DateTime.tryParse(submittedRaw) : null;

    return ExamAttempt(
      id: id,
      tourId: tourId,
      bookId: bookId,
      chapterId: chapterId,
      paperTitle: paperTitle,
      durationMinutes: durationMinutes,
      startedAt: startedAt,
      submittedAt: submittedAt,
      elapsedSeconds: elapsedSeconds,
      isCompleted: isCompleted,
      draftAnswers: draftAnswers,
      scores: scores,
      notes: notes,
    );
  }
}
