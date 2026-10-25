import 'date_codec.dart';

/// Only http(s) URLs can be shown on any device. Paths and blob URLs saved
/// by a failed upload exist only on the uploader's own device.
bool isRemoteMediaUrl(String? url) {
  if (url == null) return false;
  return url.startsWith('https://') || url.startsWith('http://');
}

class TourPostItem {
  final String id;
  final String tourId;
  final String authorEmail;
  final String authorName;
  final String? authorPhoto;
  final String caption;
  final List<String> images;
  final String? videoUrl;
  final bool isReel;

  /// Empty means "use the tour destination" (set by the UI, not hard-coded here).
  final String location;
  final String tourDay; // e.g. 'day1', 'day2'
  final String filterId;
  final List<String> likes;
  final int commentCount;
  final DateTime createdAt;

  const TourPostItem({
    required this.id,
    required this.tourId,
    required this.authorEmail,
    required this.authorName,
    this.authorPhoto,
    required this.caption,
    required this.images,
    this.videoUrl,
    this.isReel = false,
    this.location = '',
    this.tourDay = 'day1',
    this.filterId = 'normal',
    this.likes = const [],
    this.commentCount = 0,
    required this.createdAt,
  });

  bool isLikedBy(String email) => likes.contains(normalizeEmail(email));

  /// True when every attached media item can be shown on any device.
  bool get hasRemoteMedia {
    if (isReel) return isRemoteMediaUrl(videoUrl);
    return images.isNotEmpty && images.every(isRemoteMediaUrl);
  }

  Map<String, dynamic> toMap() {
    return {
      'tourId': tourId,
      'authorEmail': normalizeEmail(authorEmail),
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'caption': caption,
      'images': images,
      'videoUrl': videoUrl,
      'isReel': isReel,
      'location': location,
      'tourDay': tourDay,
      'filterId': filterId,
      'likes': likes,
      'commentCount': commentCount,
      'createdAt': writeDate(createdAt),
    };
  }

  factory TourPostItem.fromMap(String id, Map<String, dynamic> map) {
    return TourPostItem(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      authorEmail: normalizeEmail(map['authorEmail'] as String? ?? ''),
      authorName: map['authorName'] as String? ?? 'Family Member',
      authorPhoto: map['authorPhoto'] as String?,
      caption: map['caption'] as String? ?? '',
      images: (map['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      videoUrl: map['videoUrl'] as String?,
      isReel: map['isReel'] as bool? ?? false,
      location: map['location'] as String? ?? '',
      tourDay: map['tourDay'] as String? ?? 'day1',
      filterId: map['filterId'] as String? ?? 'normal',
      likes:
          (map['likes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      commentCount: (map['commentCount'] as num?)?.toInt() ?? 0,
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
    );
  }
}

class TourCommentItem {
  final String id;
  final String authorEmail;
  final String authorName;
  final String? authorPhoto;
  final String text;

  /// A reaction-only comment (an emoji) has an empty [text]; it is shown once.
  final String? reaction;
  final DateTime createdAt;

  const TourCommentItem({
    required this.id,
    required this.authorEmail,
    required this.authorName,
    this.authorPhoto,
    required this.text,
    this.reaction,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'authorEmail': normalizeEmail(authorEmail),
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'text': text,
      'reaction': reaction,
      'createdAt': writeDate(createdAt),
    };
  }

  factory TourCommentItem.fromMap(String id, Map<String, dynamic> map) {
    return TourCommentItem(
      id: id,
      authorEmail: normalizeEmail(map['authorEmail'] as String? ?? ''),
      authorName: map['authorName'] as String? ?? 'Member',
      authorPhoto: map['authorPhoto'] as String?,
      text: map['text'] as String? ?? '',
      reaction: map['reaction'] as String?,
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
    );
  }
}

class TourStoryItem {
  /// Stories are visible for this long after they are posted.
  static const Duration lifetime = Duration(hours: 24);

  final String id;
  final String authorEmail;
  final String authorName;
  final String? authorPhoto;
  final String mediaUrl;
  final String? caption;
  final DateTime createdAt;

  const TourStoryItem({
    required this.id,
    required this.authorEmail,
    required this.authorName,
    this.authorPhoto,
    required this.mediaUrl,
    this.caption,
    required this.createdAt,
  });

  bool isActiveAt(DateTime now) =>
      now.difference(createdAt) < lifetime && !createdAt.isAfter(now);

  Map<String, dynamic> toMap() {
    return {
      'authorEmail': normalizeEmail(authorEmail),
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'mediaUrl': mediaUrl,
      'caption': caption,
      'createdAt': writeDate(createdAt),
    };
  }

  factory TourStoryItem.fromMap(String id, Map<String, dynamic> map) {
    return TourStoryItem(
      id: id,
      authorEmail: normalizeEmail(map['authorEmail'] as String? ?? ''),
      authorName: map['authorName'] as String? ?? 'Member',
      authorPhoto: map['authorPhoto'] as String?,
      mediaUrl: map['mediaUrl'] as String? ?? '',
      caption: map['caption'] as String?,
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
    );
  }
}

/// Groups stories by author, newest author first, keeping each author's
/// stories in posting order so the viewer can step through them.
List<List<TourStoryItem>> groupStoriesByAuthor(List<TourStoryItem> stories) {
  final byAuthor = <String, List<TourStoryItem>>{};
  for (final story in stories) {
    byAuthor.putIfAbsent(story.authorEmail, () => []).add(story);
  }
  final groups = byAuthor.values.toList();
  for (final group in groups) {
    group.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  groups.sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
  return groups;
}
