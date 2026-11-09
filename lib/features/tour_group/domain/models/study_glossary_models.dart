// The glossary of a study book: short terms with a definition and a chapter. Members propose a term, and an
// admin approves it. Approved terms are the shared source for flashcards (tours/{id}/study_books/{id}/glossary).

/// The limits a glossary term is checked against, as firestore.rules checks them.
class StudyGlossaryLimits {
  const StudyGlossaryLimits._();

  static const int termMax = 80;
  static const int definitionMax = 500;
}

/// One glossary term.
class StudyGlossaryTerm {
  const StudyGlossaryTerm({
    required this.id,
    required this.term,
    required this.definition,
    this.chapterId,
    this.approved = false,
    this.createdByEmail = '',
  });

  final String id;
  final String term;
  final String definition;

  /// The chapter the term belongs to, or null when it is not tied to one.
  final String? chapterId;

  /// Whether an admin has approved the term. Only approved terms feed flashcards.
  final bool approved;

  /// The member who proposed the term.
  final String createdByEmail;

  /// The fields written for a term. An empty chapter is stored as null.
  Map<String, dynamic> toFields() => {
        'term': term,
        'definition': definition,
        'chapterId': chapterId,
        'approved': approved,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored term. Returns null when it has no term or definition, so a damaged term does not
  /// break the list.
  static StudyGlossaryTerm? fromMap(String id, Map<String, dynamic> map) {
    final term = (map['term'] as String?)?.trim() ?? '';
    final definition = (map['definition'] as String?)?.trim() ?? '';
    if (term.isEmpty || definition.isEmpty) return null;
    final chapterId = (map['chapterId'] as String?)?.trim();
    return StudyGlossaryTerm(
      id: id,
      term: term,
      definition: definition,
      chapterId: (chapterId == null || chapterId.isEmpty) ? null : chapterId,
      approved: map['approved'] == true,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
    );
  }
}
