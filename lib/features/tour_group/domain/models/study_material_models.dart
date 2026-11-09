// Study materials: a note, a file, a link or a recording a member files under a book and, when it helps, a
// chapter. A material waits for an admin unless the group publishes directly, and a report hides it at once.
// Stored under tours/{id}/study_materials/{id}; its reports and opens are subcollections.

/// What a material is.
enum StudyMaterialKind {
  file,
  image,
  audio,
  video,
  link,
  note;

  static StudyMaterialKind fromName(Object? raw) => StudyMaterialKind.values
      .firstWhere((k) => k.name == raw, orElse: () => StudyMaterialKind.note);

  /// Whether the material is a file uploaded to the study folder.
  bool get isUpload =>
      this == file || this == image || this == audio || this == video;
}

/// Where a material is: waiting for an admin, shown to the group, or hidden after a report.
enum StudyMaterialStatus {
  pending,
  published,
  hidden;

  static StudyMaterialStatus fromName(Object? raw) =>
      StudyMaterialStatus.values.firstWhere((s) => s.name == raw,
          orElse: () => StudyMaterialStatus.pending);
}

/// The reasons a member can give for reporting a material. Stored by name.
enum StudyMaterialReportReason {
  copyright,
  exam,
  personal,
  wrong,
  other;

  static StudyMaterialReportReason fromName(Object? raw) =>
      StudyMaterialReportReason.values.firstWhere((r) => r.name == raw,
          orElse: () => StudyMaterialReportReason.other);
}

/// A material filed under a book.
class StudyMaterial {
  const StudyMaterial({
    required this.id,
    required this.title,
    required this.kind,
    required this.bookId,
    this.chapterId,
    this.url,
    this.fileName,
    this.sizeBytes,
    this.body,
    this.status = StudyMaterialStatus.pending,
    this.reportCount = 0,
    this.reportedAt,
    this.createdByEmail = '',
    this.createdAt,
    this.replacesId,
  });

  static const int titleMax = 120;
  static const int noteMax = 20000;
  static const int linkMax = 2000;

  final String id;
  final String title;
  final StudyMaterialKind kind;
  final String bookId;

  /// The chapter the material is filed under, or null when it is about the whole book.
  final String? chapterId;

  /// The address of an uploaded file or of a link. Null for a note.
  final String? url;

  /// The name the file had on the uploader's device.
  final String? fileName;

  /// The size of an uploaded file in bytes. Null for a link or a note.
  final int? sizeBytes;

  /// The text of a note. Null for the others.
  final String? body;

  final StudyMaterialStatus status;

  /// How many members reported the material.
  final int reportCount;

  /// When the first report was made. The admins have 24 hours from this to decide.
  final DateTime? reportedAt;

  /// The member who filed the material. Only they, or an admin, change or remove it.
  final String createdByEmail;

  /// When it was filed. Null only until the server has the time.
  final DateTime? createdAt;

  /// The material this one is a newer version of, or null. Uploads never overwrite.
  final String? replacesId;

  bool get isReported => reportCount > 0;
  bool get isPublished => status == StudyMaterialStatus.published;

  /// The fields written when a material is filed. A member always confirms their rights, and the counts
  /// start at zero. The status is decided by the caller, from the group's policy.
  Map<String, dynamic> toFields({required StudyMaterialStatus status}) => {
        'title': title,
        'kind': kind.name,
        'bookId': bookId,
        'chapterId': chapterId,
        'url': url,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'body': body,
        'status': status.name,
        'rightsConfirmed': true,
        'reportCount': 0,
        'createdByEmail': createdByEmail,
        'replacesId': replacesId,
      };

  /// Reads one stored material. Returns null when it has no title or book, so a damaged record does not
  /// break the list.
  static StudyMaterial? fromMap(String id, Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final bookId = (map['bookId'] as String?)?.trim() ?? '';
    if (title.isEmpty || bookId.isEmpty) return null;
    final created = map['createdAt'];
    final reported = map['reportedAt'];
    final size = map['sizeBytes'];
    return StudyMaterial(
      id: id,
      title: title,
      kind: StudyMaterialKind.fromName(map['kind']),
      bookId: bookId,
      chapterId: _nonEmpty(map['chapterId'] as String?),
      url: _nonEmpty(map['url'] as String?),
      fileName: _nonEmpty(map['fileName'] as String?),
      sizeBytes: size is num ? size.toInt() : null,
      body: _nonEmpty(map['body'] as String?),
      status: StudyMaterialStatus.fromName(map['status']),
      reportCount: (map['reportCount'] as num?)?.toInt() ?? 0,
      reportedAt: reported is DateTime ? reported : null,
      createdByEmail: (map['createdByEmail'] as String?) ?? '',
      createdAt: created is DateTime ? created : null,
      replacesId: _nonEmpty(map['replacesId'] as String?),
    );
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
