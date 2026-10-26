// Notices, packing checklist and route checkpoints.

import 'date_codec.dart';

/// What a notice is for. Older notices have none and read as announcements.
enum NoticeKind {
  announcement('📢'),
  schedule('🕒'),
  meetup('📍'),
  reminder('⏰'),
  emergency('🚨'),
  rule('📜'),
  rollcall('🙋');

  const NoticeKind(this.emoji);

  final String emoji;

  /// Kinds that happen at a time, so they count down and can expire.
  bool get isTimed =>
      this == schedule ||
      this == meetup ||
      this == reminder ||
      this == rollcall;

  /// Kinds that ask every member to answer.
  bool get asksEveryone =>
      this == rollcall || this == emergency || this == rule;

  static NoticeKind fromName(String? name) => NoticeKind.values
      .firstWhere((k) => k.name == name, orElse: () => NoticeKind.announcement);
}

class TourNotice {
  final String id;
  final String title;
  final String content;
  final String author;
  final String authorEmail;
  final bool urgent;
  final DateTime createdAt;
  final NoticeKind kind;
  final bool pinned;

  /// When it happens: departure, meet-up, roll call. Null for plain notices.
  final DateTime? eventAt;

  /// After this the notice moves to the archive.
  final DateTime? expiresAt;
  final String? place;
  final String? mapUrl;

  /// The itinerary stop it belongs to.
  final String? stopId;

  /// Whether members are asked to answer ("Got it", or "I'm here").
  final bool requireAck;

  /// Members who answered.
  final List<String> ackBy;
  final DateTime? editedAt;

  const TourNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    this.authorEmail = '',
    this.urgent = false,
    required this.createdAt,
    this.kind = NoticeKind.announcement,
    this.pinned = false,
    this.eventAt,
    this.expiresAt,
    this.place,
    this.mapUrl,
    this.stopId,
    this.requireAck = false,
    this.ackBy = const [],
    this.editedAt,
  });

  bool get asksAnswer => requireAck || kind == NoticeKind.rollcall;

  bool ackedBy(String email) => ackBy.contains(normalizeEmail(email));

  /// The fields an admin writes. Answers (ackBy) are left out, so editing a
  /// notice keeps who already answered.
  Map<String, dynamic> toEditableMap() => {
        'title': title,
        'content': content,
        'urgent': urgent,
        'kind': kind.name,
        'pinned': pinned,
        'eventAt': eventAt == null ? null : writeDate(eventAt!),
        'expiresAt': expiresAt == null ? null : writeDate(expiresAt!),
        'place': place,
        'mapUrl': mapUrl,
        'stopId': stopId,
        'requireAck': requireAck,
      };

  factory TourNotice.fromMap(String id, Map<String, dynamic> map) {
    String? text(String key) {
      final v = map[key];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    return TourNotice(
      id: id,
      title: map['title'] as String? ?? 'নোটিশ',
      content: map['content'] as String? ?? '',
      author: map['author'] as String? ?? 'ট্যুর লিডার',
      authorEmail: normalizeEmail(map['authorEmail'] as String? ?? ''),
      urgent: map['urgent'] as bool? ?? false,
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
      kind: NoticeKind.fromName(map['kind'] as String?),
      pinned: map['pinned'] as bool? ?? false,
      eventAt: readDate(map['eventAt']),
      expiresAt: readDate(map['expiresAt']),
      place: text('place'),
      mapUrl: text('mapUrl'),
      stopId: text('stopId'),
      requireAck: map['requireAck'] as bool? ?? false,
      ackBy: (map['ackBy'] as List<dynamic>?)
              ?.map((e) => normalizeEmail(e.toString()))
              .toList() ??
          const [],
      editedAt: readDate(map['editedAt']),
    );
  }
}

class ChecklistItem {
  final String id;
  final String title;
  final String category;

  /// Emails of the members who have packed this item. Each person ticks
  /// their own items, so one person's tick does not tick it for everyone.
  final List<String> checkedBy;

  const ChecklistItem({
    required this.id,
    required this.title,
    required this.category,
    this.checkedBy = const [],
  });

  bool isCheckedBy(String email) => checkedBy.contains(normalizeEmail(email));

  factory ChecklistItem.fromMap(String id, Map<String, dynamic> map) {
    return ChecklistItem(
      id: id,
      title: map['title'] as String? ?? '',
      category: map['category'] as String? ?? 'Others',
      checkedBy: (map['checkedBy'] as List<dynamic>?)
              ?.map((e) => normalizeEmail(e.toString()))
              .toList() ??
          const [],
    );
  }
}

/// What a stop along the way is for.
enum CheckpointKind {
  food,
  prayer,
  fuel,
  washroom,
  viewpoint,

  /// An army checkpost or escort point, such as Dighinala before Sajek.
  checkpost,

  /// A ferry, ghat or jetty.
  ferry,
  toll,
  hospital,
  police,
  hotel,
  shopping,
  custom;

  static CheckpointKind fromString(String? value) {
    for (final k in values) {
      if (k.name == value) return k;
    }
    return CheckpointKind.custom;
  }

  String get emoji => switch (this) {
        food => '🍲',
        prayer => '🕌',
        fuel => '⛽',
        washroom => '🚻',
        viewpoint => '📸',
        checkpost => '🛡️',
        ferry => '⛴️',
        toll => '🎫',
        hospital => '🏥',
        police => '👮',
        hotel => '🏨',
        shopping => '🛍️',
        custom => '📍',
      };
}

/// A stop along a leg of the route that a member added: a meal break, a
/// prayer stop, the army escort point, a ferry ghat…
class RouteCheckpoint {
  final String id;
  final String name;
  final String highlight;

  /// Km from the start of its leg.
  final int kmFromStart;
  final double? lat;
  final double? lng;
  final String addedByEmail;

  /// The leg it belongs to ("<fromId>><toId>"). Stops added before legs
  /// existed have none and show on the first leg.
  final String? legKey;
  final CheckpointKind kind;
  final DateTime? plannedAt;
  final String notes;

  /// When the group passed it, set by an admin.
  final DateTime? visitedAt;

  const RouteCheckpoint({
    required this.id,
    required this.name,
    this.highlight = '',
    required this.kmFromStart,
    this.lat,
    this.lng,
    this.addedByEmail = '',
    this.legKey,
    this.kind = CheckpointKind.custom,
    this.plannedAt,
    this.notes = '',
    this.visitedAt,
  });

  bool get hasLocation => lat != null && lng != null;

  factory RouteCheckpoint.fromMap(String id, Map<String, dynamic> map) {
    return RouteCheckpoint(
      id: id,
      name: map['name'] as String? ?? '',
      highlight: map['highlight'] as String? ?? '',
      kmFromStart: (map['kmFromStart'] as num?)?.toInt() ?? 0,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      addedByEmail: normalizeEmail(map['addedByEmail'] as String? ?? ''),
      legKey: map['legKey'] as String?,
      kind: CheckpointKind.fromString(map['kind'] as String?),
      plannedAt: readDate(map['plannedAt']),
      notes: map['notes'] as String? ?? '',
      visitedAt: readDate(map['visitedAt']),
    );
  }
}

/// Per-person feed state kept on this device: bookmarked posts and stories
/// already viewed. Nothing here is shared with other members.
class FeedPrefs {
  final Set<String> bookmarks;
  final Set<String> seenStories;
  final Map<String, List<String>> collections;

  const FeedPrefs({
    this.bookmarks = const {},
    this.seenStories = const {},
    this.collections = const {},
  });
}
