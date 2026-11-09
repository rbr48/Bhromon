// A study or book club's shared book list and reading plan, stored under
// tours/{id}/study_books and tours/{id}/reading_sessions. A member proposes a book, and an
// admin lists it or declines it. Anyone on the list moves a book along its statuses. A
// book's creator or an admin changes its details or removes it, and the same goes for a
// session. An admin splits a listed book into chapters; members mark them read, and a
// session can name the chapters it covers.

import 'study_session_models.dart';

/// Where a book stands in the group's reading.
enum StudyBookStatus {
  toRead,
  reading,
  finished;

  /// An unknown stored status reads as "to read".
  static StudyBookStatus fromName(Object? raw) => StudyBookStatus.values
      .firstWhere((s) => s.name == raw, orElse: () => StudyBookStatus.toRead);
}

/// Whether a book is on the group's list. A member's book is proposed until an admin lists
/// it or declines it.
enum StudyBookApproval {
  proposed,
  listed,
  declined;

  /// A book with no stored approval was listed before approvals existed, so it reads as
  /// listed.
  static StudyBookApproval fromName(Object? raw) => StudyBookApproval.values
      .firstWhere((a) => a.name == raw, orElse: () => StudyBookApproval.listed);
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
    this.approval = StudyBookApproval.listed,
    this.declineNote = '',
  });

  final String id;
  final String title;

  /// Who wrote it, or empty when nobody has said.
  final String author;

  /// What the group should know about the book. Empty when there is nothing to add.
  final String notes;

  final StudyBookStatus status;

  /// The member who added or proposed the book. Only they, or an admin, change its details
  /// or remove it.
  final String createdByEmail;

  /// The member who set the current status. Null until someone sets it.
  final String? statusByEmail;

  /// Whether the book is proposed, listed or declined.
  final StudyBookApproval approval;

  /// Why an admin declined the proposal. Empty unless it was declined with a note.
  final String declineNote;

  bool get isProposed => approval == StudyBookApproval.proposed;
  bool get isListed => approval == StudyBookApproval.listed;
  bool get isDeclined => approval == StudyBookApproval.declined;

  /// The fields written when a book is added. Empty optional text is stored as null, so
  /// the rules see the same shape every time.
  Map<String, dynamic> toFields() => {
        'title': title,
        'author': author.isEmpty ? null : author,
        'notes': notes.isEmpty ? null : notes,
        'status': status.name,
        'statusByEmail': statusByEmail,
        'createdByEmail': createdByEmail,
        'approval': approval.name,
        'declineNote': declineNote.isEmpty ? null : declineNote,
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
      approval: StudyBookApproval.fromName(map['approval']),
      declineNote: (map['declineNote'] as String?)?.trim() ?? '',
    );
  }
}

/// How many members said they would read a proposed book, and whether the signed-in member
/// is one of them.
class StudyVoteTally {
  const StudyVoteTally({required this.count, required this.mine});

  final int count;

  /// Whether the signed-in member has voted.
  final bool mine;

  static const none = StudyVoteTally(count: 0, mine: false);
}

/// One chapter of a book: its number, title, page range, due date and the questions a
/// member can think about while reading it. An admin sets chapters.
class StudyChapter {
  const StudyChapter({
    required this.id,
    required this.number,
    required this.title,
    this.pageFrom,
    this.pageTo,
    this.dueOn,
    this.guide = const [],
  });

  /// The most guide questions a chapter can carry.
  static const int guideMax = 5;

  /// The highest chapter number and page a book can have.
  static const int numberMax = 500;
  static const int pageMax = 5000;

  final String id;

  /// The chapter's place in the book, from 1 up.
  final int number;

  final String title;

  /// The first and last page of the chapter, or null when the book's pages are not set.
  final int? pageFrom;
  final int? pageTo;

  /// The day the group should have read the chapter by. Null when it has no date.
  final DateTime? dueOn;

  /// Questions to think about while reading. A thread can start from each one later.
  final List<String> guide;

  /// The fields written for a chapter. Empty optional values are stored as null.
  Map<String, dynamic> toFields() => {
        'number': number,
        'title': title,
        'pageFrom': pageFrom,
        'pageTo': pageTo,
        'dueOn': dueOn,
        'guide': guide,
      };

  /// Reads one stored chapter. Returns null when it has no usable number or title, so a
  /// damaged chapter does not break the list. Guide questions past the limit are dropped.
  static StudyChapter? fromMap(String id, Map<String, dynamic> map) {
    final number = (map['number'] as num?)?.toInt();
    final title = (map['title'] as String?)?.trim() ?? '';
    if (number == null || number < 1 || title.isEmpty) return null;
    final due = map['dueOn'];
    final rawGuide = map['guide'];
    final guide = rawGuide is List
        ? [
            for (final question in rawGuide)
              if (question is String && question.trim().isNotEmpty)
                question.trim(),
          ].take(guideMax).toList()
        : <String>[];
    return StudyChapter(
      id: id,
      number: number,
      title: title,
      pageFrom: (map['pageFrom'] as num?)?.toInt(),
      pageTo: (map['pageTo'] as num?)?.toInt(),
      dueOn: due is DateTime ? due : null,
      guide: guide,
    );
  }
}

/// A member's read mark on a chapter. A counted mark joins the group total when its member
/// chooses; an uncounted mark is private to its member.
class StudyReadMark {
  const StudyReadMark({
    required this.chapterId,
    this.readAt,
    this.counted = false,
  });

  final String chapterId;

  /// When the chapter was marked. Null only until the server has the time.
  final DateTime? readAt;

  /// Whether the mark counts towards the group total.
  final bool counted;

  /// Reads a stored mark. A mark that exists is a read, even before its time arrives.
  static StudyReadMark fromMap(String chapterId, Map<String, dynamic> map) {
    final at = map['readAt'];
    return StudyReadMark(
      chapterId: chapterId,
      readAt: at is DateTime ? at : null,
      counted: map['counted'] == true,
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
    this.chapterIds = const [],
    this.place = '',
    this.notes = '',
    this.createdByEmail = '',
    this.agenda = '',
    this.link = '',
    this.timerStartsAt,
    this.timerSeconds,
    this.recap,
  });

  /// The most chapters a session can name.
  static const int chapterMax = 10;

  final String id;

  /// What to read or cover, such as "Chapters 1 to 3".
  final String title;

  /// When the session starts, on the device's clock.
  final DateTime startsAt;

  /// The book of the session, or null when it is not about one book.
  final String? bookId;

  /// The chapters of the book the session covers. Empty when none are named.
  final List<String> chapterIds;

  /// Where the group meets. Empty when it is not decided.
  final String place;

  final String notes;

  /// The member who planned the session. Only they, or an admin, change or remove it.
  final String createdByEmail;

  /// What the session covers, for the members who come. Empty when it is not written.
  final String agenda;

  /// The meeting link, which must be https. Empty when there is none.
  final String link;

  /// When the shared focus timer started, or null when it is not running.
  final DateTime? timerStartsAt;

  /// How long the focus timer runs, in seconds. Null when the session has no timer.
  final int? timerSeconds;

  /// The recap written after the session, or null when there is none.
  final StudySessionRecap? recap;

  /// The fields a member writes when adding a session. [startsAt] is written as a
  /// timestamp by the repository.
  Map<String, dynamic> toFields() => {
        'title': title,
        'bookId': bookId,
        'chapterIds': chapterIds.isEmpty ? null : chapterIds,
        'agenda': agenda.isEmpty ? null : agenda,
        'link': link.isEmpty ? null : link,
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
    final rawChapters = map['chapterIds'];
    return ReadingSession(
      id: id,
      title: title,
      startsAt: startsAt,
      bookId: _nonEmpty(map['bookId'] as String?),
      chapterIds: rawChapters is List
          ? [
              for (final chapter in rawChapters)
                if (chapter is String && chapter.isNotEmpty) chapter,
            ].take(chapterMax).toList()
          : const [],
      place: (map['place'] as String?)?.trim() ?? '',
      notes: (map['notes'] as String?)?.trim() ?? '',
      agenda: (map['agenda'] as String?)?.trim() ?? '',
      link: (map['link'] as String?)?.trim() ?? '',
      timerStartsAt: map['timerStartsAt'] is DateTime
          ? map['timerStartsAt'] as DateTime
          : null,
      timerSeconds: (map['timerSeconds'] as num?)?.toInt(),
      recap: StudySessionRecap.fromMap(map['recap']),
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
    );
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
