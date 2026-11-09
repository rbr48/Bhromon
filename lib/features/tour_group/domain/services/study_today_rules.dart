import '../models/study_finding_models.dart';
import '../models/study_subject_models.dart';
import '../models/study_today_models.dart';
import 'study_finding_rules.dart' show canCheckFinding;
import 'study_subject_rules.dart' show daysUntilExam;

/// Exam mode starts this many days before a subject's exam.
const int kExamModeDays = 14;

/// Whether exam mode is on at [daysLeft] days before the exam: the last [kExamModeDays] days, with
/// the exam day itself included. Null, or a day that has passed, is not exam mode.
bool examModeOn(int? daysLeft) =>
    daysLeft != null && daysLeft >= 0 && daysLeft <= kExamModeDays;

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
