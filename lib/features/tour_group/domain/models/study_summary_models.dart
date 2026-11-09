// A chapter summary: a shared page for one chapter, written as revisions. Any member adds a revision in their own
// name. Nothing is overwritten, so an earlier revision can always be restored as a new one, and an admin pins the
// revision the group should read (tours/{id}/study_books/{id}/chapters/{id}/summaries/{revisionId}).

/// The limits a summary revision is checked against, as firestore.rules checks them.
class StudySummaryLimits {
  const StudySummaryLimits._();

  static const int textMax = 4000;
  static const int nameMax = 80;
}

/// One revision of a chapter summary. A revision is never changed after it is written.
class StudySummaryRevision {
  const StudySummaryRevision({
    required this.id,
    required this.text,
    required this.editorEmail,
    this.editorName = '',
    this.createdAt,
    this.restoredFromId,
  });

  final String id;

  /// The summary itself, up to [StudySummaryLimits.textMax] characters.
  final String text;

  /// The member who wrote the revision. Stands in for a member who has left.
  final String editorEmail;

  /// The editor's name at the time, shown next to the revision. Empty when the name was not known.
  final String editorName;

  /// When the revision was written. Set by the server, so null until it is confirmed.
  final DateTime? createdAt;

  /// The revision this one restores, when it is a restore. Null for an ordinary revision.
  final String? restoredFromId;

  /// The fields written for a new revision. The time is added by the repository, as the server's time.
  Map<String, dynamic> toFields() => {
        'text': text,
        'editorEmail': editorEmail,
        'editorName': editorName,
        'restoredFromId': restoredFromId,
      };

  /// Reads one stored revision. Returns null when it has no text, so a damaged revision does not break
  /// the list.
  static StudySummaryRevision? fromMap(String id, Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final created = map['createdAt'];
    final restored = map['restoredFromId'];
    return StudySummaryRevision(
      id: id,
      text: text,
      editorEmail: (map['editorEmail'] as String?) ?? '',
      editorName: (map['editorName'] as String?)?.trim() ?? '',
      createdAt: created is DateTime ? created : null,
      restoredFromId:
          restored is String && restored.isNotEmpty ? restored : null,
    );
  }
}
