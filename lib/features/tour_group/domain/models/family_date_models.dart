// A date a family keeps: a birthday, an anniversary, a bill, a school day or a
// medicine time. Stored under `tours/{id}/family_dates`. The reminder job
// (`sendFamilyDateReminders`) moves its next day on; the app computes the same
// rules in `family_date_rules.dart`.

// What a family date is about. Each kind has its own emoji.
enum FamilyDateKind {
  birthday('🎂'),
  anniversary('💍'),
  bill('🧾'),
  school('🎒'),
  medicine('💊'),
  custom('📅');

  const FamilyDateKind(this.emoji);

  final String emoji;

  /// An unknown stored kind reads as a custom date, so nothing is lost.
  static FamilyDateKind fromName(Object? raw) => FamilyDateKind.values
      .firstWhere((k) => k.name == raw, orElse: () => FamilyDateKind.custom);
}

/// How often a family date comes round. An unknown stored value reads as once,
/// so an unreadable repeat never reminds people again and again.
enum FamilyRecurrence {
  once,
  monthly,
  yearly;

  static FamilyRecurrence fromName(Object? raw) => FamilyRecurrence.values
      .firstWhere((r) => r.name == raw, orElse: () => FamilyRecurrence.once);
}

/// The reminder choices the app offers, in days before the date.
const List<int> kFamilyRemindChoices = [0, 1, 3, 7];

/// The longest a reminder may come before a date. The rules allow up to this.
const int kFamilyRemindMaxDays = 30;

final RegExp _dayKeyPattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

/// The day `YYYY-MM-DD` as a date, or null when it is not a real calendar day
/// (30 February, or a month of 13).
DateTime? parseFamilyDay(String? raw) {
  if (raw == null || !_dayKeyPattern.hasMatch(raw)) return null;
  final year = int.parse(raw.substring(0, 4));
  final month = int.parse(raw.substring(5, 7));
  final day = int.parse(raw.substring(8, 10));
  if (month < 1 || month > 12) return null;
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

class FamilyDate {
  const FamilyDate({
    required this.id,
    required this.title,
    required this.kind,
    required this.recurrence,
    required this.startOn,
    required this.nextOn,
    required this.remindDays,
    this.remindOn,
    this.note = '',
    this.createdByEmail = '',
  });

  final String id;
  final String title;
  final FamilyDateKind kind;
  final FamilyRecurrence recurrence;

  /// The first day of the date, as `YYYY-MM-DD`.
  final String startOn;

  /// The day the reminder job last left as next. Shown only as a fallback: the
  /// list works out the next day from [startOn] and today.
  final String nextOn;

  /// How many days before the date the reminder goes out.
  final int remindDays;

  /// The day the next reminder is due, or null when none is.
  final String? remindOn;

  final String note;

  /// The member who added the date. Only they, or an admin, change it.
  final String createdByEmail;

  Map<String, dynamic> toMap() => {
        'title': title,
        'kind': kind.name,
        'recurrence': recurrence.name,
        'startOn': startOn,
        'nextOn': nextOn,
        'remindDays': remindDays,
        'remindOn': remindOn,
        'note': note,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored date. Returns null when it has no usable title or start day,
  /// so a damaged record does not break the list.
  static FamilyDate? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final startOn = map['startOn'] as String?;
    if (startOn == null || title.isEmpty || parseFamilyDay(startOn) == null) {
      return null;
    }
    final nextOn = map['nextOn'] as String?;
    final remindOn = map['remindOn'] as String?;
    final remind = map['remindDays'];
    final days = remind is num ? remind.toInt() : kFamilyRemindChoices.first;
    return FamilyDate(
      id: id,
      title: title,
      kind: FamilyDateKind.fromName(map['kind']),
      recurrence: FamilyRecurrence.fromName(map['recurrence']),
      startOn: startOn,
      nextOn: parseFamilyDay(nextOn) != null ? nextOn! : startOn,
      remindDays: days < 0
          ? 0
          : (days > kFamilyRemindMaxDays ? kFamilyRemindMaxDays : days),
      remindOn: parseFamilyDay(remindOn) != null ? remindOn : null,
      note: (map['note'] as String?) ?? '',
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
    );
  }
}
