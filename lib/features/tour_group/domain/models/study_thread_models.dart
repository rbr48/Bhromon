// Discussions on a book. A member starts a thread, usually on one chapter. Replies form a flat
// list in time order. A reply can be marked helpful once by each other member, and reported
// once. The asker accepts one reply, and an admin can accept on their behalf. Stored under
// tours/{id}/study_books/{id}/threads and .../threads/{id}/replies.

/// A question or a point about a book, started by a member.
class StudyThread {
  const StudyThread({
    required this.id,
    required this.title,
    required this.body,
    this.pageRef = '',
    this.chapterId,
    this.createdByEmail = '',
    this.createdAt,
    this.pinned = false,
    this.locked = false,
    this.acceptedReplyId,
  });

  static const int titleMax = 120;
  static const int bodyMax = 2000;
  static const int pageRefMax = 20;

  final String id;
  final String title;
  final String body;

  /// A page reference such as "p. 34". Empty when there is none.
  final String pageRef;

  /// The chapter the thread belongs to, or null when it is about the whole book.
  final String? chapterId;

  /// The member who started the thread. Only they, or an admin, delete it.
  final String createdByEmail;

  /// When it was started. Null only until the server has the time.
  final DateTime? createdAt;

  /// Whether an admin has pinned it to the top.
  final bool pinned;

  /// Whether an admin has locked it, so it takes no more replies.
  final bool locked;

  /// The reply the asker accepted, or null when none is accepted.
  final String? acceptedReplyId;

  bool get isAnswered => acceptedReplyId != null;

  /// The fields written when a thread is started. Empty optional values are stored as null.
  Map<String, dynamic> toFields() => {
        'title': title,
        'body': body,
        'pageRef': pageRef.isEmpty ? null : pageRef,
        'chapterId': chapterId,
        'createdByEmail': createdByEmail,
        'pinned': pinned,
        'locked': locked,
        'acceptedReplyId': acceptedReplyId,
      };

  /// Reads one stored thread. Returns null when it has no title or body, so a damaged thread
  /// does not break the list.
  static StudyThread? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final body = (map['body'] as String?)?.trim() ?? '';
    if (title.isEmpty || body.isEmpty) return null;
    final created = map['createdAt'];
    return StudyThread(
      id: id,
      title: title,
      body: body,
      pageRef: (map['pageRef'] as String?)?.trim() ?? '',
      chapterId: _nonEmpty(map['chapterId'] as String?),
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
      pinned: map['pinned'] == true,
      locked: map['locked'] == true,
      acceptedReplyId: _nonEmpty(map['acceptedReplyId'] as String?),
    );
  }
}

/// A reply to a thread. Its helpful votes and reports are kept in subcollections; the counts
/// here move with them.
class StudyReply {
  const StudyReply({
    required this.id,
    required this.text,
    this.createdByEmail = '',
    this.createdAt,
    this.helpfulCount = 0,
    this.reportCount = 0,
  });

  static const int textMax = 1000;

  final String id;
  final String text;

  /// The member who wrote the reply. Only they, or an admin, delete it.
  final String createdByEmail;

  /// When it was written. Null only until the server has the time.
  final DateTime? createdAt;

  /// How many members found the reply helpful.
  final int helpfulCount;

  /// How many members reported the reply.
  final int reportCount;

  bool get isReported => reportCount > 0;

  /// The fields written when a reply is added. The counts start at zero.
  Map<String, dynamic> toFields() => {
        'text': text,
        'createdByEmail': createdByEmail,
        'helpfulCount': 0,
        'reportCount': 0,
      };

  /// Reads one stored reply. Returns null when it has no text.
  static StudyReply? fromMap(String id, Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final created = map['createdAt'];
    return StudyReply(
      id: id,
      text: text,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
      helpfulCount: (map['helpfulCount'] as num?)?.toInt() ?? 0,
      reportCount: (map['reportCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The reasons a member can give for reporting a reply. Stored by name.
enum StudyReportReason {
  wrong,
  unclear,
  spam,
  other;

  static StudyReportReason fromName(Object? raw) => StudyReportReason.values
      .firstWhere((r) => r.name == raw, orElse: () => StudyReportReason.other);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
