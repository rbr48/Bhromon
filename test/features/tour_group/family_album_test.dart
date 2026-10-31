import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/family_album.dart';
import 'package:flutter_test/flutter_test.dart';

TourPostItem _post(String id, DateTime createdAt, List<String> images,
        {bool isReel = false}) =>
    TourPostItem(
      id: id,
      tourId: 'f',
      authorEmail: 'asha@x.com',
      authorName: 'Asha',
      caption: '',
      images: images,
      isReel: isReel,
      createdAt: createdAt,
    );

void main() {
  group('familyAlbumMonths', () {
    test('groups the photos by the month they were posted, newest month first',
        () {
      final months = familyAlbumMonths([
        _post('a', DateTime(2026, 9, 3), ['s1.jpg']),
        _post('b', DateTime(2026, 10, 1), ['o1.jpg', 'o2.jpg']),
        _post('c', DateTime(2025, 12, 30), ['d1.jpg']),
      ]);
      expect(months.map((m) => m.month).toList(),
          [DateTime(2026, 10), DateTime(2026, 9), DateTime(2025, 12)]);
      expect(months.first.photos, ['o1.jpg', 'o2.jpg']);
    });

    test(
        'photos in a month run from the newest post, in the order each post has them',
        () {
      final months = familyAlbumMonths([
        _post('old', DateTime(2026, 10, 2), ['x1.jpg', 'x2.jpg']),
        _post('new', DateTime(2026, 10, 20), ['y1.jpg', 'y2.jpg']),
      ]);
      expect(months.single.photos, ['y1.jpg', 'y2.jpg', 'x1.jpg', 'x2.jpg']);
    });

    test('posts without photos, blank addresses and reels add nothing', () {
      final months = familyAlbumMonths([
        _post('text', DateTime(2026, 10, 2), const []),
        _post('blank', DateTime(2026, 10, 3), ['  ']),
        _post('reel', DateTime(2026, 10, 4), ['cover.jpg'], isReel: true),
        _post('photo', DateTime(2026, 10, 5), ['p.jpg']),
      ]);
      expect(months.single.photos, ['p.jpg']);
    });

    test('no posts give an empty album', () {
      expect(familyAlbumMonths(const []), isEmpty);
    });
  });
}
