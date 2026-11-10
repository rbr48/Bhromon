// Pure rules and parsing utilities for the 3-Hour Timed Exam Simulator.
// Completely offline, deterministic logic with zero external AI dependencies.

import '../models/study_exam_simulator_models.dart';
import '../models/study_syllabus_models.dart';

/// The alert state of the exam timer based on time remaining.
enum ExamTimerAlertState {
  normal, // > 30 minutes
  warning, // <= 30 minutes (amber indicator)
  critical, // <= 10 minutes (pulsing red indicator)
  expired; // 0 seconds remaining

  bool get isWarning => this == ExamTimerAlertState.warning;
  bool get isCritical => this == ExamTimerAlertState.critical;
  bool get isExpired => this == ExamTimerAlertState.expired;
}

class StudyExamTimerRules {
  const StudyExamTimerRules._();

  /// Determines the timer alert state based on remaining time.
  static ExamTimerAlertState getAlertState(Duration remaining) {
    if (remaining <= Duration.zero) return ExamTimerAlertState.expired;
    if (remaining <= const Duration(minutes: 10)) {
      return ExamTimerAlertState.critical;
    }
    if (remaining <= const Duration(minutes: 30)) {
      return ExamTimerAlertState.warning;
    }
    return ExamTimerAlertState.normal;
  }

  /// Formats duration as `HH:mm:ss` (or `mm:ss` when under an hour).
  static String formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '00:00:00';
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

/// Deterministically parses Markdown solution documents into structured [ExamQuestion] objects.
class StudyExamSimulatorExtractor {
  const StudyExamSimulatorExtractor._();

  static final RegExp _mainHeadingPattern = RegExp(
    r'^(#{1,3})\s+(.*?(?:Question|প্রশ্ন|PART|GROUP|বিভাগ)\s*(\d{1,2}|[\u09E6-\u09EF]{1,2}).*?)$',
    multiLine: true,
    caseSensitive: false,
  );

  static final RegExp _marksPattern = RegExp(
    r'(?:Marks?|মান|নম্বর)[\s:]*([0-9\+\s=]+|[\u09E6-\u09EF\+\s=]+)',
    caseSensitive: false,
  );

  /// Extracts structured questions and examiner model answers from exam markdown.
  static List<ExamQuestion> extractQuestions({
    required String subjectTitle,
    required String markdownContent,
    int defaultMarksPerQuestion = 20,
    int maxQuestions = 10,
  }) {
    if (markdownContent.trim().isEmpty) {
      return _generateDefaultQuestions(subjectTitle);
    }

    final matches = _mainHeadingPattern.allMatches(markdownContent).toList();
    if (matches.isEmpty) {
      // Fallback: general ## or ### headings
      final generalPattern = RegExp(r'^(#{2,3})\s+(.+)$', multiLine: true);
      matches.addAll(generalPattern.allMatches(markdownContent));
    }

    if (matches.isEmpty) {
      return _generateDefaultQuestions(subjectTitle);
    }

    final questions = <ExamQuestion>[];

    for (var i = 0; i < matches.length; i++) {
      if (questions.length >= maxQuestions) break;

      final current = matches[i];
      final headingText = current.group(2)?.trim() ?? '';
      final startIndex = current.end;
      final endIndex = i + 1 < matches.length
          ? matches[i + 1].start
          : markdownContent.length;

      final body = markdownContent.substring(startIndex, endIndex).trim();
      final marks =
          _parseMarks(headingText, defaultMarks: defaultMarksPerQuestion);
      final mod = StudySyllabusCatalog.identifyModule(
        subjectTitle,
        '$headingText $body',
      );

      questions.add(ExamQuestion(
        id: 'q_${i + 1}',
        number: i + 1,
        prompt: headingText,
        marks: marks,
        modelAnswer: body,
        moduleCode: mod?.code,
      ));
    }

    return questions.isNotEmpty
        ? questions
        : _generateDefaultQuestions(subjectTitle);
  }

  static int _parseMarks(String text, {required int defaultMarks}) {
    final match = _marksPattern.firstMatch(text);
    if (match != null) {
      final raw = match.group(1)?.trim() ?? '';
      // If contains '=', take the total after '=': e.g. '10 + 10 = 20' -> 20
      if (raw.contains('=')) {
        final afterEq = raw.split('=').last.trim();
        final parsed = _convertDigits(afterEq);
        if (parsed != null && parsed > 0 && parsed <= 50) return parsed;
      }
      final parsed = _convertDigits(raw);
      if (parsed != null && parsed > 0 && parsed <= 50) return parsed;
    }
    return defaultMarks;
  }

  static int? _convertDigits(String text) {
    const bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    var converted = '';
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final bnIndex = bnDigits.indexOf(char);
      if (bnIndex != -1) {
        converted += '$bnIndex';
      } else if (int.tryParse(char) != null) {
        converted += char;
      }
    }
    return int.tryParse(converted);
  }

  /// Fallback when no markdown solution is attached: standard 8-question IBB paper format.
  static List<ExamQuestion> fallbackQuestions(String subjectTitle,
      {int count = 8}) {
    return _generateDefaultQuestions(subjectTitle, count: count);
  }

  static List<ExamQuestion> _generateDefaultQuestions(String subjectTitle,
      {int count = 8}) {
    final modules = StudySyllabusCatalog.modulesFor(subjectTitle);
    return List.generate(count, (index) {
      final number = index + 1;
      final mod = modules.isNotEmpty ? modules[index % modules.length] : null;
      return ExamQuestion(
        id: 'q_$number',
        number: number,
        prompt: 'Question $number [Marks: 20]',
        marks: 20,
        modelAnswer:
            'Official examiner model answer not yet attached for this past paper.',
        moduleCode: mod?.code,
      );
    });
  }
}
