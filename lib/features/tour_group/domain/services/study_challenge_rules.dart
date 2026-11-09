import 'study_progress_rules.dart' show studyWeekStart;

// The weekly challenge of a subject. A week runs from its Monday at local midnight to the next Monday.
// The week's Monday is the challenge's id, so a week has one challenge.

/// The Monday that starts the challenge week of [day].
DateTime challengeWeekStart(DateTime day) => studyWeekStart(day);

/// The id of the week that starts on [weekStart]: its Monday as yyyy-MM-dd.
String challengeWeekKey(DateTime weekStart) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${weekStart.year.toString().padLeft(4, '0')}-'
      '${two(weekStart.month)}-${two(weekStart.day)}';
}

/// The Monday a week id stands for, or null when the id is not a real date in yyyy-MM-dd form.
DateTime? challengeWeekStartOf(String weekKey) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(weekKey);
  if (match == null) return null;
  final parsed = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  // A date such as 2026-02-30 rolls over to March, so it does not read back as the same id.
  return challengeWeekKey(parsed) == weekKey ? parsed : null;
}

/// The moment the week that starts on [weekStart] ends: the next Monday at local midnight.
DateTime challengeWeekEnd(DateTime weekStart) => DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 7,
    );

/// Whether [at] falls inside the week that starts on [weekStart]. A missing time is outside it.
bool inChallengeWeek(DateTime weekStart, DateTime? at) =>
    at != null &&
    !at.isBefore(weekStart) &&
    at.isBefore(challengeWeekEnd(weekStart));

/// How many of [times] fall inside the week that starts on [weekStart].
int countInChallengeWeek(Iterable<DateTime?> times, DateTime weekStart) {
  var count = 0;
  for (final at in times) {
    if (inChallengeWeek(weekStart, at)) count++;
  }
  return count;
}

/// Whether a member may join, or leave, the challenge of [weekStart] at [now]: only while its week
/// runs. The same window is the one an admin may set a challenge in.
bool challengeIsOpen({required DateTime weekStart, required DateTime now}) =>
    !now.isBefore(weekStart) && now.isBefore(challengeWeekEnd(weekStart));

/// The tasks done so far, never more than the target and never less than none.
int challengeDone(int count, int target) {
  if (count <= 0) return 0;
  return count > target ? target : count;
}

/// Whether the tasks done reach the target.
bool challengeMet(int count, int target) => count >= target;
