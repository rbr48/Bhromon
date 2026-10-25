import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_activity_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';

void main() {
  group('TourStoryPoll', () {
    test('calculates vote counts and percentages accurately', () {
      const poll = TourStoryPoll(
        question: 'Dinner tonight?',
        options: ['Seafood', 'Biryani', 'BBQ'],
        votes: {
          'user1@test.com': 0,
          'user2@test.com': 0,
          'user3@test.com': 1,
        },
      );

      expect(poll.totalVotes, 3);
      expect(poll.voteCountFor(0), 2);
      expect(poll.voteCountFor(1), 1);
      expect(poll.voteCountFor(2), 0);
      expect(poll.percentageFor(0), closeTo(66.66, 0.1));
      expect(poll.percentageFor(1), closeTo(33.33, 0.1));
      expect(poll.percentageFor(2), 0.0);
      expect(poll.hasVoted('user1@test.com'), isTrue);
      expect(poll.hasVoted('user4@test.com'), isFalse);
      expect(poll.selectedOption('user3@test.com'), 1);

      // Add vote
      final updated = poll.withVote('user4@test.com', 2);
      expect(updated.totalVotes, 4);
      expect(updated.voteCountFor(2), 1);
      expect(updated.percentageFor(2), 25.0);
    });

    test('serializes and deserializes correctly', () {
      const poll = TourStoryPoll(
        question: 'Boat ride?',
        options: ['Yes', 'No'],
        votes: {'traveler@bd.com': 0},
      );
      final map = poll.toMap();
      final restored = TourStoryPoll.fromMap(map);

      expect(restored.question, 'Boat ride?');
      expect(restored.options, ['Yes', 'No']);
      expect(restored.votes['traveler@bd.com'], 0);
    });
  });

  group('TourPostDraft', () {
    test('draft serialization and state tracking', () {
      final now = DateTime(2026, 10, 25, 12, 0);
      final draft = TourPostDraft(
        caption: 'Coxs Bazar Sunset #sunset',
        mediaPaths: ['/tmp/sunset1.jpg', '/tmp/sunset2.jpg'],
        isReel: false,
        location: 'Inani Beach',
        tourDay: 'day2',
        filterId: 'clarendon',
        brightness: 0.1,
        contrast: 1.2,
        saturation: 1.1,
        tags: ['friend@x.com'],
        savedAt: now,
      );

      expect(draft.isEmpty, isFalse);
      final map = draft.toMap();
      final restored = TourPostDraft.fromMap(map);

      expect(restored.caption, 'Coxs Bazar Sunset #sunset');
      expect(restored.mediaPaths.length, 2);
      expect(restored.location, 'Inani Beach');
      expect(restored.filterId, 'clarendon');
      expect(restored.contrast, 1.2);
      expect(restored.tags, ['friend@x.com']);
    });

    test('empty draft reports isEmpty true', () {
      final draft = TourPostDraft(savedAt: DateTime.now());
      expect(draft.isEmpty, isTrue);
    });
  });

  group('TourCommentItem Threading & Likes', () {
    test('nested reply identification', () {
      final parent = TourCommentItem(
        id: 'c1',
        authorEmail: 'parent@x.com',
        authorName: 'Parent',
        text: 'Great view!',
        createdAt: DateTime.now(),
      );
      expect(parent.isReply, isFalse);

      final reply = TourCommentItem(
        id: 'c2',
        authorEmail: 'reply@x.com',
        authorName: 'Child',
        text: 'Totally agree!',
        parentId: 'c1',
        likes: ['someone@x.com'],
        isPinned: true,
        isAuthorLiked: true,
        createdAt: DateTime.now(),
      );
      expect(reply.isReply, isTrue);
      expect(reply.parentId, 'c1');
      expect(reply.isLikedBy('someone@x.com'), isTrue);
      expect(reply.isPinned, isTrue);
      expect(reply.isAuthorLiked, isTrue);

      final map = reply.toMap();
      final restored = TourCommentItem.fromMap(reply.id, map);
      expect(restored.parentId, 'c1');
      expect(restored.isPinned, isTrue);
      expect(restored.isAuthorLiked, isTrue);
      expect(restored.likes, ['someone@x.com']);
    });
  });

  group('TourStoryItem Video & Stickers', () {
    test('video story with poll and viewer tracking', () {
      const poll = TourStoryPoll(
        question: 'Beach or Hills?',
        options: ['Beach', 'Hills'],
      );
      const sticker = TourStorySticker(
        type: 'tide',
        title: 'ভাটা (Low Tide)',
        subtitle: 'Safe for swimming',
      );

      final story = TourStoryItem(
        id: 's1',
        authorEmail: 'lead@x.com',
        authorName: 'Tour Leader',
        mediaUrl: 'https://vps/media/s1.mp4',
        isVideo: true,
        videoUrl: 'https://vps/media/s1.mp4',
        viewers: ['m1@x.com', 'm2@x.com'],
        poll: poll,
        sticker: sticker,
        reactions: {'m1@x.com': '🔥', 'm2@x.com': '❤️'},
        createdAt: DateTime.now(),
      );

      expect(story.isVideo, isTrue);
      expect(story.isViewedBy('m1@x.com'), isTrue);
      expect(story.isViewedBy('m3@x.com'), isFalse);
      expect(story.reactions['m1@x.com'], '🔥');
      expect(story.reactions['m2@x.com'], '❤️');
      expect(story.poll?.question, 'Beach or Hills?');
      expect(story.sticker?.title, 'ভাটা (Low Tide)');

      final map = story.toMap();
      final restored = TourStoryItem.fromMap(story.id, map);
      expect(restored.isVideo, isTrue);
      expect(restored.videoUrl, 'https://vps/media/s1.mp4');
      expect(restored.viewers, ['m1@x.com', 'm2@x.com']);
      expect(restored.reactions['m1@x.com'], '🔥');
      expect(restored.reactions['m2@x.com'], '❤️');
      expect(restored.poll?.question, 'Beach or Hills?');
      expect(restored.sticker?.type, 'tide');
    });
  });

  group('TourPostItem Extended Capabilities', () {
    test('post with tags, pinned status, audio and expense ledger link', () {
      final post = TourPostItem(
        id: 'p1',
        tourId: 't1',
        authorEmail: 'chef@x.com',
        authorName: 'Chef',
        caption: 'Seafood Platter at Inani #seafood #foodie',
        images: ['https://vps/media/p1.jpg'],
        tags: ['foodie1@x.com', 'foodie2@x.com'],
        isPinned: true,
        hideLikeCount: true,
        disableComments: false,
        audioTitle: 'Ocean Breeze - Instrumental',
        audioUrl: 'https://vps/media/ocean.mp3',
        aspectRatio: 0.8,
        expenseAmount: 1850.0,
        expenseCategory: 'Food',
        createdAt: DateTime.now(),
      );

      expect(post.isPinned, isTrue);
      expect(post.hideLikeCount, isTrue);
      expect(post.tags.length, 2);
      expect(post.audioTitle, 'Ocean Breeze - Instrumental');
      expect(post.expenseAmount, 1850.0);
      expect(post.expenseCategory, 'Food');

      final map = post.toMap();
      final restored = TourPostItem.fromMap(post.id, map);
      expect(restored.isPinned, isTrue);
      expect(restored.hideLikeCount, isTrue);
      expect(restored.tags, ['foodie1@x.com', 'foodie2@x.com']);
      expect(restored.audioTitle, 'Ocean Breeze - Instrumental');
      expect(restored.aspectRatio, 0.8);
      expect(restored.expenseAmount, 1850.0);
    });

    test('post with editing state and archiving round-trips correctly', () {
      final now = DateTime(2026, 10, 25, 14, 0);
      final editedAt = DateTime(2026, 10, 25, 14, 30);
      final post = TourPostItem(
        id: 'p_archived_1',
        tourId: 't1',
        authorEmail: 'traveler@x.com',
        authorName: 'Traveler',
        caption: 'Edited Inani Sunset caption',
        images: ['https://bhromon.fun/media/t1/images/inani.jpg'],
        location: 'ইনানী বিচ (Inani Beach)',
        tourDay: 'day2',
        isEdited: true,
        editedAt: editedAt,
        isArchived: true,
        createdAt: now,
      );

      expect(post.isEdited, isTrue);
      expect(post.editedAt, editedAt);
      expect(post.isArchived, isTrue);

      final map = post.toMap();
      expect(map['isEdited'], isTrue);
      expect(map['isArchived'], isTrue);
      expect(map['editedAt'], isNotNull);

      final restored = TourPostItem.fromMap(post.id, map);
      expect(restored.isEdited, isTrue);
      expect(restored.isArchived, isTrue);
      expect(restored.location, 'ইনানী বিচ (Inani Beach)');
      expect(restored.caption, 'Edited Inani Sunset caption');
    });

    test('reel post with custom coverUrl and videoUrl round-trips correctly',
        () {
      final reelPost = TourPostItem(
        id: 'reel_1',
        tourId: 't1',
        authorEmail: 'creator@x.com',
        authorName: 'Creator',
        caption: 'Sunset waves reel #reels',
        images: const [],
        videoUrl: 'https://bhromon.fun/media/t1/reels/sunset.mp4',
        coverUrl: 'https://bhromon.fun/media/t1/covers/sunset_thumb.jpg',
        isReel: true,
        aspectRatio: 9 / 16,
        createdAt: DateTime.now(),
      );

      expect(reelPost.isReel, isTrue);
      expect(
          reelPost.videoUrl, 'https://bhromon.fun/media/t1/reels/sunset.mp4');
      expect(reelPost.coverUrl,
          'https://bhromon.fun/media/t1/covers/sunset_thumb.jpg');
      expect(reelPost.aspectRatio, closeTo(0.5625, 0.001));

      final map = reelPost.toMap();
      final restored = TourPostItem.fromMap(reelPost.id, map);

      expect(restored.isReel, isTrue);
      expect(
          restored.videoUrl, 'https://bhromon.fun/media/t1/reels/sunset.mp4');
      expect(restored.coverUrl,
          'https://bhromon.fun/media/t1/covers/sunset_thumb.jpg');
      expect(restored.aspectRatio, closeTo(0.5625, 0.001));
    });
  });

  group('FeedPrefs Collections', () {
    test('organizes bookmarks into named collections', () {
      const prefs = FeedPrefs(
        bookmarks: {'p1', 'p2', 'p3'},
        seenStories: {'s1'},
        collections: {
          'খাবার': ['p1'],
          'হোটেল': ['p2'],
          'স্পট': ['p1', 'p3'],
        },
      );

      expect(prefs.bookmarks.length, 3);
      expect(prefs.collections['খাবার'], ['p1']);
      expect(prefs.collections['হোটেল'], ['p2']);
      expect(prefs.collections['স্পট'], ['p1', 'p3']);
    });
  });
}
