import '../models/study_assignment_models.dart';

/// Whether a viewer sees an assignment: every shown one, plus one still waiting for an admin when the viewer
/// added it or is an admin.
bool canSeeAssignment({
  required StudyAssignment assignment,
  required String viewerEmail,
  required bool isAdmin,
}) =>
    assignment.shown ||
    isAdmin ||
    (assignment.createdByEmail.isNotEmpty &&
        assignment.createdByEmail == viewerEmail);

/// The assignments a viewer sees, in the order they were given.
List<StudyAssignment> visibleStudyAssignments({
  required List<StudyAssignment> assignments,
  required String viewerEmail,
  required bool isAdmin,
}) =>
    [
      for (final assignment in assignments)
        if (canSeeAssignment(
          assignment: assignment,
          viewerEmail: viewerEmail,
          isAdmin: isAdmin,
        ))
          assignment,
    ];

/// Whether a viewer may change or remove an assignment: the member who added it, or an admin.
bool canEditAssignment({
  required String createdByEmail,
  required String viewerEmail,
  required bool isAdmin,
}) =>
    isAdmin || (createdByEmail.isNotEmpty && createdByEmail == viewerEmail);

/// The assignments in the order to work through them: the ones not yet finished first, the nearest due day
/// first, the undated ones after the dated ones, and the newest first among the undated. A just-written
/// assignment whose time is not yet known comes first, as a problem does.
List<StudyAssignment> sortStudyAssignments(
  List<StudyAssignment> assignments, {
  Set<String> finished = const {},
}) {
  final sorted = [...assignments];
  sorted.sort((a, b) {
    final doneA = finished.contains(a.id);
    final doneB = finished.contains(b.id);
    if (doneA != doneB) return doneA ? 1 : -1;
    final dueA = a.dueAt;
    final dueB = b.dueAt;
    if (dueA != null && dueB != null) {
      final byDue = dueA.compareTo(dueB);
      if (byDue != 0) return byDue;
    } else if (dueA != null) {
      return -1;
    } else if (dueB != null) {
      return 1;
    }
    final createdA = a.createdAt;
    final createdB = b.createdAt;
    if (createdA == null && createdB == null) return 0;
    if (createdA == null) return -1;
    if (createdB == null) return 1;
    return createdB.compareTo(createdA);
  });
  return sorted;
}

/// How many of [assignments] the viewer has finished.
int finishedAssignmentCount({
  required List<StudyAssignment> assignments,
  required Set<String> finished,
}) =>
    [
      for (final assignment in assignments)
        if (finished.contains(assignment.id)) assignment,
    ].length;

/// The number of whole calendar days from [now] to the due day, so a day due today is 0 and a day that has
/// passed is negative. The due day is compared on its date only.
int daysUntilAssignmentDue({required DateTime dueAt, required DateTime now}) {
  final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final today = DateTime(now.year, now.month, now.day);
  return due.difference(today).inDays;
}

/// How near an assignment's due day is at a given time.
enum AssignmentDue { none, upcoming, dueSoon, dueToday, overdue }

/// How many days before its due day an assignment counts as due soon.
const int kAssignmentDueSoonDays = 3;

/// The due state of an assignment at [now]: due soon in the days before its day, due today on it, and overdue
/// once that day has passed. An assignment with no due day has none.
AssignmentDue assignmentDueState(
    {required DateTime? dueAt, required DateTime now}) {
  if (dueAt == null) return AssignmentDue.none;
  final days = daysUntilAssignmentDue(dueAt: dueAt, now: now);
  if (days < 0) return AssignmentDue.overdue;
  if (days == 0) return AssignmentDue.dueToday;
  if (days <= kAssignmentDueSoonDays) return AssignmentDue.dueSoon;
  return AssignmentDue.upcoming;
}

/// The days an assignment is due on, as dates at midnight, for the group calendar. An undated assignment has none.
Set<DateTime> assignmentDueDays(Iterable<StudyAssignment> assignments) => {
      for (final assignment in assignments)
        if (assignment.dueAt != null)
          DateTime(assignment.dueAt!.year, assignment.dueAt!.month,
              assignment.dueAt!.day),
    };

/// The assignments due today or later, the nearest day first and then by title, for the calendar's list.
List<StudyAssignment> upcomingStudyAssignments(
  Iterable<StudyAssignment> assignments, {
  required DateTime now,
}) {
  final upcoming = [
    for (final assignment in assignments)
      if (assignment.dueAt != null &&
          daysUntilAssignmentDue(dueAt: assignment.dueAt!, now: now) >= 0)
        assignment,
  ];
  upcoming.sort((a, b) {
    final byDay = DateTime(a.dueAt!.year, a.dueAt!.month, a.dueAt!.day)
        .compareTo(DateTime(b.dueAt!.year, b.dueAt!.month, b.dueAt!.day));
    return byDay != 0 ? byDay : a.title.compareTo(b.title);
  });
  return upcoming;
}
