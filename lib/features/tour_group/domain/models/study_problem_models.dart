// Problem solving: problems a study group works through. A problem is posted in a subject's problems
// module, and it has a reference solution that an admin writes and that opens to members at a release
// time. Each member submits their own working, and sees and reviews other members' working only after
// they have submitted their own. Stored under study_subjects/{id}/problems/{problemId}; the reference
// solution is .../reference/solution, each member's working is .../solutions/{email}, and a review of a
// working is .../solutions/{email}/reviews/{reviewer}. The review counts on the working move in the
// same batch as a review (firestore.rules).

/// The verdict a reviewer gives a working.
enum WorkVerdict {
  right,
  gap;

  /// The verdict with [name], or null for a name the app does not know.
  static WorkVerdict? fromName(Object? raw) {
    for (final verdict in WorkVerdict.values) {
      if (verdict.name == raw) return verdict;
    }
    return null;
  }
}

/// The limits on a problem's words, a working, a reference solution and a review note. The rules
/// enforce the same numbers.
class StudyProblemLimits {
  const StudyProblemLimits._();

  /// The longest statement of a problem.
  static const int textMax = 1000;

  /// The longest title of a problem.
  static const int titleMax = 120;

  /// The longest reference solution.
  static const int referenceMax = 4000;

  /// The longest working a member submits.
  static const int workMax = 4000;

  /// The longest note a review can carry.
  static const int noteMax = 300;
}

/// A problem posted in a subject's problems module.
class StudyProblem {
  const StudyProblem({
    required this.id,
    required this.text,
    this.title = '',
    this.createdByEmail = '',
    this.createdAt,
    this.releaseAt,
    this.shown = true,
    this.pinned = false,
    this.reportCount = 0,
    this.reportedAt,
  });

  final String id;

  /// The statement of the problem.
  final String text;

  /// A short heading. Empty when there is none.
  final String title;

  final String createdByEmail;

  /// When it was posted. Null only while the server's clock has not yet given a time.
  final DateTime? createdAt;

  /// When the reference solution opens to members. Null while no release time is set.
  final DateTime? releaseAt;

  /// Whether members can see it. A problem waiting for an admin is not shown yet, and a reported one is
  /// hidden from members until an admin restores it.
  final bool shown;

  /// Whether an admin has pinned it to the top.
  final bool pinned;

  /// How many members have reported the problem.
  final int reportCount;

  /// When the first report was made, and the problem was hidden. Null when it has never been reported
  /// or an admin has restored it.
  final DateTime? reportedAt;

  /// Whether the problem is reported and waiting for an admin's decision.
  bool get isReported => reportedAt != null;

  /// Reads one stored problem. Returns null when it has no statement, so a damaged problem does not
  /// break the list.
  static StudyProblem? fromMap(String id, Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final created = map['createdAt'];
    final release = map['releaseAt'];
    final reported = map['reportedAt'];
    return StudyProblem(
      id: id,
      text: text,
      title: (map['title'] as String?)?.trim() ?? '',
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
      releaseAt: release is DateTime ? release : null,
      shown: map['shown'] != false,
      pinned: map['pinned'] == true,
      reportCount: _count(map['reportCount']),
      reportedAt: reported is DateTime ? reported : null,
    );
  }

  static int _count(Object? raw) {
    final n = (raw as num?)?.toInt() ?? 0;
    return n < 0 ? 0 : n;
  }
}

/// The reference solution of a problem: an admin's answer, which carries the admin's name as the
/// mark that an admin reviewed it.
class StudyReferenceSolution {
  const StudyReferenceSolution({
    required this.text,
    this.reviewedByEmail = '',
    this.updatedAt,
  });

  final String text;

  /// The admin who wrote and reviewed the reference solution.
  final String reviewedByEmail;

  final DateTime? updatedAt;

  /// Reads the stored reference solution. Returns null when it has no text.
  static StudyReferenceSolution? fromMap(Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final updated = map['updatedAt'];
    return StudyReferenceSolution(
      text: text,
      reviewedByEmail: (map['reviewedByEmail'] as String?) ?? '',
      updatedAt: updated is DateTime ? updated : null,
    );
  }
}

/// A member's own working on a problem, with how many reviews it has had of each verdict. The
/// member's email is the working's document id, so [solverEmail] is that id.
class StudyProblemSolution {
  const StudyProblemSolution({
    required this.solverEmail,
    required this.text,
    this.createdAt,
    this.updatedAt,
    this.rightCount = 0,
    this.gapCount = 0,
    this.reportCount = 0,
    this.reportedAt,
  });

  final String solverEmail;

  /// The working, in the member's words.
  final String text;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// How many reviewers found the working right.
  final int rightCount;

  /// How many reviewers found a gap in the working.
  final int gapCount;

  /// How many members have reported the working.
  final int reportCount;

  /// When the first report was made, and the working was hidden from the other members. Null when it
  /// has never been reported or an admin has restored it.
  final DateTime? reportedAt;

  /// How many reviews the working has had, either way.
  int get reviewCount => rightCount + gapCount;

  /// Whether the working is reported and hidden from members other than its author and the admins.
  bool get isReported => reportedAt != null;

  /// Reads one stored working. Returns null when it has no text. Counts never read below zero.
  static StudyProblemSolution? fromMap(
      String solverEmail, Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final created = map['createdAt'];
    final updated = map['updatedAt'];
    final reported = map['reportedAt'];
    return StudyProblemSolution(
      solverEmail: solverEmail,
      text: text,
      createdAt: created is DateTime ? created : null,
      updatedAt: updated is DateTime ? updated : null,
      rightCount: _count(map['rightCount']),
      gapCount: _count(map['gapCount']),
      reportCount: _count(map['reportCount']),
      reportedAt: reported is DateTime ? reported : null,
    );
  }

  static int _count(Object? raw) {
    final n = (raw as num?)?.toInt() ?? 0;
    return n < 0 ? 0 : n;
  }
}

/// A reviewer's review of a working: right or a gap, with an optional note.
class StudyWorkReview {
  const StudyWorkReview({
    required this.reviewerEmail,
    required this.verdict,
    this.note = '',
    this.createdAt,
  });

  /// The reviewer. It is also the review's document id.
  final String reviewerEmail;

  final WorkVerdict verdict;

  /// What the reviewer found, when there is a gap. Empty when there is none.
  final String note;

  final DateTime? createdAt;

  /// Reads one stored review. Returns null when its verdict is not one the app knows.
  static StudyWorkReview? fromMap(
      String reviewerEmail, Map<String, dynamic> map) {
    final verdict = WorkVerdict.fromName(map['verdict']);
    if (verdict == null) return null;
    final created = map['createdAt'];
    return StudyWorkReview(
      reviewerEmail: reviewerEmail,
      verdict: verdict,
      note: (map['note'] as String?)?.trim() ?? '',
      createdAt: created is DateTime ? created : null,
    );
  }
}
