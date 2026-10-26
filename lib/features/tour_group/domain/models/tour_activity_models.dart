// Notices, packing checklist and route checkpoints.

import 'date_codec.dart';

class TourNotice {
  final String id;
  final String title;
  final String content;
  final String author;
  final String authorEmail;
  final bool urgent;
  final DateTime createdAt;

  const TourNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    this.authorEmail = '',
    this.urgent = false,
    required this.createdAt,
  });

  factory TourNotice.fromMap(String id, Map<String, dynamic> map) {
    return TourNotice(
      id: id,
      title: map['title'] as String? ?? 'নোটিশ',
      content: map['content'] as String? ?? '',
      author: map['author'] as String? ?? 'ট্যুর লিডার',
      authorEmail: normalizeEmail(map['authorEmail'] as String? ?? ''),
      urgent: map['urgent'] as bool? ?? false,
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
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
