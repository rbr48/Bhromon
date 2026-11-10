// A study group's subjects: what the group studies. An admin adds a subject and turns on its
// modules, and members use them. A subject is stored under tours/{id}/study_subjects, its
// modules under .../modules, and its posts under .../tips, .../suggestions, .../findings and .../problems
// (the findings and the problems have their own models in study_finding_models.dart and
// study_problem_models.dart). A subject
// reuses the approval of a book: a member proposes it, and an admin lists or declines it.

import 'study_models.dart';

/// The activities a subject can hold. Only the live modules can be turned on yet; the rest
/// are listed so an admin can see what is coming.
enum StudyModuleKey {
  tips,
  suggestions,
  discussion,
  findings,
  problems,
  papers,
  plan,
  glossary,
  assignments,
  challenges,
  flashcards,
  quizzes;

  /// Whether the module shows the book its subject studies: its discussion, glossary, flashcards,
  /// quizzes, or the reading sessions planned for it. The subject must name a book for these.
  bool get isBookModule =>
      this == StudyModuleKey.discussion ||
      this == StudyModuleKey.glossary ||
      this == StudyModuleKey.flashcards ||
      this == StudyModuleKey.quizzes ||
      this == StudyModuleKey.plan;

  /// Whether an admin sets who may post in the module. A book module follows its own rules instead,
  /// so it has no policy to set.
  bool get hasPostPolicy => !isBookModule;

  /// The module with [name], or null for a name the app does not know.
  static StudyModuleKey? fromName(Object? raw) {
    for (final key in StudyModuleKey.values) {
      if (key.name == raw) return key;
    }
    return null;
  }
}

/// Who may post in a module.
enum StudyPostPolicy {
  /// Every member posts, and the post is shown at once.
  members,

  /// Only admins post.
  admins,

  /// Members post, and an admin shows each post before others see it.
  approval;

  /// An unknown stored policy reads as every member.
  static StudyPostPolicy fromName(Object? raw) => StudyPostPolicy.values
      .firstWhere((p) => p.name == raw, orElse: () => StudyPostPolicy.members);
}

/// One module's settings in a subject.
class StudyModuleSettings {
  const StudyModuleSettings({
    required this.key,
    required this.enabled,
    required this.name,
    required this.postPolicy,
  });

  final StudyModuleKey key;

  /// Whether members can see and use the module.
  final bool enabled;

  /// The name the group sees, which an admin may change.
  final String name;

  final StudyPostPolicy postPolicy;

  /// The fields an admin writes for the module.
  Map<String, dynamic> toFields() => {
        'enabled': enabled,
        'name': name,
        'postPolicy': postPolicy.name,
      };

  /// Reads one stored module. Returns null when it has no name, so a damaged module reads as
  /// off.
  static StudyModuleSettings? fromMap(
    StudyModuleKey key,
    Map<String, dynamic> map,
  ) {
    final name = (map['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return StudyModuleSettings(
      key: key,
      enabled: map['enabled'] == true,
      name: name,
      postPolicy: StudyPostPolicy.fromName(map['postPolicy']),
    );
  }
}

/// A subject the group studies. An admin archives a listed subject to hide it from members; its
/// content stays, and an admin restores it.
class StudySubject {
  const StudySubject({
    required this.id,
    required this.title,
    this.code = '',
    this.description = '',
    this.examDate,
    this.approval = StudyBookApproval.listed,
    this.declineNote = '',
    this.createdByEmail = '',
    this.archived = false,
    this.bookId,
  });

  final String id;
  final String title;

  /// The course code, such as "PHY 101". Empty when there is none.
  final String code;

  /// The listed book the subject studies. Its book modules (discussion, glossary, flashcards,
  /// quizzes and the reading plan) open this book. Null when the subject names none.
  final String? bookId;

  /// What the subject covers. Empty when there is nothing to add.
  final String description;

  /// The day of the next exam, on the date only. Null when it is not set.
  final DateTime? examDate;

  /// Whether the subject is proposed, listed or declined.
  final StudyBookApproval approval;

  /// Why an admin declined the proposal. Empty unless it was declined with a note.
  final String declineNote;

  /// The member who added or proposed the subject.
  final String createdByEmail;

  /// Whether an admin has archived the subject. Only a listed subject can be archived. Members
  /// do not see an archived subject, and nobody adds to it until an admin restores it.
  final bool archived;

  bool get isListed => approval == StudyBookApproval.listed;
  bool get isProposed => approval == StudyBookApproval.proposed;
  bool get isDeclined => approval == StudyBookApproval.declined;

  /// The fields written when a subject is added. Empty optional text is stored as null.
  Map<String, dynamic> toFields() => {
        'title': title,
        'code': code.isEmpty ? null : code,
        'description': description.isEmpty ? null : description,
        'examDate': examDate,
        'approval': approval.name,
        'declineNote': declineNote.isEmpty ? null : declineNote,
        'createdByEmail': createdByEmail,
        'bookId': bookId,
      };

  /// Reads one stored subject. The repository turns stored timestamps into dates first.
  /// Returns null when the subject has no title, so a damaged subject does not break the list.
  static StudySubject? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    final exam = map['examDate'];
    final book = (map['bookId'] as String?)?.trim() ?? '';
    return StudySubject(
      id: id,
      title: title,
      code: (map['code'] as String?)?.trim() ?? '',
      description: (map['description'] as String?)?.trim() ?? '',
      examDate: exam is DateTime ? exam : null,
      approval: StudyBookApproval.fromName(map['approval']),
      declineNote: (map['declineNote'] as String?)?.trim() ?? '',
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      archived: map['archived'] == true,
      bookId: book.isEmpty ? null : book,
    );
  }
}

/// A tip or a suggestion posted in a subject's module.
class StudyPost {
  const StudyPost({
    required this.id,
    required this.text,
    this.title = '',
    this.url = '',
    this.createdByEmail = '',
    this.createdAt,
    this.helpfulCount = 0,
    this.shown = true,
    this.pinned = false,
  });

  final String id;

  /// What the post says: the tip, or why a suggestion helps.
  final String text;

  /// A short heading. Empty when there is none.
  final String title;

  /// A link to a resource, always https. Empty when there is none.
  final String url;

  final String createdByEmail;

  /// When it was posted. Null only while the server's clock has not yet given a time.
  final DateTime? createdAt;

  /// How many members marked it helpful.
  final int helpfulCount;

  /// Whether members can see it. A post waiting for an admin is not shown yet.
  final bool shown;

  /// Whether an admin has pinned it to the top.
  final bool pinned;

  /// Reads one stored post. Returns null when it has no text.
  static StudyPost? fromMap(String id, Map<String, dynamic> map) {
    final text = (map['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final created = map['createdAt'];
    return StudyPost(
      id: id,
      text: text,
      title: (map['title'] as String?)?.trim() ?? '',
      url: (map['url'] as String?)?.trim() ?? '',
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
      helpfulCount: (map['helpfulCount'] as num?)?.toInt() ?? 0,
      shown: map['shown'] != false,
      pinned: map['pinned'] == true,
    );
  }
}
