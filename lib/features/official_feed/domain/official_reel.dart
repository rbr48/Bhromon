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

/// One post in the official feed.
class OfficialReel {
  const OfficialReel({
    required this.id,
    required this.videoUrl,
    this.coverUrl,
    this.caption = '',
    this.createdAt,
    this.durationSeconds,
  });

  final String id;
  final String videoUrl;
  final String? coverUrl;
  final String caption;
  final DateTime? createdAt;
  final int? durationSeconds;

  /// The post a feed document describes, or null when its video is not an official file.
  static OfficialReel? fromMap(String id, Map<String, dynamic> data) {
    final video = data['videoUrl'];
    if (video is! String || !isOfficialMediaUrl(video)) return null;
    final cover = data['coverUrl'];
    final caption = data['caption'];
    final created = data['createdAt'];
    final duration = data['durationSeconds'];
    return OfficialReel(
      id: id,
      videoUrl: video,
      coverUrl: cover is String && isOfficialMediaUrl(cover) ? cover : null,
      caption: caption is String ? caption : '',
      createdAt: created is Timestamp ? created.toDate() : null,
      durationSeconds: duration is int && duration > 0 ? duration : null,
    );
  }
}
