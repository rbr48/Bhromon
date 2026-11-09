import '../models/study_glossary_models.dart';
import '../models/study_material_models.dart';
import '../models/study_models.dart';
import '../models/study_summary_models.dart';
import 'study_chapter_rules.dart';
import 'study_glossary_rules.dart';
import 'study_progress_rules.dart';

// The study pack of a book: what the group shares, gathered into one document a member can keep. It holds the
// pinned chapter summaries, the accepted answers, the approved glossary terms, the session recaps, and the published
// materials as titles and links. It holds no files, scores, uncounted reads, flashcards or reports, because none of
// those has a field here.

/// One chapter in the pack: the pinned summary of a chapter an admin pinned.
class StudyPackChapter {
  const StudyPackChapter({
    required this.number,
    required this.title,
    required this.summary,
  });

  final int number;
  final String title;
  final String summary;
}

/// One accepted answer: the question the thread asked and the reply the asker accepted.
class StudyPackAnswer {
  const StudyPackAnswer({required this.question, required this.answer});

  final String question;
  final String answer;
}

/// One approved glossary term.
class StudyPackTerm {
  const StudyPackTerm({required this.term, required this.definition});

  final String term;
  final String definition;
}

/// The recap of a reading session: what the group covered, what was hard, and the questions still open.
class StudyPackRecap {
  const StudyPackRecap({
    required this.title,
    required this.covered,
    required this.hard,
    required this.openQuestions,
  });

  final String title;
  final String covered;
  final String hard;
  final List<String> openQuestions;
}

/// A published material, as its title and, for a link, its web address. A file has a title and no link: the pack
/// never carries a file, and a file's link is signed for members only.
class StudyPackMaterial {
  const StudyPackMaterial({required this.title, this.url});

  final String title;
  final String? url;
}

/// The study pack of one book.
class StudyPack {
  const StudyPack({
    required this.bookTitle,
    required this.chapters,
    required this.answers,
    required this.terms,
    required this.recaps,
    required this.materials,
  });

  final String bookTitle;
  final List<StudyPackChapter> chapters;
  final List<StudyPackAnswer> answers;
  final List<StudyPackTerm> terms;
  final List<StudyPackRecap> recaps;
  final List<StudyPackMaterial> materials;

  /// Whether there is nothing to put in the pack yet.
  bool get isEmpty =>
      chapters.isEmpty &&
      answers.isEmpty &&
      terms.isEmpty &&
      recaps.isEmpty &&
      materials.isEmpty;
}

/// Gathers the study pack of [book] from what the group shares.
///
/// Only a chapter with a pinned summary contributes one, and its pinned revision is the one used, even when a newer
/// revision exists. The accepted answers come from [acceptedAnswers]. Only approved glossary terms are used. A
/// session contributes its recap when the recap says something. A material contributes only when it is published.
StudyPack buildStudyPack({
  required StudyBook book,
  required List<StudyChapter> chapters,
  required Map<String, List<StudySummaryRevision>> revisionsByChapter,
  required List<({String question, String answer})> acceptedAnswers,
  required List<StudyGlossaryTerm> glossary,
  required List<ReadingSession> sessions,
  required List<StudyMaterial> materials,
}) {
  final packChapters = <StudyPackChapter>[];
  for (final chapter in sortStudyChapters(chapters)) {
    final shown = summaryShownToGroup(
      revisionsByChapter[chapter.id] ?? const [],
      pinnedId: chapter.pinnedSummaryId,
    );
    final revision = shown.revision;
    if (!shown.pinned || revision == null) continue;
    packChapters.add(StudyPackChapter(
      number: chapter.number,
      title: chapter.title,
      summary: revision.text,
    ));
  }

  final packTerms = [
    for (final term in approvedTerms(glossary))
      StudyPackTerm(term: term.term, definition: term.definition),
  ];

  final bookSessions = [
    for (final session in sessions)
      if (session.bookId == book.id && session.recap != null) session,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final packRecaps = <StudyPackRecap>[];
  for (final session in bookSessions) {
    final recap = session.recap!;
    final openQuestions = [
      for (final question in recap.openQuestions)
        if (question.trim().isNotEmpty) question.trim(),
    ];
    if (recap.covered.trim().isEmpty &&
        recap.hard.trim().isEmpty &&
        openQuestions.isEmpty) {
      continue;
    }
    packRecaps.add(StudyPackRecap(
      title: session.title,
      covered: recap.covered.trim(),
      hard: recap.hard.trim(),
      openQuestions: openQuestions,
    ));
  }

  final packMaterials = [
    for (final material in materials)
      if (material.bookId == book.id &&
          material.status == StudyMaterialStatus.published)
        StudyPackMaterial(
          title: material.title,
          url: material.kind == StudyMaterialKind.link ? material.url : null,
        ),
  ];

  return StudyPack(
    bookTitle: book.title,
    chapters: packChapters,
    answers: [
      for (final answer in acceptedAnswers)
        StudyPackAnswer(question: answer.question, answer: answer.answer),
    ],
    terms: packTerms,
    recaps: packRecaps,
    materials: packMaterials,
  );
}
