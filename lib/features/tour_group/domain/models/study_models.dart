// A study or book club's shared book list and reading plan, stored under
// tours/{id}/study_books and tours/{id}/reading_sessions. Any member adds a book or a
// session, and anyone moves a book along its statuses. A book's creator or an admin
// changes its details or removes it, and the same goes for a session.

/// Where a book stands in the group's reading.
enum StudyBookStatus {
  toRead,
  reading,
  finished;

  /// An unknown stored status reads as "to read".
  static StudyBookStatus fromName(Object? raw) => StudyBookStatus.values
      .firstWhere((s) => s.name == raw, orElse: () => StudyBookStatus.toRead);
}

/// A book the group reads or has read.
class StudyBook {
  const StudyBook({
    required this.id,
    required this.title,
    this.author = '',
    this.notes = '',
    this.status = StudyBookStatus.toRead,
    this.createdByEmail = '',
    this.statusByEmail,
  });

  final String id;
  final String title;

  /// Who wrote it, or empty when nobody has said.
  final String author;

  /// What the group should know about the book. Empty when there is nothing to add.
  final String notes;

  final StudyBookStatus status;

  /// The member who added the book. Only they, or an admin, change its details or
  /// remove it.
  final String createdByEmail;

  /// The member who set the current status. Null until someone sets it.
  final String? statusByEmail;

  /// The fields a member writes when adding a book. Empty optional text is stored as
  /// null, so the rules see the same shape every time.
  Map<String, dynamic> toFields() => {
        'title': title,
        'author': author.isEmpty ? null : author,
        'notes': notes.isEmpty ? null : notes,
        'status': status.name,
        'statusByEmail': statusByEmail,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored book. Returns null when it has no title, so a damaged book does
  /// not break the list.
  static StudyBook? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    return StudyBook(
      id: id,
      title: title,
      author: (map['author'] as String?)?.trim() ?? '',
      notes: (map['notes'] as String?)?.trim() ?? '',
      status: StudyBookStatus.fromName(map['status']),
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      statusByEmail: _nonEmpty(map['statusByEmail'] as String?),
    );
  }
}

/// A meeting or a stretch of reading the group plans: what to read or cover, and when.
class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.title,
    required this.startsAt,
    this.bookId,
    this.place = '',
    this.notes = '',
    this.createdByEmail = '',
  });

  final String id;

  /// What to read or cover, such as "Chapters 1 to 3".
  final String title;

  /// When the session starts, on the device's clock.
  final DateTime startsAt;

  /// The book of the session, or null when it is not about one book.
  final String? bookId;

  /// Where the group meets. Empty when it is not decided.
  final String place;

  final String notes;

  /// The member who planned the session. Only they, or an admin, change or remove it.
  final String createdByEmail;

  /// The fields a member writes when adding a session. [startsAt] is written as a
  /// timestamp by the repository.
  Map<String, dynamic> toFields() => {
        'title': title,
        'bookId': bookId,
        'startsAt': startsAt,
        'place': place.isEmpty ? null : place,
        'notes': notes.isEmpty ? null : notes,
        'createdByEmail': createdByEmail,
      };

  /// Reads one stored session. The repository turns a stored timestamp into a
  /// [DateTime] first. Returns null when the session has no title or no start, so a
  /// damaged session does not break the plan.
  static ReadingSession? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final startsAt = map['startsAt'];
    if (title.isEmpty || startsAt is! DateTime) return null;
    return ReadingSession(
      id: id,
      title: title,
      startsAt: startsAt,
      bookId: _nonEmpty(map['bookId'] as String?),
      place: (map['place'] as String?)?.trim() ?? '',
      notes: (map['notes'] as String?)?.trim() ?? '',
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
    );
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
