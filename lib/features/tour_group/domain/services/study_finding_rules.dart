import '../models/study_finding_models.dart';

/// How a finding stands, from the checks made on it.
enum FindingStanding { unchecked, confirmed, challenged, contested }

/// The standing of a finding. It is unchecked until someone checks it, confirmed when
/// confirmations outnumber challenges, challenged when challenges outnumber them, and contested
/// when they are level.
FindingStanding findingStanding(StudyFinding finding) {
  if (finding.checkCount == 0) return FindingStanding.unchecked;
  if (finding.confirmCount > finding.challengeCount) {
    return FindingStanding.confirmed;
  }
  if (finding.challengeCount > finding.confirmCount) {
    return FindingStanding.challenged;
  }
  return FindingStanding.contested;
}

/// Whether a viewer may check a finding: a shown finding that is not their own, which they have
/// not checked yet. A member who has checked it withdraws the check first to change it.
bool canCheckFinding({
  required StudyFinding finding,
  required String viewerEmail,
  required bool hasOwnCheck,
}) =>
    finding.shown && finding.createdByEmail != viewerEmail && !hasOwnCheck;

/// Whether a viewer may report a finding: a shown finding that the viewer did not write. A report hides
/// the finding from everyone but its author and the admins, until an admin restores it.
bool canReportFinding({
  required StudyFinding finding,
  required String viewerEmail,
}) =>
    finding.shown && finding.createdByEmail != viewerEmail;

/// The findings an admin must decide, because they were reported and are hidden: the oldest report first.
List<StudyFinding> reportedFindingsForReview(Iterable<StudyFinding> findings) {
  final reported = [
    for (final finding in findings)
      if (finding.isReported && !finding.shown) finding,
  ];
  reported.sort((a, b) => a.reportedAt!.compareTo(b.reportedAt!));
  return reported;
}

/// The findings a viewer sees: every shown finding, plus one still waiting for an admin when
/// the viewer wrote it or is an admin.
List<StudyFinding> visibleStudyFindings({
  required List<StudyFinding> findings,
  required String viewerEmail,
  required bool isAdmin,
}) =>
    [
      for (final finding in findings)
        if (finding.shown || isAdmin || finding.createdByEmail == viewerEmail)
          finding,
    ];

/// Findings in reading order: pinned first, then the most checked, then the newest. A finding
/// whose time is not yet known comes first, since it was just written.
List<StudyFinding> sortStudyFindings(List<StudyFinding> findings) {
  final sorted = [...findings];
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.checkCount != b.checkCount) {
      return b.checkCount.compareTo(a.checkCount);
    }
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta == null && tb == null) return 0;
    if (ta == null) return -1;
    if (tb == null) return 1;
    return tb.compareTo(ta);
  });
  return sorted;
}
