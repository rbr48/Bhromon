import '../models/study_finding_models.dart';
import '../models/study_problem_models.dart';
import '../models/study_subject_models.dart';
import '../models/study_today_models.dart';
import 'study_finding_rules.dart' show canCheckFinding;
import 'study_problem_rules.dart'
    show ProblemSetDue, problemSetDueState, visibleStudyProblems, workedCount;
import 'study_subject_rules.dart' show daysUntilExam;

/// Exam mode starts this many days before a subject's exam.
const int kExamModeDays = 14;

/// Whether exam mode is on at [daysLeft] days before the exam: the last [kExamModeDays] days, with
/// the exam day itself included. Null, or a day that has passed, is not exam mode.
bool examModeOn(int? daysLeft) =>
    daysLeft != null && daysLeft >= 0 && daysLeft <= kExamModeDays;

/// The lines of the Today card, in the order they can appear.
enum TodayCardLine { exam, deadline, problemSet, findings, cards, challenge }

/// The order of the Today card's lines. Outside exam mode the next deadline leads, then the problem set due soon, the
/// findings, the cards due and the challenge. In exam mode the exam comes first and then the cards due, the deadline
/// and the problem set, so revision comes before the other work.
List<TodayCardLine> todayCardLineOrder({required bool examMode}) => examMode
    ? const [
        TodayCardLine.exam,
        TodayCardLine.cards,
        TodayCardLine.deadline,
        TodayCardLine.problemSet,
        TodayCardLine.findings,
        TodayCardLine.challenge,
      ]
    : const [
        TodayCardLine.exam,
        TodayCardLine.deadline,
        TodayCardLine.problemSet,
        TodayCardLine.findings,
        TodayCardLine.cards,
        TodayCardLine.challenge,
      ];

/// The problem set the Today card shows for a viewer: the set due soon (see [problemSetDueState]) that has a problem the
/// viewer can see and has not worked yet. [total] counts the problems of the set the viewer can see, and [worked] the
/// ones among them the viewer has submitted a working for.
class DueProblemSet {
  const DueProblemSet({
    required this.set,
    required this.total,
    required this.worked,
  });

  final StudyProblemSet set;
  final int total;
  final int worked;
}

/// The nearest set that is due soon and that the viewer still has to work on, or null when there is none. [workedIds]
/// holds the ids of the problems the viewer has submitted a working for. A set due sooner comes first; two that are due
/// the same day come in the order of their names.
DueProblemSet? nextDueProblemSet({
  required List<StudyProblemSet> sets,
  required List<StudyProblem> problems,
  required Set<String> workedIds,
  required String viewerEmail,
  required bool isAdmin,
  required DateTime now,
}) {
  final visible = visibleStudyProblems(
    problems: problems,
    viewerEmail: viewerEmail,
    isAdmin: isAdmin,
  );
  DueProblemSet? next;
  for (final set in sets) {
    if (problemSetDueState(dueAt: set.dueAt, now: now) !=
        ProblemSetDue.dueSoon) {
      continue;
    }
    final inSet = [
      for (final problem in visible)
        if (problem.setId == set.id) problem,
    ];
    if (inSet.isEmpty) continue;
    final worked = workedCount(problems: inSet, workedIds: workedIds);
    if (worked == inSet.length) continue;
    final candidate = DueProblemSet(
      set: set,
      total: inSet.length,
      worked: worked,
    );
    if (next == null || _dueSooner(candidate.set, next.set)) {
      next = candidate;
    }
  }
  return next;
}

/// Whether [a] is due before [b], or on the same day with a name that comes first. Both sets have a due date here.
bool _dueSooner(StudyProblemSet a, StudyProblemSet b) {
  final dueA = a.dueAt!;
  final dueB = b.dueAt!;
  if (dueA.isBefore(dueB)) return true;
  if (dueB.isBefore(dueA)) return false;
  return a.title.compareTo(b.title) < 0;
}

/// The findings a viewer may check and has not checked yet: the ones waiting for their check.
/// [checkedIds] holds the ids of the findings the viewer has checked.
int findingsWaitingForCheck({
  required List<StudyFinding> findings,
  required String viewerEmail,
  required Set<String> checkedIds,
}) {
  var waiting = 0;
  for (final finding in findings) {
    if (canCheckFinding(
      finding: finding,
      viewerEmail: viewerEmail,
      hasOwnCheck: checkedIds.contains(finding.id),
    )) {
      waiting++;
    }
  }
  return waiting;
}

/// The next deadline on or after [today]: the earliest due day, and between chapters due the same
/// day, the one whose title comes first. Null when nothing is due from today on. A chapter due
/// before today is overdue, and is not the next deadline.
StudyDeadline? nextStudyDeadline(
    List<StudyDeadline> deadlines, DateTime today) {
  final from = _dayOf(today);
  StudyDeadline? next;
  for (final deadline in deadlines) {
    final due = _dayOf(deadline.dueOn);
    if (due.isBefore(from)) continue;
    if (next == null) {
      next = deadline;
      continue;
    }
    final nextDue = _dayOf(next.dueOn);
    if (due.isBefore(nextDue) ||
        (due == nextDue &&
            deadline.chapterTitle.compareTo(next.chapterTitle) < 0)) {
      next = deadline;
    }
  }
  return next;
}

/// The subject whose exam is nearest from [today], among the exams still to come (today included). Null when no
/// subject has one. Two exams on the same day keep the order of [subjects].
StudySubject? nearestExam(List<StudySubject> subjects, DateTime today) {
  StudySubject? nearest;
  int? nearestDays;
  for (final subject in subjects) {
    final exam = subject.examDate;
    if (exam == null) continue;
    final days = daysUntilExam(exam, today);
    if (days < 0) continue;
    if (nearestDays == null || days < nearestDays) {
      nearest = subject;
      nearestDays = days;
    }
  }
  return nearest;
}

/// The local midnight of [value]'s day.
DateTime _dayOf(DateTime value) => DateTime(value.year, value.month, value.day);
