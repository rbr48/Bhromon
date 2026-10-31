// A shared shopping or to-do item in a family circle, stored under
// tours/{id}/family_tasks. Anyone in the circle ticks it off, and the tick records
// who made it. Its creator or an admin changes its text or removes it.

/// Whether an item is something to buy or something to do.
enum FamilyTaskKind {
  shopping,
  todo;

  /// An unknown stored kind reads as something to buy.
  static FamilyTaskKind fromName(Object? raw) => FamilyTaskKind.values
      .firstWhere((k) => k.name == raw, orElse: () => FamilyTaskKind.shopping);
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
  });

  final String id;
  final String title;
  final FamilyTaskKind kind;
  final bool done;

  /// Whose item it is, or null for anyone in the circle.
  final String? assigneeEmail;

  /// Who ticked the item. Null while it is open.
  final String? doneByEmail;

  /// The member who added the item. Only they, or an admin, edit or remove it.
  final String createdByEmail;

  /// The fields a member writes when adding or editing an item.
  Map<String, dynamic> toFields() => {
        'title': title,
        'kind': kind.name,
        'done': done,
        'assigneeEmail': assigneeEmail,
        'doneByEmail': doneByEmail,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored item. Returns null when it has no text, so a damaged item
  /// does not break the list.
  static FamilyTask? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    final assignee = map['assigneeEmail'] as String?;
    final doneBy = map['doneByEmail'] as String?;
    return FamilyTask(
      id: id,
      title: title,
      kind: FamilyTaskKind.fromName(map['kind']),
      done: map['done'] == true,
      assigneeEmail: assignee == null || assignee.isEmpty ? null : assignee,
      doneByEmail: doneBy == null || doneBy.isEmpty ? null : doneBy,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
    );
  }
}
