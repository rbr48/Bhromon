import '../models/tour_post_models.dart';

/// One month of the family album: the photos posted in it, newest first.
class AlbumMonth {
  const AlbumMonth({required this.month, required this.photos});

  /// The first day of the month.
  final DateTime month;

  /// Web addresses of the photos, newest post first.
  final List<String> photos;
}

/// Groups the photos in [posts] by the month they were posted. Months come newest
/// first. A post with no photos, and a blank photo address, adds nothing. Videos
/// and reels are not photos, so they are not in the album.
List<AlbumMonth> familyAlbumMonths(List<TourPostItem> posts) {
  final newestFirst = [...posts]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final byMonth = <DateTime, List<String>>{};
  for (final post in newestFirst) {
    if (post.isReel) continue;
    final month = DateTime(post.createdAt.year, post.createdAt.month);
    for (final url in post.images) {
      if (url.trim().isEmpty) continue;
      byMonth.putIfAbsent(month, () => []).add(url);
    }
  }
  final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final month in months)
      AlbumMonth(month: month, photos: byMonth[month]!),
  ];
}
