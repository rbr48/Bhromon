// A request a resident raises with the committee of a housing society, stored under
// tours/{id}/service_requests. Any member raises one under their own email. The
// committee moves it along open, in progress and resolved, and leaves a note for the
// residents. The author can still correct the words while it is open.

import 'date_codec.dart';

/// The longest title a request can have, and the shortest.
const int kServiceRequestTitleMax = 120;
const int kServiceRequestTitleMin = 3;

/// The longest details a request can carry.
const int kServiceRequestDetailsMax = 1000;

/// The longest note the committee can leave on a request.
const int kServiceRequestNoteMax = 500;

/// What a request is about. Stored by name; the labels are translated in the app.
enum ServiceRequestCategory {
  lift,
  water,
  power,
  security,
  cleaning,
  other;

  /// An unknown stored category reads as other, so a request is never lost.
  static ServiceRequestCategory fromName(Object? raw) =>
      ServiceRequestCategory.values.firstWhere(
        (c) => c.name == raw,
        orElse: () => ServiceRequestCategory.other,
      );
}

/// Where a request stands. Stored under the names in [stored].
enum ServiceRequestStatus {
  open('open'),
  inProgress('in_progress'),
  resolved('resolved');

  const ServiceRequestStatus(this.stored);

  /// The value written to the database.
  final String stored;

  /// An unknown stored status reads as open.
  static ServiceRequestStatus fromStored(Object? raw) =>
      ServiceRequestStatus.values.firstWhere(
        (s) => s.stored == raw,
        orElse: () => ServiceRequestStatus.open,
      );
}

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.title,
    this.details = '',
    this.category = ServiceRequestCategory.other,
    this.status = ServiceRequestStatus.open,
    this.createdByEmail = '',
    this.createdByName = '',
    this.createdAt,
    this.updatedAt,
    this.adminNote = '',
    this.photoUrl,
    this.inProgressAt,
    this.resolvedAt,
    this.resolvedByName,
  });

  final String id;

  /// What the problem is, in a few words.
  final String title;

  /// Where it is, since when, and anything else that helps.
  final String details;

  final ServiceRequestCategory category;
  final ServiceRequestStatus status;

  /// The resident who raised it. Only they, or an admin, may remove it.
  final String createdByEmail;

  /// The resident's name when it was raised, for the list.
  final String createdByName;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The committee's note for the residents: what was done, or what is needed.
  final String adminNote;

  /// Optional photo attachment showing the issue / repair needed.
  final String? photoUrl;

  /// When the status changed to [ServiceRequestStatus.inProgress].
  final DateTime? inProgressAt;

  /// When the status changed to [ServiceRequestStatus.resolved].
  final DateTime? resolvedAt;

  /// Name of the committee member or admin who resolved the issue.
  final String? resolvedByName;

  bool get isOpen => status == ServiceRequestStatus.open;
  bool get isInProgress => status == ServiceRequestStatus.inProgress;
  bool get isResolved => status == ServiceRequestStatus.resolved;

  ServiceRequest copyWith({
    String? title,
    String? details,
    ServiceRequestCategory? category,
    ServiceRequestStatus? status,
    String? adminNote,
    String? photoUrl,
    DateTime? inProgressAt,
    DateTime? resolvedAt,
    String? resolvedByName,
  }) {
    return ServiceRequest(
      id: id,
      title: title ?? this.title,
      details: details ?? this.details,
      category: category ?? this.category,
      status: status ?? this.status,
      createdByEmail: createdByEmail,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      adminNote: adminNote ?? this.adminNote,
      photoUrl: photoUrl ?? this.photoUrl,
      inProgressAt: inProgressAt ?? this.inProgressAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedByName: resolvedByName ?? this.resolvedByName,
    );
  }

  /// The fields an author writes when raising or correcting a request.
  Map<String, dynamic> toTextFields() => {
        'title': title,
        'details': details,
        'category': category.name,
        if (photoUrl != null) 'photoUrl': photoUrl,
      };

  /// Reads one stored request. Returns null when it has no title, so a damaged request
  /// is left out rather than shown blank.
  static ServiceRequest? fromMap(String id, Map<String, dynamic> data) {
    final title = _text(data['title']).trim();
    if (title.isEmpty) return null;
    final photo = _text(data['photoUrl']).trim();
    final resolver = _text(data['resolvedByName']).trim();
    return ServiceRequest(
      id: id,
      title: title,
      details: _text(data['details']).trim(),
      category: ServiceRequestCategory.fromName(data['category']),
      status: ServiceRequestStatus.fromStored(data['status']),
      createdByEmail: _text(data['createdByEmail']),
      createdByName: _text(data['createdByName']),
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
      adminNote: _text(data['adminNote']).trim(),
      photoUrl: photo.isEmpty ? null : photo,
      inProgressAt: readDate(data['inProgressAt']),
      resolvedAt: readDate(data['resolvedAt']),
      resolvedByName: resolver.isEmpty ? null : resolver,
    );
  }

  static String _text(Object? raw) => raw is String ? raw : '';
}
