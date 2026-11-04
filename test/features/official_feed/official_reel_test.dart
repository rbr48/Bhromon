import 'package:bhromon/features/official_feed/domain/official_reel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOfficialMediaUrl', () {
    test('accepts an https file under the official path on bhromon.fun', () {
      expect(
        isOfficialMediaUrl('https://bhromon.fun/media/official/reels/a.mp4'),
        isTrue,
      );
    });

    test('refuses plain http, another host and every other media space', () {
      expect(
        isOfficialMediaUrl('http://bhromon.fun/media/official/reels/a.mp4'),
        isFalse,
      );
      expect(
        isOfficialMediaUrl('https://example.com/media/official/reels/a.mp4'),
        isFalse,
      );
      expect(
        isOfficialMediaUrl('https://bhromon.fun/media/tour_1/posts/a.mp4'),
        isFalse,
      );
      expect(
        isOfficialMediaUrl('https://bhromon.fun/media/official-x/a.mp4'),
        isFalse,
      );
      expect(isOfficialMediaUrl('not a url'), isFalse);
    });
  });

  group('OfficialReel.fromMap', () {
    test('keeps a post whose video is an official file', () {
      final reel = OfficialReel.fromMap('p1', {
        'videoUrl': 'https://bhromon.fun/media/official/reels/p1.mp4',
        'coverUrl': 'https://bhromon.fun/media/official/covers/p1.jpg',
        'caption': 'Welcome',
        'durationSeconds': 42,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
      });

      expect(reel, isNotNull);
      expect(reel!.id, 'p1');
      expect(reel.caption, 'Welcome');
      expect(reel.coverUrl, 'https://bhromon.fun/media/official/covers/p1.jpg');
      expect(reel.durationSeconds, 42);
      expect(
          reel.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 1)), isTrue);
    });

    test('drops a post whose video is not an official file', () {
      expect(
        OfficialReel.fromMap('p2', {
          'videoUrl': 'https://bhromon.fun/media/tour_1/posts/x.mp4',
        }),
        isNull,
      );
      expect(OfficialReel.fromMap('p3', const {}), isNull);
      expect(OfficialReel.fromMap('p4', {'videoUrl': 42}), isNull);
    });

    test('a cover outside the official path is left out, not the post', () {
      final reel = OfficialReel.fromMap('p5', {
        'videoUrl': 'https://bhromon.fun/media/official/reels/p5.mp4',
        'coverUrl': 'https://bhromon.fun/media/tour_1/cover.jpg',
      });

      expect(reel, isNotNull);
      expect(reel!.coverUrl, isNull);
    });

    test('a bad caption, date or duration reads as missing', () {
      final reel = OfficialReel.fromMap('p6', {
        'videoUrl': 'https://bhromon.fun/media/official/reels/p6.mp4',
        'caption': 12,
        'createdAt': 'yesterday',
        'durationSeconds': 0,
      });

      expect(reel!.caption, '');
      expect(reel.createdAt, isNull);
      expect(reel.durationSeconds, isNull);
    });

    test('keeps an image post with an official image URL', () {
      final post = OfficialReel.fromMap('img1', {
        'imageUrl': 'https://bhromon.fun/media/official/images/img1.jpg',
        'caption': 'Photo Announcement',
      });

      expect(post, isNotNull);
      expect(post!.isImage, isTrue);
      expect(post.isVideo, isFalse);
      expect(
          post.imageUrl, 'https://bhromon.fun/media/official/images/img1.jpg');
      expect(post.displayImageUrl,
          'https://bhromon.fun/media/official/images/img1.jpg');
      expect(post.caption, 'Photo Announcement');
    });
  });
}
