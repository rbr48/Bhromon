import '../models/study_summary_models.dart';

// The progress of a study group: a member's own streak, the group's totals as counts, and the revision of a
// chapter summary that the group reads. Nothing here reads or writes the database.

/// A member's streak in weeks: the run they are on now, and the best run they have had.
class StudyStreak {
  const StudyStreak({required this.current, required this.best});

  final int current;
  final int best;
}

/// The Monday that starts the week of [day], at local midnight.
DateTime studyWeekStart(DateTime day) {
  final local = DateTime(day.year, day.month, day.day);
  final back = (local.weekday - DateTime.monday) % 7;
  return DateTime(local.year, local.month, local.day - back);
}

DateTime _nextWeek(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

DateTime _previousWeek(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day - 7);

/// The streak from the days a member did something to study: a read mark, an answer, a flashcard review or a
/// quiz. A week counts when it holds at least one such day. The run counts through this week, and a run that
/// stopped last week still counts until this week is over, so a member is not penalised before the week ends.
/// A missed week ends the run quietly, and the best run stays on the record.
StudyStreak studyStreak(Iterable<DateTime> actions, {required DateTime today}) {
  final weeks = {for (final day in actions) studyWeekStart(day)};
  if (weeks.isEmpty) return const StudyStreak(current: 0, best: 0);

  // The run that counts now ends this week, or last week while this week has no action yet.
  final thisWeek = studyWeekStart(today);
  DateTime? end;
  if (weeks.contains(thisWeek)) {
    end = thisWeek;
  } else if (weeks.contains(_previousWeek(thisWeek))) {
    end = _previousWeek(thisWeek);
  }
  var current = 0;
  var week = end;
  while (week != null && weeks.contains(week)) {
    current++;
    week = _previousWeek(week);
  }

  // The best run is the longest stretch of consecutive weeks, the current one included.
  final sorted = weeks.toList()..sort();
  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final weekStart in sorted) {
    run = previous != null && weekStart == _nextWeek(previous) ? run + 1 : 1;
    if (run > best) best = run;
    previous = weekStart;
  }
  return StudyStreak(current: current, best: best);
}

/// The revisions of a chapter, newest first. A revision with no time yet sorts as the oldest.
List<StudySummaryRevision> newestFirst(
    Iterable<StudySummaryRevision> revisions) {
  final list = revisions.toList();
  list.sort((a, b) {
    final first = a.createdAt;
    final second = b.createdAt;
    if (first == null && second == null) return a.id.compareTo(b.id);
    if (first == null) return 1;
    if (second == null) return -1;
    return second.compareTo(first);
  });
  return list;
}

/// What the group reads for a chapter: the revision an admin pinned, or the newest when none is pinned. When the
/// pinned revision is no longer there, or an admin has hidden it, the newest shown one is read. A hidden revision is
/// never read by the group. [pinned] says whether the shown one is the pinned one.
({StudySummaryRevision? revision, bool pinned}) summaryShownToGroup(
  Iterable<StudySummaryRevision> revisions, {
  String? pinnedId,
}) {
  final list = newestFirst(revisions.where((revision) => !revision.hidden));
  if (pinnedId != null) {
    for (final revision in list) {
      if (revision.id == pinnedId) return (revision: revision, pinned: true);
    }
  }
  return (revision: list.isEmpty ? null : list.first, pinned: false);
}

/// The number of questions answered within [withinDays] days of being asked. A question counts when its first
/// answer came no later than that. A question with no answer, or an answer dated before its question, does not.
int questionsAnsweredWithin(
  Iterable<({DateTime asked, DateTime? firstAnswer})> questions, {
  int withinDays = 3,
}) {
  final limit = Duration(days: withinDays);
  var count = 0;
  for (final question in questions) {
    final answer = question.firstAnswer;
    if (answer == null) continue;
    final gap = answer.difference(question.asked);
    if (!gap.isNegative && gap <= limit) count++;
  }
  return count;
}

/// What the group sees: counts only, never a name or a score. [chaptersCounted] is how many members counted each
/// chapter as read. [quizTakers] is how many members took each quiz. [questionsAnswered] is how many questions were
/// answered within three days, out of [questionsAsked].
class StudyGroupTotals {
  const StudyGroupTotals({
    required this.chaptersCounted,
    required this.quizTakers,
    required this.questionsAnswered,
    required this.questionsAsked,
  });

  final Map<String, int> chaptersCounted;
  final Map<String, int> quizTakers;
  final int questionsAnswered;
  final int questionsAsked;
}

/// Adds up the group's totals. [countedReadFlags] holds, for each chapter, the counted flag of every read mark the
/// member can see on it. Only the counted ones add to the total: an uncounted read is private to its member.
/// [takersByQuiz] is the taker count each quiz keeps. [questions] are the threads, each with its first answer.
StudyGroupTotals groupTotals({
  required Map<String, Iterable<bool>> countedReadFlags,
  required Map<String, int> takersByQuiz,
  required Iterable<({DateTime asked, DateTime? firstAnswer})> questions,
  int withinDays = 3,
}) {
  final chapters = {
    for (final entry in countedReadFlags.entries)
      entry.key: entry.value.where((counted) => counted).length,
  };
  final list = questions.toList();
  return StudyGroupTotals(
    chaptersCounted: chapters,
    quizTakers: Map.unmodifiable(takersByQuiz),
    questionsAnswered: questionsAnsweredWithin(list, withinDays: withinDays),
    questionsAsked: list.length,
  );
}

/// A member's own record on a book. Only they see it.
class StudyMyRecord {
  const StudyMyRecord({
    required this.chaptersRead,
    required this.quizzesTaken,
    required this.cardsDue,
    required this.questionsAsked,
    required this.answersGiven,
  });

  final int chaptersRead;
  final int quizzesTaken;
  final int cardsDue;
  final int questionsAsked;
  final int answersGiven;
}
