import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';

void main() {
  final now = DateTime(2026, 10, 25, 12);

  group('isRemoteMediaUrl', () {
    test('only http and https addresses count as remote', () {
      expect(isRemoteMediaUrl('https://media.example.com/a.jpg'), isTrue);
      expect(isRemoteMediaUrl('http://media.example.com/a.jpg'), isTrue);
      expect(isRemoteMediaUrl('file:///tmp/a.jpg'), isFalse);
      expect(isRemoteMediaUrl('blob:https://x/1'), isFalse);
      expect(isRemoteMediaUrl(null), isFalse);
    });
  });

  group('TourPostItem', () {
    test('reads defaults and normalises the author', () {
      final post = TourPostItem.fromMap('p1', {
        'authorEmail': ' Rina@Example.com ',
        'createdAt': now.toIso8601String(),
      });

      expect(post.authorEmail, 'rina@example.com');
      expect(post.authorName, 'Family Member');
      expect(post.caption, '');
      expect(post.images, isEmpty);
      expect(post.tourDay, 'day1');
      expect(post.filterId, 'normal');
      expect(post.commentCount, 0);
      expect(post.isReel, isFalse);
      expect(post.isPinned, isFalse);
      expect(post.isArchived, isFalse);
    });

    test('round-trips its media, tags and edit state', () {
      final post = TourPostItem(
        id: 'p2',
        tourId: 't1',
        authorEmail: 'Rina@Example.com',
        authorName: 'Rina',
        caption: 'Sunrise',
        images: const ['https://media.example.com/1.jpg'],
        likes: const ['asha@example.com'],
        commentCount: 3,
        createdAt: now,
        tags: const ['Babu@Example.com'],
        isPinned: true,
        hideLikeCount: true,
        disableComments: true,
        aspectRatio: 0.8,
        expenseAmount: 450,
        expenseCategory: 'Food',
        isEdited: true,
        editedAt: now,
        isArchived: true,
      );

      final back = TourPostItem.fromMap('p2', post.toMap());

      expect(back.caption, 'Sunrise');
      expect(back.images, ['https://media.example.com/1.jpg']);
      expect(back.likes, ['asha@example.com']);
      expect(back.commentCount, 3);
      expect(back.tags, ['Babu@Example.com']);
      expect(back.isPinned, isTrue);
      expect(back.hideLikeCount, isTrue);
      expect(back.disableComments, isTrue);
      expect(back.aspectRatio, 0.8);
      expect(back.expenseAmount, 450);
      expect(back.expenseCategory, 'Food');
      expect(back.isEdited, isTrue);
      expect(back.editedAt!.isAtSameMomentAs(now), isTrue);
      expect(back.isArchived, isTrue);
      expect(back.isLikedBy('ASHA@example.com'), isTrue);
      expect(back.isLikedBy('babu@example.com'), isFalse);
    });

    test('a photo post is remote only when every image is', () {
      TourPostItem withImages(List<String> images,
              {bool reel = false, String? video}) =>
          TourPostItem(
            id: 'p3',
            tourId: 't1',
            authorEmail: 'a@example.com',
            authorName: 'A',
            caption: '',
            images: images,
            isReel: reel,
            videoUrl: video,
            createdAt: now,
          );

      expect(withImages(['https://m/1.jpg', 'https://m/2.jpg']).hasRemoteMedia,
          isTrue);
      expect(
          withImages(['https://m/1.jpg', 'file:///tmp/2.jpg']).hasRemoteMedia,
          isFalse);
      expect(withImages([]).hasRemoteMedia, isFalse);
      expect(
          withImages(['https://m/1.jpg'], reel: true, video: 'https://m/v.mp4')
              .hasRemoteMedia,
          isTrue);
      expect(withImages([], reel: true, video: 'file:///v.mp4').hasRemoteMedia,
          isFalse);
    });
  });

  group('TourStoryItem', () {
    test('is active for 24 hours after it was posted', () {
      final story = TourStoryItem(
        id: 's1',
        authorEmail: 'a@example.com',
        authorName: 'A',
        mediaUrl: 'https://m/s.jpg',
        createdAt: now,
        viewers: const ['rina@example.com'],
      );

      expect(story.isActiveAt(now.add(const Duration(hours: 1))), isTrue);
      expect(story.isActiveAt(now.add(TourStoryItem.lifetime)), isFalse);
      expect(
          story.isActiveAt(now.subtract(const Duration(minutes: 1))), isFalse);
      expect(story.isViewedBy('rina@example.com'), isTrue);
      expect(story.isViewedBy('babu@example.com'), isFalse);
    });
  });

  group('TourStoryPoll', () {
    test('counts votes per option and remembers who voted', () {
      final poll = TourStoryPoll.fromMap({
        'question': 'Dinner?',
        'options': ['Fish', 'Chicken'],
        'votes': {
          'Rina@Example.com': 0,
          'Babu@Example.com': 1,
          'Asha@Example.com': 0
        },
      });

      expect(poll.question, 'Dinner?');
      expect(poll.totalVotes, 3);
      expect(poll.voteCountFor(0), 2);
      expect(poll.voteCountFor(1), 1);
      expect(poll.hasVoted('RINA@example.com'), isTrue);
      expect(poll.hasVoted('nobody@example.com'), isFalse);
    });
  });

  group('TourPostDraft', () {
    test('is empty until it has a caption or media', () {
      final blank =
          TourPostDraft(caption: '', mediaPaths: const [], savedAt: now);
      final withText =
          TourPostDraft(caption: 'Hello', mediaPaths: const [], savedAt: now);

      expect(blank.isEmpty, isTrue);
      expect(withText.isEmpty, isFalse);
    });
  });
}
