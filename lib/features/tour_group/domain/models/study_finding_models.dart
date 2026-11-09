// Shared findings: a result a member has reached, with how it was checked. Other members
// confirm or challenge it. A finding is stored under a subject as .../findings/{id}, and each
// member's check of it as .../findings/{id}/checks/{email}. The counts on the finding move in
// the same batch as a check, which firestore.rules enforces.

/// What a member says about a finding.
enum FindingVerdict {
  confirm,
  challenge;

  /// The verdict with [name], or null for a name the app does not know.
  static FindingVerdict? fromName(Object? raw) {
    for (final verdict in FindingVerdict.values) {
      if (verdict.name == raw) return verdict;
    }
    return null;
  }
}

/// The limits on a finding's words and a check's note. The rules enforce the same numbers.
class StudyFindingLimits {
  const StudyFindingLimits._();

  /// The longest result a finding can carry.
  static const int textMax = 1000;

  /// The longest method a finding can carry.
  static const int methodMax = 500;

  /// The longest note a check can carry.
  static const int noteMax = 300;
}

/// A finding posted in a subject's findings module.
class StudyFinding {
  const StudyFinding({
    required this.id,
    required this.text,
    required this.method,
    this.createdByEmail = '',
    this.createdAt,
    this.confirmCount = 0,
    this.challengeCount = 0,
    this.shown = true,
    this.pinned = false,
  });

  final String id;

  /// The result, in the member's words.
  final String text;

  /// How the result was checked, so that others can check it the same way.
  final String method;

  final String createdByEmail;

  /// When it was posted. Null only while the server's clock has not yet given a time.
  final DateTime? createdAt;

  /// How many members confirmed it.
  final int confirmCount;

  /// How many members challenged it.
  final int challengeCount;

  /// Whether members can see it. A finding waiting for an admin is not shown yet.
  final bool shown;

  /// Whether an admin has pinned it to the top.
  final bool pinned;

  /// How many members have checked it, either way.
  int get checkCount => confirmCount + challengeCount;

  /// Reads one stored finding. Returns null when it has no result or no method, so a damaged
  /// finding does not break the list. Counts never read below zero.
  static StudyFinding? fromMap(String id, Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    final method = (map['method'] as String?)?.trim() ?? '';
    if (text.isEmpty || method.isEmpty) return null;
    final created = map['createdAt'];
    return StudyFinding(
      id: id,
      text: text,
      method: method,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
      confirmCount: _count(map['confirmCount']),
      challengeCount: _count(map['challengeCount']),
      shown: map['shown'] != false,
      pinned: map['pinned'] == true,
    );
  }

  static int _count(Object? raw) {
    final n = (raw as num?)?.toInt() ?? 0;
    return n < 0 ? 0 : n;
  }
}

/// One member's check of a finding: confirmed or challenged, with an optional note.
class StudyFindingCheck {
  const StudyFindingCheck({
    required this.email,
    required this.verdict,
    this.note = '',
    this.createdAt,
  });

  /// The member who made the check. It is also the check's document id.
  final String email;

  final FindingVerdict verdict;

  /// Why the member challenged it, or what they checked. Empty when there is none.
  final String note;

  final DateTime? createdAt;

  /// Reads one stored check. Returns null when its verdict is not one the app knows.
  static StudyFindingCheck? fromMap(String email, Map<String, dynamic> map) {
    final verdict = FindingVerdict.fromName(map['verdict']);
    if (verdict == null) return null;
    final created = map['createdAt'];
    return StudyFindingCheck(
      email: email,
      verdict: verdict,
      note: (map['note'] as String?)?.trim() ?? '',
      createdAt: created is DateTime ? created : null,
    );
  }
}
