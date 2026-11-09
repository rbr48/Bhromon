/// What a weekly challenge asks a member to do. Each task is counted from the member's own work,
/// so nobody sees another member's progress.
enum ChallengeKind {
  /// Work out problems: each problem the member submitted or edited this week counts once.
  problems,

  /// Check findings: each finding the member confirmed or challenged this week counts once.
  findings,

  /// Review flashcards: each card reviewed this week counts once. The count stays on the device.
  cards;

  /// The kind with [name], or null for a name the app does not know.
  static ChallengeKind? fromName(Object? raw) {
    for (final kind in ChallengeKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }
}

/// The limits of a weekly challenge.
class StudyChallengeLimits {
  const StudyChallengeLimits._();

  /// The fewest tasks a challenge may ask for.
  static const int targetMin = 1;

  /// The most tasks a challenge may ask for in one week.
  static const int targetMax = 20;
}

/// A subject's challenge for one week: a kind of task and how many of it. Its id is the week's
/// Monday as yyyy-MM-dd, so a week has one challenge.
class StudyChallenge {
  const StudyChallenge({
    required this.weekKey,
    required this.kind,
    required this.target,
    this.setByEmail = '',
    this.setAt,
  });

  /// The week's Monday as yyyy-MM-dd. It is the challenge's document id.
  final String weekKey;

  final ChallengeKind kind;

  /// How many tasks of [kind] the week asks for.
  final int target;

  /// The admin who set the challenge, or empty when the stored value is not there.
  final String setByEmail;

  /// When it was set. Null only until the server has the time.
  final DateTime? setAt;

  /// Reads one stored challenge. Returns null when its kind is not one the app knows, or its
  /// target is out of range.
  static StudyChallenge? fromMap(String weekKey, Map<String, dynamic> map) {
    final kind = ChallengeKind.fromName(map['kind']);
    final target = map['target'];
    if (kind == null || target is! num) return null;
    final count = target.toInt();
    if (count < StudyChallengeLimits.targetMin ||
        count > StudyChallengeLimits.targetMax) {
      return null;
    }
    final setAt = map['setAt'];
    return StudyChallenge(
      weekKey: weekKey,
      kind: kind,
      target: count,
      setByEmail: (map['setByEmail'] as String?)?.trim() ?? '',
      setAt: setAt is DateTime ? setAt : null,
    );
  }

  /// The fields an admin writes. The admin's email and the time are added when it is saved.
  Map<String, dynamic> toFields() => {
        'kind': kind.name,
        'target': target,
      };
}
