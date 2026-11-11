// A shared shopping or to-do item in a family circle, stored under
// tours/{id}/family_tasks. Anyone in the circle adds an item and ticks it off, and the
// tick records who made it and when. Its creator or an admin changes its text, its kind
// or its assignee, and removes it.

/// Whether an item is something to buy or something to do.
enum FamilyTaskKind {
  shopping,
  todo;

  /// An unknown stored kind reads as something to buy.
  static FamilyTaskKind fromName(Object? raw) => FamilyTaskKind.values
      .firstWhere((k) => k.name == raw, orElse: () => FamilyTaskKind.shopping);
}

/// The most items one member may add on a Dhaka day. The rules hold the same limit
/// (familyTaskCounted in firestore.rules), so a batch past it is refused.
const int familyTaskDailyLimit = 200;

/// Above this many items the list says it is long and offers to clear what is finished.
const int familyTaskLongListAt = 500;

/// Thrown when the signed-in member has already added [familyTaskDailyLimit] items today.
class FamilyTaskDailyLimitException implements Exception {
  const FamilyTaskDailyLimitException();

  @override
  String toString() => 'FamilyTaskDailyLimitException: daily limit reached';
}

class FamilyTask {
  const FamilyTask({
    required this.id,
    required this.title,
    required this.kind,
    this.done = false,
    this.assigneeEmail,
    this.doneByEmail,
    this.createdByEmail = '',
    this.createdAt,
    this.doneAt,
  });

  final String id;

  /// The item's text. Empty only for an item saved before blank text was refused. It
  /// shows as untitled, so its creator or an admin can still remove it.
  final String title;
  final FamilyTaskKind kind;
  final bool done;

  /// Whose item it is, or null for anyone in the circle.
  final String? assigneeEmail;

  /// Who ticked the item. Null while it is open.
  final String? doneByEmail;

  /// The member who added the item. Only they, or an admin, edit or remove it.
  final String createdByEmail;

  /// When the item was added, or null for an item saved before the time was recorded.
  final DateTime? createdAt;

  /// When the item was ticked, or null while it is open, or for one ticked before the
  /// time was recorded.
  final DateTime? doneAt;

  bool get isUntitled => title.isEmpty;

  /// The fields a member writes when they add an item. The creation time is added
  /// by the repository as a server time, so it is not part of these fields.
  Map<String, dynamic> toFields() => {
        'title': title,
        'kind': kind.name,
        'done': done,
        'assigneeEmail': assigneeEmail,
        'doneByEmail': doneByEmail,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored item. A damaged item still reads, so the list shows it and its
  /// creator or an admin can remove it. [map] holds its times as [DateTime]s.
  static FamilyTask fromMap(String id, Map<String, dynamic> map) {
    return FamilyTask(
      id: id,
      title: _text(map['title'])?.trim() ?? '',
      kind: FamilyTaskKind.fromName(map['kind']),
      done: map['done'] == true,
      assigneeEmail: _text(map['assigneeEmail']),
      doneByEmail: _text(map['doneByEmail']),
      createdByEmail: _text(map['createdByEmail']) ?? '',
      createdAt: _time(map['createdAt']),
      doneAt: _time(map['doneAt']),
    );
  }

  static String? _text(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw : null;

  static DateTime? _time(Object? raw) => raw is DateTime ? raw : null;
}
