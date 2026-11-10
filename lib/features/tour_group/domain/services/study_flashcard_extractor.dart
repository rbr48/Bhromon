import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/study_flashcard_models.dart';
import '../models/study_syllabus_models.dart';
import 'study_flashcard_rules.dart';

/// Deterministically parses Markdown exam solutions into question-answer flashcard pairs
/// mapped to their official IBB JAIBB syllabus modules.
class StudyFlashcardExtractor {
  const StudyFlashcardExtractor._();

  /// Regex pattern matching main question headers:
  /// `### Question 1 [Marks: 5 + 5 = 10]`
  /// `### প্রশ্ন ১ [মান: ১০ + ১০ = ২০]`
  /// `## Question 2`
  static final RegExp _mainHeadingPattern = RegExp(
    r'^(#{1,3})\s+(.*?(?:Question|প্রশ্ন|PART|GROUP|বিভাগ).*?)$',
    multiLine: true,
    caseSensitive: false,
  );

  /// Regex pattern matching sub-question items:
  /// `১(ক) ...` or `1(a) ...` or `(a) ...` or `(ক) ...`
  static final RegExp _subQuestionPattern = RegExp(
    r'^(?:(?:\d{1,2}|[\u09E6-\u09EF]{1,2})[\.\s]*)?\(?([a-zA-Z\u0995-\u09B9])\)?[\.\s]+(.+)$',
    multiLine: true,
  );

  /// Extracts structured question/answer flashcards from a markdown solution text.
  static List<StudyFlashcard> extractFromMarkdown({
    required String deckId,
    required String subjectTitle,
    required String markdownContent,
    required DateTime today,
    int maxCards = 50,
  }) {
    if (markdownContent.trim().isEmpty) return const [];

    final cards = <StudyFlashcard>[];
    final cleanDayKey = dayKey(today);

    // 1. Locate all main question sections
    final matches = _mainHeadingPattern.allMatches(markdownContent).toList();
    if (matches.isEmpty) {
      // Fallback: split by general ## or ### headings
      final generalPattern = RegExp(r'^(#{2,3})\s+(.+)$', multiLine: true);
      matches.addAll(generalPattern.allMatches(markdownContent));
    }

    if (matches.isEmpty) {
      return const [];
    }

    for (var i = 0; i < matches.length; i++) {
      if (cards.length >= maxCards) break;

      final current = matches[i];
      final headingText = current.group(2)?.trim() ?? '';
      final startIndex = current.end;
      final endIndex = i + 1 < matches.length
          ? matches[i + 1].start
          : markdownContent.length;

      final sectionBody =
          markdownContent.substring(startIndex, endIndex).trim();
      if (sectionBody.isEmpty) continue;

      // Check if section contains sub-questions (e.g. 1(a), 1(b) or ১(ক), ১(খ))
      final subMatches = _subQuestionPattern.allMatches(sectionBody).toList();
      if (subMatches.length >= 2) {
        for (var j = 0; j < subMatches.length; j++) {
          if (cards.length >= maxCards) break;
          final sub = subMatches[j];
          final subPrompt = sub.group(0)?.trim() ?? '';
          final subStart = sub.end;
          final subEnd = j + 1 < subMatches.length
              ? subMatches[j + 1].start
              : sectionBody.length;
          final subBody = sectionBody.substring(subStart, subEnd).trim();

          final cleanFront = _cleanHeading('$headingText - $subPrompt');
          final cleanBack = _cleanAnswer(subBody);

          if (cleanFront.length >= 5 && cleanBack.length >= 10) {
            final cardId = _generateCardId(deckId, cleanFront);
            final mod = StudySyllabusCatalog.identifyModule(
              subjectTitle,
              '$cleanFront $cleanBack',
            );

            cards.add(StudyFlashcard(
              id: cardId,
              deckId: deckId,
              front: cleanFront,
              back: cleanBack,
              box: StudyFlashcardLimits.boxMin,
              dueOn: cleanDayKey,
              moduleCode: mod?.code,
            ));
          }
        }
      } else {
        // Section is a standalone broad question
        final lines = sectionBody.split('\n');
        String questionPrompt = headingText;
        String answerBody = sectionBody;

        if (lines.isNotEmpty && lines.first.trim().endsWith('?')) {
          questionPrompt =
              '${_cleanHeading(headingText)}: ${lines.first.trim()}';
          answerBody = lines.skip(1).join('\n').trim();
        }

        final cleanFront = _cleanHeading(questionPrompt);
        final cleanBack = _cleanAnswer(answerBody);

        if (cleanFront.length >= 5 && cleanBack.length >= 10) {
          final cardId = _generateCardId(deckId, cleanFront);
          final mod = StudySyllabusCatalog.identifyModule(
            subjectTitle,
            '$cleanFront $cleanBack',
          );

          cards.add(StudyFlashcard(
            id: cardId,
            deckId: deckId,
            front: cleanFront,
            back: cleanBack,
            box: StudyFlashcardLimits.boxMin,
            dueOn: cleanDayKey,
            moduleCode: mod?.code,
          ));
        }
      }
    }

    return cards;
  }

  static String _cleanHeading(String text) {
    return text
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanAnswer(String text) {
    final cleaned =
        text.replaceAll(RegExp(r'^#+\s*', multiLine: true), '').trim();
    if (cleaned.length <= 450) {
      return cleaned;
    }
    // Truncate cleanly at a sentence or punctuation boundary
    final sub = cleaned.substring(0, 440);
    final lastPunct = sub.lastIndexOf(RegExp(r'[\.\n।!?]'));
    if (lastPunct > 180) {
      return '${cleaned.substring(0, lastPunct + 1).trim()} ...';
    }
    return '$sub...';
  }

  static String _generateCardId(String deckId, String front) {
    final bytes = utf8.encode('$deckId:$front');
    final digest = sha256.convert(bytes);
    return 'fc_${digest.toString().substring(0, 14)}';
  }
}
