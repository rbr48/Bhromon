import 'date_codec.dart';

/// Only http(s) URLs can be shown on any device. Paths and blob URLs saved
/// by a failed upload exist only on the uploader's own device.
bool isRemoteMediaUrl(String? url) {
  if (url == null) return false;
  return url.startsWith('https://') || url.startsWith('http://');
}

/// Interactive poll sticker for stories.
class TourStoryPoll {
  final String question;
  final List<String> options;

  /// Map of voter email -> selected option index.
  final Map<String, int> votes;

  const TourStoryPoll({
    required this.question,
    required this.options,
    this.votes = const {},
  });

  int get totalVotes => votes.length;

  int voteCountFor(int optionIndex) =>
      votes.values.where((idx) => idx == optionIndex).length;

  double percentageFor(int optionIndex) {
    if (totalVotes == 0) return 0.0;
    return (voteCountFor(optionIndex) / totalVotes) * 100.0;
  }

  bool hasVoted(String email) => votes.containsKey(normalizeEmail(email));

  int? selectedOption(String email) => votes[normalizeEmail(email)];

  TourStoryPoll withVote(String email, int optionIndex) {
    final updated = Map<String, int>.from(votes);
    updated[normalizeEmail(email)] = optionIndex;
    return TourStoryPoll(
      question: question,
      options: options,
      votes: updated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options,
      'votes': votes,
    };
  }

  factory TourStoryPoll.fromMap(Map<String, dynamic> map) {
    final rawVotes = map['votes'] as Map<dynamic, dynamic>? ?? {};
    final parsedVotes = <String, int>{};
    rawVotes.forEach((k, v) {
      if (v is num) {
        parsedVotes[normalizeEmail(k.toString())] = v.toInt();
      }
    });

    return TourStoryPoll(
      question: map['question'] as String? ?? '',
      options: (map['options'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['হ্যাঁ', 'না'],
      votes: parsedVotes,
    );
  }
}

/// Interactive location, tide, or question sticker for stories.
class TourStorySticker {
  /// 'location', 'tide', 'countdown', 'question'
  final String type;
  final String title;
  final String? subtitle;
  final double dx; // 0.0 to 1.0 (relative canvas x)
  final double dy; // 0.0 to 1.0 (relative canvas y)

  const TourStorySticker({
    required this.type,
    required this.title,
    this.subtitle,
    this.dx = 0.5,
    this.dy = 0.5,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'title': title,
      'subtitle': subtitle,
      'dx': dx,
      'dy': dy,
    };
  }

  factory TourStorySticker.fromMap(Map<String, dynamic> map) {
    return TourStorySticker(
      type: map['type'] as String? ?? 'location',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String?,
      dx: (map['dx'] as num?)?.toDouble() ?? 0.5,
      dy: (map['dy'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// A permanent collection of stories archived by the tour group.
class TourStoryHighlight {
  final String id;
  final String tourId;
  final String title;
  final String coverUrl;
  final List<String> storyIds;
  final DateTime createdAt;

  const TourStoryHighlight({
    required this.id,
    required this.tourId,
    required this.title,
    required this.coverUrl,
    required this.storyIds,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tourId': tourId,
      'title': title,
      'coverUrl': coverUrl,
      'storyIds': storyIds,
      'createdAt': writeDate(createdAt),
    };
  }

  factory TourStoryHighlight.fromMap(String id, Map<String, dynamic> map) {
    return TourStoryHighlight(
      id: id,
      tourId: map['tourId'] as String? ?? '',
      title: map['title'] as String? ?? 'স্মৃতি',
      coverUrl: map['coverUrl'] as String? ?? '',
      storyIds: (map['storyIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: readDate(map['createdAt']) ?? DateTime.now(),
    );
  }
}

/// Local draft for post/reel creation with auto-recovery.
class TourPostDraft {
  final String caption;
  final List<String> mediaPaths;
  final bool isReel;
  final String location;
  final String tourDay;
  final String filterId;
  final double brightness;
  final double contrast;
  final double saturation;
  final List<String> tags;
  final DateTime savedAt;

  const TourPostDraft({
    this.caption = '',
    this.mediaPaths = const [],
    this.isReel = false,
    this.location = '',
    this.tourDay = 'day1',
    this.filterId = 'normal',
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.tags = const [],
    required this.savedAt,
  });

  bool get isEmpty => caption.isEmpty && mediaPaths.isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'caption': caption,
      'mediaPaths': mediaPaths,
      'isReel': isReel,
      'location': location,
      'tourDay': tourDay,
      'filterId': filterId,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'tags': tags,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  factory TourPostDraft.fromMap(Map<String, dynamic> map) {
    return TourPostDraft(
      caption: map['caption'] as String? ?? '',
      mediaPaths: (map['mediaPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isReel: map['isReel'] as bool? ?? false,
      location: map['location'] as String? ?? '',
      tourDay: map['tourDay'] as String? ?? 'day1',
      filterId: map['filterId'] as String? ?? 'normal',
      brightness: (map['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (map['saturation'] as num?)?.toDouble() ?? 1.0,
      tags:
          (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      savedAt:
          DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
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

  // --- Extended Instagram Parity & Travel Capabilities ---
  final List<String> tags; // Tagged member emails
  final bool isPinned;
  final bool hideLikeCount;
  final bool disableComments;
  final String? audioTitle;
  final String? audioUrl;
  final double? aspectRatio;
  final double? expenseAmount;
  final String? expenseCategory;
  final String? coverUrl;

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
    this.tags = const [],
    this.isPinned = false,
    this.hideLikeCount = false,
    this.disableComments = false,
    this.audioTitle,
    this.audioUrl,
    this.aspectRatio,
    this.expenseAmount,
    this.expenseCategory,
    this.coverUrl,
  });

  bool isLikedBy(String email) => likes.contains(normalizeEmail(email));

  /// True when every attached media item can be shown on any device.
  bool get hasRemoteMedia {
    if (isReel) return isRemoteMediaUrl(videoUrl);
    return images.isNotEmpty && images.every(isRemoteMediaUrl);
  }

  TourPostItem copyWith({
    String? id,
    String? tourId,
    String? authorEmail,
    String? authorName,
    String? authorPhoto,
    String? caption,
    List<String>? images,
    String? videoUrl,
    bool? isReel,
    String? location,
    String? tourDay,
    String? filterId,
    List<String>? likes,
    int? commentCount,
    DateTime? createdAt,
    List<String>? tags,
    bool? isPinned,
    bool? hideLikeCount,
    bool? disableComments,
    String? audioTitle,
    String? audioUrl,
    double? aspectRatio,
    double? expenseAmount,
    String? expenseCategory,
    String? coverUrl,
  }) {
    return TourPostItem(
      id: id ?? this.id,
      tourId: tourId ?? this.tourId,
      authorEmail: authorEmail ?? this.authorEmail,
      authorName: authorName ?? this.authorName,
      authorPhoto: authorPhoto ?? this.authorPhoto,
      caption: caption ?? this.caption,
      images: images ?? this.images,
      videoUrl: videoUrl ?? this.videoUrl,
      isReel: isReel ?? this.isReel,
      location: location ?? this.location,
      tourDay: tourDay ?? this.tourDay,
      filterId: filterId ?? this.filterId,
      likes: likes ?? this.likes,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
      isPinned: isPinned ?? this.isPinned,
      hideLikeCount: hideLikeCount ?? this.hideLikeCount,
      disableComments: disableComments ?? this.disableComments,
      audioTitle: audioTitle ?? this.audioTitle,
      audioUrl: audioUrl ?? this.audioUrl,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      expenseAmount: expenseAmount ?? this.expenseAmount,
      expenseCategory: expenseCategory ?? this.expenseCategory,
      coverUrl: coverUrl ?? this.coverUrl,
    );
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
      if (tags.isNotEmpty) 'tags': tags,
      if (isPinned) 'isPinned': true,
      if (hideLikeCount) 'hideLikeCount': true,
      if (disableComments) 'disableComments': true,
      if (audioTitle != null) 'audioTitle': audioTitle,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
      if (expenseAmount != null) 'expenseAmount': expenseAmount,
      if (expenseCategory != null) 'expenseCategory': expenseCategory,
      if (coverUrl != null) 'coverUrl': coverUrl,
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
      tags:
          (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      isPinned: map['isPinned'] as bool? ?? false,
      hideLikeCount: map['hideLikeCount'] as bool? ?? false,
      disableComments: map['disableComments'] as bool? ?? false,
      audioTitle: map['audioTitle'] as String?,
      audioUrl: map['audioUrl'] as String?,
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble(),
      expenseAmount: (map['expenseAmount'] as num?)?.toDouble(),
      expenseCategory: map['expenseCategory'] as String?,
      coverUrl: map['coverUrl'] as String?,
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

  // --- Extended Threading & Social Parity ---
  final String? parentId; // If set, this is a reply to comment with parentId
  final List<String> likes;
  final bool isPinned;
  final bool isAuthorLiked;

  const TourCommentItem({
    required this.id,
    required this.authorEmail,
    required this.authorName,
    this.authorPhoto,
    required this.text,
    this.reaction,
    required this.createdAt,
    this.parentId,
    this.likes = const [],
    this.isPinned = false,
    this.isAuthorLiked = false,
  });

  bool get isReply => parentId != null && parentId!.isNotEmpty;
  bool isLikedBy(String email) => likes.contains(normalizeEmail(email));

  TourCommentItem copyWith({
    String? id,
    String? authorEmail,
    String? authorName,
    String? authorPhoto,
    String? text,
    String? reaction,
    DateTime? createdAt,
    String? parentId,
    List<String>? likes,
    bool? isPinned,
    bool? isAuthorLiked,
  }) {
    return TourCommentItem(
      id: id ?? this.id,
      authorEmail: authorEmail ?? this.authorEmail,
      authorName: authorName ?? this.authorName,
      authorPhoto: authorPhoto ?? this.authorPhoto,
      text: text ?? this.text,
      reaction: reaction ?? this.reaction,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
      likes: likes ?? this.likes,
      isPinned: isPinned ?? this.isPinned,
      isAuthorLiked: isAuthorLiked ?? this.isAuthorLiked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorEmail': normalizeEmail(authorEmail),
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'text': text,
      'reaction': reaction,
      'createdAt': writeDate(createdAt),
      if (parentId != null && parentId!.isNotEmpty) 'parentId': parentId,
      if (likes.isNotEmpty) 'likes': likes,
      if (isPinned) 'isPinned': true,
      if (isAuthorLiked) 'isAuthorLiked': true,
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
      parentId: map['parentId'] as String?,
      likes:
          (map['likes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      isPinned: map['isPinned'] as bool? ?? false,
      isAuthorLiked: map['isAuthorLiked'] as bool? ?? false,
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

  // --- Extended Video, Stickers & Viewer Analytics ---
  final bool isVideo;
  final String? videoUrl;
  final List<String> viewers;
  final TourStoryPoll? poll;
  final TourStorySticker? sticker;
  final String? highlightId;

  const TourStoryItem({
    required this.id,
    required this.authorEmail,
    required this.authorName,
    this.authorPhoto,
    required this.mediaUrl,
    this.caption,
    required this.createdAt,
    this.isVideo = false,
    this.videoUrl,
    this.viewers = const [],
    this.poll,
    this.sticker,
    this.highlightId,
  });

  bool isActiveAt(DateTime now) =>
      now.difference(createdAt) < lifetime && !createdAt.isAfter(now);

  bool isViewedBy(String email) => viewers.contains(normalizeEmail(email));

  TourStoryItem copyWith({
    String? id,
    String? authorEmail,
    String? authorName,
    String? authorPhoto,
    String? mediaUrl,
    String? caption,
    DateTime? createdAt,
    bool? isVideo,
    String? videoUrl,
    List<String>? viewers,
    TourStoryPoll? poll,
    TourStorySticker? sticker,
    String? highlightId,
  }) {
    return TourStoryItem(
      id: id ?? this.id,
      authorEmail: authorEmail ?? this.authorEmail,
      authorName: authorName ?? this.authorName,
      authorPhoto: authorPhoto ?? this.authorPhoto,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      isVideo: isVideo ?? this.isVideo,
      videoUrl: videoUrl ?? this.videoUrl,
      viewers: viewers ?? this.viewers,
      poll: poll ?? this.poll,
      sticker: sticker ?? this.sticker,
      highlightId: highlightId ?? this.highlightId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorEmail': normalizeEmail(authorEmail),
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'mediaUrl': mediaUrl,
      'caption': caption,
      'createdAt': writeDate(createdAt),
      if (isVideo) 'isVideo': true,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (viewers.isNotEmpty) 'viewers': viewers,
      if (poll != null) 'poll': poll!.toMap(),
      if (sticker != null) 'sticker': sticker!.toMap(),
      if (highlightId != null) 'highlightId': highlightId,
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
      isVideo: map['isVideo'] as bool? ?? false,
      videoUrl: map['videoUrl'] as String?,
      viewers: (map['viewers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      poll: map['poll'] != null
          ? TourStoryPoll.fromMap(Map<String, dynamic>.from(map['poll'] as Map))
          : null,
      sticker: map['sticker'] != null
          ? TourStorySticker.fromMap(
              Map<String, dynamic>.from(map['sticker'] as Map))
          : null,
      highlightId: map['highlightId'] as String?,
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
