// Notices, packing checklist, route checkpoints and channel messages.

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

/// A stop on the highway roadmap that a member added.
class RouteCheckpoint {
  final String id;
  final String name;
  final String highlight;
  final int kmFromStart;
  final double? lat;
  final double? lng;
  final String addedByEmail;

  const RouteCheckpoint({
    required this.id,
    required this.name,
    this.highlight = '',
    required this.kmFromStart,
    this.lat,
    this.lng,
    this.addedByEmail = '',
  });

  factory RouteCheckpoint.fromMap(String id, Map<String, dynamic> map) {
    return RouteCheckpoint(
      id: id,
      name: map['name'] as String? ?? 'চেকপয়েন্ট',
      highlight: map['highlight'] as String? ?? '',
      kmFromStart: (map['kmFromStart'] as num?)?.toInt() ?? 0,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      addedByEmail: normalizeEmail(map['addedByEmail'] as String? ?? ''),
    );
  }
}

class ChannelMessage {
  final String id;
  final String senderEmail;
  final String senderName;
  final String text;
  final DateTime timestamp;

  const ChannelMessage({
    required this.id,
    required this.senderEmail,
    required this.senderName,
    required this.text,
    required this.timestamp,
  });

  bool isSentBy(String email) => senderEmail == normalizeEmail(email);

  factory ChannelMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChannelMessage(
      id: id,
      senderEmail: normalizeEmail(map['senderEmail'] as String? ?? ''),
      senderName: map['senderName'] as String? ?? 'Member',
      text: map['text'] as String? ?? '',
      timestamp: readDate(map['timestamp']) ?? DateTime.now(),
    );
  }
}

/// Per-person feed state kept on this device: bookmarked posts and stories
/// already viewed. Nothing here is shared with other members.
class FeedPrefs {
  final Set<String> bookmarks;
  final Set<String> seenStories;

  const FeedPrefs({this.bookmarks = const {}, this.seenStories = const {}});
}
