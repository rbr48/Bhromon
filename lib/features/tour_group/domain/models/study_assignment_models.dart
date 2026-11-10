// An assignment a study group has to do: what it asks for, the day it is due, a link to the brief,
// and whether members see it yet. It is stored under a subject as
// tours/{id}/study_subjects/{id}/assignments/{assignmentId}. Each member's finished assignments are
// kept in one document of their own (see the repository's assignment marks).

/// One assignment a subject's group has to do.
class StudyAssignment {
  const StudyAssignment({
    required this.id,
    required this.title,
    this.details = '',
    this.url = '',
    this.dueAt,
    this.shown = true,
    this.createdByEmail = '',
    this.createdAt,
  });

  final String id;
  final String title;

  /// What the assignment asks for. Empty when there is nothing to add.
  final String details;

  /// A link to the brief or the submission page, always https. Empty when there is none.
  final String url;

  /// The day it is due, on the date only. Null when no day is set.
  final DateTime? dueAt;

  /// Whether members can see it. An assignment that waits for an admin is not shown yet.
  final bool shown;

  /// The member who added the assignment.
  final String createdByEmail;

  /// When it was added. Null only while the server's clock has not yet given a time.
  final DateTime? createdAt;

  /// Reads one stored assignment. Returns null when it has no title, so a damaged one does not
  /// break the list. The repository turns stored timestamps into dates first.
  static StudyAssignment? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    final due = map['dueAt'];
    final created = map['createdAt'];
    return StudyAssignment(
      id: id,
      title: title,
      details: (map['details'] as String?)?.trim() ?? '',
      url: (map['url'] as String?)?.trim() ?? '',
      dueAt: due is DateTime ? due : null,
      shown: map['shown'] != false,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
    );
  }
}
