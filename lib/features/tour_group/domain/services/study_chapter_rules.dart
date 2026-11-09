import '../models/study_models.dart';

/// The fewest and most chapters a member can plan to read in a week, for the reading pace.
const int kPaceMin = 1;
const int kPaceMax = 14;

/// The due date of each chapter in order, from a start date and a number of chapters a
/// week. The start day is day one, and a chapter is due on the last day of the week it
/// falls in. The result has [count] dates; a pace outside the limits is brought inside them.
List<DateTime> chapterDueDates({
  required DateTime start,
  required int perWeek,
  required int count,
}) {
  final first = DateTime(start.year, start.month, start.day);
  final pace = perWeek.clamp(kPaceMin, kPaceMax);
  return [
    for (var i = 0; i < count; i++)
      DateTime(first.year, first.month, first.day + 7 * (i ~/ pace) + 6),
  ];
}

/// The chapters in reading order: by number, then by title.
List<StudyChapter> sortStudyChapters(Iterable<StudyChapter> chapters) {
  final sorted = chapters.toList();
  sorted.sort((a, b) {
    final byNumber = a.number.compareTo(b.number);
    return byNumber != 0 ? byNumber : a.title.compareTo(b.title);
  });
  return sorted;
}

/// The first chapter in reading order that the member has not marked read, or null when
/// every chapter is read. [chapters] must already be in reading order.
StudyChapter? nextUnreadChapter(
  List<StudyChapter> chapters,
  Set<String> readChapterIds,
) {
  for (final chapter in chapters) {
    if (!readChapterIds.contains(chapter.id)) return chapter;
  }
  return null;
}

/// Whether a chapter is past its due day and not yet read, counted on dates only.
bool isChapterOverdue(
  StudyChapter chapter, {
  required bool read,
  required DateTime today,
}) {
  final due = chapter.dueOn;
  if (read || due == null) return false;
  final dueDay = DateTime(due.year, due.month, due.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  return dueDay.isBefore(todayDay);
}

/// The guide questions as an editor saves them: trimmed, blanks dropped, and at most the
/// limit a chapter can carry.
List<String> cleanGuideQuestions(Iterable<String> raw) => [
      for (final question in raw)
        if (question.trim().isNotEmpty) question.trim(),
    ].take(StudyChapter.guideMax).toList();

/// Whether a chapter's page range is valid: both pages or neither, each within the book, and
/// the last page not before the first.
bool validPageRange(int? from, int? to) {
  if (from == null && to == null) return true;
  if (from == null || to == null) return false;
  return from >= 1 && to >= from && to <= StudyChapter.pageMax;
}

/// Whether a chapter number is one the book can have.
bool validChapterNumber(int number) =>
    number >= 1 && number <= StudyChapter.numberMax;
