import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String location;
  final String tourDay; // 'all', 'day1', 'day2', 'day3', 'day4', 'day5'
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
    this.location = 'Cox\'s Bazar',
    this.tourDay = 'day1',
    this.filterId = 'normal',
    this.likes = const [],
    this.commentCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tourId': tourId,
      'authorEmail': authorEmail,
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
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory TourPostItem.fromMap(String id, Map<String, dynamic> map) {
    return TourPostItem(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      authorEmail: map['authorEmail'] as String? ?? '',
      authorName: map['authorName'] as String? ?? 'Family Member',
      authorPhoto: map['authorPhoto'] as String?,
      caption: map['caption'] as String? ?? '',
      images: (map['images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      videoUrl: map['videoUrl'] as String?,
      isReel: map['isReel'] as bool? ?? false,
      location: map['location'] as String? ?? "লাবণী ও সুগন্ধা বিচ, কক্সবাজার",
      tourDay: map['tourDay'] as String? ?? 'day1',
      filterId: map['filterId'] as String? ?? 'normal',
      likes: (map['likes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      commentCount: map['commentCount'] as int? ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class TourCommentItem {
  final String id;
  final String authorEmail;
  final String authorName;
  final String? authorPhoto;
  final String text;
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
      'authorEmail': authorEmail,
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'text': text,
      'reaction': reaction,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory TourCommentItem.fromMap(String id, Map<String, dynamic> map) {
    return TourCommentItem(
      id: id,
      authorEmail: map['authorEmail'] as String? ?? '',
      authorName: map['authorName'] as String? ?? 'Member',
      authorPhoto: map['authorPhoto'] as String?,
      text: map['text'] as String? ?? '',
      reaction: map['reaction'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class TourStoryItem {
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

  Map<String, dynamic> toMap() {
    return {
      'authorEmail': authorEmail,
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'mediaUrl': mediaUrl,
      'caption': caption,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory TourStoryItem.fromMap(String id, Map<String, dynamic> map) {
    return TourStoryItem(
      id: id,
      authorEmail: map['authorEmail'] as String? ?? '',
      authorName: map['authorName'] as String? ?? 'Member',
      authorPhoto: map['authorPhoto'] as String?,
      mediaUrl: map['mediaUrl'] as String? ?? '',
      caption: map['caption'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
