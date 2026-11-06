import 'package:cloud_firestore/cloud_firestore.dart';

/// The path every official file lives under. The app plays only files there.
const String officialMediaPrefix = '/media/official/';

/// Whether [url] points at a file of the official feed, over https.
bool isOfficialMediaUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'bhromon.fun' &&
      uri.path.startsWith(officialMediaPrefix);
}

/// One post in the official feed (a video reel or an image post).
class OfficialReel {
  const OfficialReel({
    required this.id,
    this.videoUrl,
    this.imageUrl,
    this.coverUrl,
    this.caption = '',
    this.createdAt,
    this.durationSeconds,
  });

  final String id;
  final String? videoUrl;
  final String? imageUrl;
  final String? coverUrl;
  final String caption;
  final DateTime? createdAt;
  final int? durationSeconds;

  /// Whether this post is a video reel.
  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// Whether this post is an image post.
  bool get isImage =>
      !isVideo &&
      ((imageUrl != null && imageUrl!.isNotEmpty) ||
          (coverUrl != null && coverUrl!.isNotEmpty));

  /// The primary image URL for an image post or cover.
  String? get displayImageUrl => imageUrl ?? coverUrl;

  /// The post a feed document describes, or null when neither its video nor its image is an official file.
  static OfficialReel? fromMap(String id, Map<String, dynamic> data) {
    final video = data['videoUrl'];
    final image = data['imageUrl'];
    final cover = data['coverUrl'];

    final hasValidVideo = video is String && isOfficialMediaUrl(video);
    final hasValidImage = image is String && isOfficialMediaUrl(image);
    final hasValidCover = cover is String && isOfficialMediaUrl(cover);

    if (!hasValidVideo && !hasValidImage && !hasValidCover) return null;

    final caption = data['caption'];
    final created = data['createdAt'];
    final duration = data['durationSeconds'];
    return OfficialReel(
      id: id,
      videoUrl: hasValidVideo ? video : null,
      imageUrl: hasValidImage ? image : null,
      coverUrl: hasValidCover ? cover : null,
      caption: caption is String ? caption : '',
      createdAt: created is Timestamp ? created.toDate() : null,
      durationSeconds: duration is int && duration > 0 ? duration : null,
    );
  }
}
