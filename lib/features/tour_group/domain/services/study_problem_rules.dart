import '../models/study_problem_models.dart';

/// Whether a reference solution has opened at [now]: a release time is set, and it has come.
bool referenceOpen({required DateTime? releaseAt, required DateTime now}) =>
    releaseAt != null && !now.isBefore(releaseAt);

/// Whether a viewer may read the reference solution. An admin always may. A member may once the
/// problem is shown to them and its reference has opened.
bool canSeeReference({
  required StudyProblem problem,
  required bool isAdmin,
  required DateTime now,
}) =>
    isAdmin ||
    (problem.shown && referenceOpen(releaseAt: problem.releaseAt, now: now));

/// Whether a viewer may review a peer's working: it is not their own, they have not reviewed this one
/// yet, and they have submitted their own working. An admin reviews without a working of their own. A
/// member who has reviewed it withdraws the review first to change it.
bool canReviewWork({
  required String solverEmail,
  required String viewerEmail,
  required bool viewerHasWork,
  required bool viewerHasReview,
  bool viewerIsAdmin = false,
}) =>
    solverEmail != viewerEmail &&
    (viewerHasWork || viewerIsAdmin) &&
    !viewerHasReview;

/// How a working stands, from its reviews.
enum WorkStanding { unreviewed, rightSoFar, gapsFound, mixed }

/// The standing of a working. It is unreviewed until someone reviews it, right so far when right
/// reviews outnumber gaps, gaps found when gaps outnumber them, and mixed when they are level.
WorkStanding workStanding(StudyProblemSolution work) {
  if (work.reviewCount == 0) return WorkStanding.unreviewed;
  if (work.rightCount > work.gapCount) return WorkStanding.rightSoFar;
  if (work.gapCount > work.rightCount) return WorkStanding.gapsFound;
  return WorkStanding.mixed;
}

/// Whether the reference of a problem has a release time, and whether that time has come.
enum ReferenceStatus { noRelease, scheduled, open }

/// The release status of a problem's reference solution at [now].
ReferenceStatus referenceStatus({
  required StudyProblem problem,
  required DateTime now,
}) {
  if (problem.releaseAt == null) return ReferenceStatus.noRelease;
  return referenceOpen(releaseAt: problem.releaseAt, now: now)
      ? ReferenceStatus.open
      : ReferenceStatus.scheduled;
}

/// The problems a viewer sees: every shown problem, plus one still waiting for an admin when the
/// viewer wrote it or is an admin.
List<StudyProblem> visibleStudyProblems({
  required List<StudyProblem> problems,
  required String viewerEmail,
  required bool isAdmin,
}) =>
    [
      for (final problem in problems)
        if (problem.shown || isAdmin || problem.createdByEmail == viewerEmail)
          problem,
    ];

/// Problems in reading order: pinned first, then the newest. A problem whose time is not yet
/// known comes first, since it was just written.
List<StudyProblem> sortStudyProblems(List<StudyProblem> problems) {
  final sorted = [...problems];
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  });
  return sorted;
}
