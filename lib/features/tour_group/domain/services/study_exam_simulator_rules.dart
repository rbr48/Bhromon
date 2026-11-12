// Pure rules and parsing for the timed exam simulator. Deterministic and offline: no AI.

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

/// A timer warning the candidate sees once, when the time left first falls to it.
enum ExamTimerWarning { thirtyMinutes, tenMinutes }

class StudyExamTimerRules {
  const StudyExamTimerRules._();

  static const Duration warningLeft = Duration(minutes: 30);
  static const Duration criticalLeft = Duration(minutes: 10);

  /// Determines the timer alert state based on remaining time.
  static ExamTimerAlertState getAlertState(Duration remaining) {
    if (remaining <= Duration.zero) return ExamTimerAlertState.expired;
    if (remaining <= criticalLeft) return ExamTimerAlertState.critical;
    if (remaining <= warningLeft) return ExamTimerAlertState.warning;
    return ExamTimerAlertState.normal;
  }

  /// The warning reached when the time left falls from [before] to [after], if any. A time
  /// that is already over reaches no warning.
  static ExamTimerWarning? crossedWarning(Duration before, Duration after) {
    if (after <= Duration.zero) return null;
    if (before > criticalLeft && after <= criticalLeft) {
      return ExamTimerWarning.tenMinutes;
    }
    if (before > warningLeft && after <= warningLeft) {
      return ExamTimerWarning.thirtyMinutes;
    }
    return null;
  }

  /// Formats duration as `HH:mm:ss`, with ASCII digits. The screen localises the digits.
  static String formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '00:00:00';
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

/// One heading and the text under it, before it is joined to the question it belongs to.
class _Section {
  const _Section(this.heading, this.statement, this.answer);

  final String heading;
  final String statement;
  final String answer;
}

/// Reads a past paper's solution markdown into exam questions.
///
/// A question starts at a heading that names a question ("Question 2", "প্রশ্ন ১", "PART 1").
/// Headings with the same number, such as sub-parts "Question 1 (b)", join that question. Its
/// text is split at the first answer marker ("Answer", "Solution", "উত্তর", "সমাধান"): the text
/// before the marker is the question the candidate answers, and the text after it is the
/// examiner's model answer. A paper with no question headings gives no questions. Nothing is
/// invented to fill a paper.
class StudyExamSimulatorExtractor {
  const StudyExamSimulatorExtractor._();

  static final RegExp _headingPattern = RegExp(
    r'^(#{1,3})[ \t]+(.+?)[ \t]*$',
    multiLine: true,
  );

  static final RegExp _questionMarker = RegExp(
    r'(?:Question|প্রশ্ন|PART|GROUP|বিভাগ)[ \t]*([0-9০-৯]{1,2})',
    caseSensitive: false,
  );

  /// A marks label is followed by a digit, so a word that contains "মান" does not match.
  static final RegExp _marksLabel = RegExp(
    r'(?:Marks?|মান|নম্বর)[ \t:：]*(?=[0-9০-৯])',
    caseSensitive: false,
  );

  /// The answer marker stands alone at the start of a line, optionally followed by a colon.
  /// A word that begins the same way ("উত্তরাধিকার") does not match.
  static final RegExp _answerMarker = RegExp(
    r'^[ \t]*(?:#{1,6}[ \t]*)?(?:\*\*)?[ \t]*'
    r'(?:আদর্শ উত্তর|উত্তর|সমাধান|model answer|answer|solution)'
    r'[ \t]*(?:\*\*)?[ \t]*(?:[:：.\-–—](?:\*\*)?[ \t]*|$)',
    multiLine: true,
    caseSensitive: false,
  );

  static final RegExp _digitRun = RegExp(r'[0-9]+');

  static const String _bengaliDigits = '০১২৩৪৫৬৭৮৯';

  static String _asciiDigits(String text) => text.replaceAllMapped(
        RegExp('[$_bengaliDigits]'),
        (match) => '${_bengaliDigits.indexOf(match.group(0)!)}',
      );

  static int? _firstNumber(String text) {
    final match = _digitRun.firstMatch(text);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static int? _questionNumber(String heading) {
    final match = _questionMarker.firstMatch(heading);
    return match == null ? null : int.tryParse(_asciiDigits(match.group(1)!));
  }

  /// The question statement and the model answer in the text under a question heading.
  static ({String statement, String answer}) splitBody(String body) {
    final marker = _answerMarker.firstMatch(body);
    if (marker == null) return (statement: '', answer: body.trim());
    return (
      statement: body.substring(0, marker.start).trim(),
      answer: body.substring(marker.end).trim(),
    );
  }

  /// The marks named by a question heading: "[Marks: 20]", "[মান: ১০ + ১০ = ২০]" (the total
  /// after "="), or "[Marks: 5 + 5]" (the sum). Null when the heading names no usable marks.
  static int? parseMarks(String heading) {
    final label = _marksLabel.firstMatch(heading);
    if (label == null) return null;
    final expression = _asciiDigits(heading.substring(label.end))
        .split(RegExp(r'[\]\)\n]'))
        .first;
    int? value;
    if (expression.contains('=')) {
      value = _firstNumber(expression.split('=').last);
    } else if (expression.contains('+')) {
      final parts = expression.split('+').map(_firstNumber).whereType<int>();
      if (parts.isNotEmpty) value = parts.fold<int>(0, (sum, p) => sum + p);
    } else {
      value = _firstNumber(expression);
    }
    if (value == null || value < 1 || value > 100) return null;
    return value;
  }

  /// Extracts the questions of a paper's solution markdown. Empty when no heading names a
  /// question, so the caller shows that the paper is not available.
  static List<ExamQuestion> extractQuestions({
    required String subjectTitle,
    required String markdownContent,
    int defaultMarksPerQuestion = 20,
  }) {
    final text =
        markdownContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final headings = [
      for (final match in _headingPattern.allMatches(text))
        if (_questionNumber(match.group(2)!) != null) match,
    ];

    final order = <int>[];
    final sections = <int, List<_Section>>{};
    for (var i = 0; i < headings.length; i++) {
      final match = headings[i];
      final heading = match.group(2)!.trim();
      final number = _questionNumber(heading)!;
      final end = i + 1 < headings.length ? headings[i + 1].start : text.length;
      final body = splitBody(text.substring(match.end, end));
      if (!sections.containsKey(number)) {
        order.add(number);
        sections[number] = [];
      }
      sections[number]!.add(_Section(heading, body.statement, body.answer));
    }

    final questions = <ExamQuestion>[];
    for (final number in order) {
      final parts = sections[number]!;
      final heading = parts.first.heading;
      final statement = [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].statement.isNotEmpty)
            i == 0
                ? parts[i].statement
                : '**${parts[i].heading}**\n\n${parts[i].statement}',
      ].join('\n\n');
      final answer = [
        for (final part in parts)
          if (part.answer.isNotEmpty) part.answer,
      ].join('\n\n');
      var marks = defaultMarksPerQuestion;
      for (final part in parts) {
        final named = parseMarks(part.heading);
        if (named != null) {
          marks = named;
          break;
        }
      }
      final module = StudySyllabusCatalog.identifyModule(
        subjectTitle,
        '$heading $statement $answer',
      );
      questions.add(ExamQuestion(
        id: 'q_${questions.length + 1}',
        number: questions.length + 1,
        prompt: statement.isNotEmpty ? statement : heading,
        heading: heading,
        marks: marks,
        modelAnswer: answer,
        moduleCode: module?.code,
      ));
    }
    return questions;
  }
}
