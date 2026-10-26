import 'package:flutter_test/flutter_test.dart';

import 'package:bhromon/features/tour_group/domain/models/expense_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/scrapbook_engine.dart';

const _img = 'https://bhromon.fun/media/t1/posts/a.jpg';
const _vid = 'https://bhromon.fun/media/t1/posts/a.mp4';

TourPostItem _post(
  String id, {
  String author = 'rina@x.com',
  String name = 'Rina',
  List<String> images = const [_img],
  bool reel = false,
  String caption = '',
  String location = '',
  String day = 'day1',
  int likes = 0,
  int comments = 0,
  List<String> tags = const [],
  int minute = 0,
  bool archived = false,
}) {
  return TourPostItem(
    id: id,
    tourId: 't1',
    authorEmail: author,
    authorName: name,
    caption: caption,
    images: reel ? const [] : images,
    videoUrl: reel ? _vid : null,
    isReel: reel,
    location: location,
    tourDay: day,
    likes: [for (var i = 0; i < likes; i++) 'fan$i@x.com'],
    commentCount: comments,
    tags: tags,
    createdAt: DateTime(2026, 10, 25, 8, minute),
    isArchived: archived,
  );
}

final _days = [
  TourDayInfo(
      id: 'day1', dayNumber: 1, date: DateTime(2026, 10, 25), label: 'Day 1'),
  TourDayInfo(
      id: 'day2', dayNumber: 2, date: DateTime(2026, 10, 26), label: 'Day 2'),
];

void main() {
  test('an empty tour makes an empty issue with no awards or cover', () {
    final issue = ScrapbookIssue.build(posts: const []);
    expect(issue.isEmpty, isTrue);
    expect(issue.coverPost, isNull);
    expect(issue.awards, isEmpty);
    expect(issue.chapters, isEmpty);
  });

  test('the cover is the best-received photo, never a reel', () {
    final issue = ScrapbookIssue.build(posts: [
      _post('p1', likes: 2),
      _post('r1', reel: true, likes: 9),
      _post('p2', likes: 3, minute: 5),
    ]);
    expect(issue.coverPost!.id, 'p2');
  });

  test('archived posts are left out everywhere', () {
    final issue = ScrapbookIssue.build(posts: [
      _post('p1', archived: true, likes: 5),
      _post('p2'),
    ]);
    expect(issue.stats.posts, 1);
    expect(issue.coverPost!.id, 'p2');
  });

  test('chapters follow tour days, and stray posts get a dated chapter', () {
    final stray = TourPostItem(
      id: 'p9',
      tourId: 't1',
      authorEmail: 'rina@x.com',
      authorName: 'Rina',
      caption: '',
      images: const [_img],
      tourDay: 'day7',
      createdAt: DateTime(2026, 10, 27, 9),
    );
    final issue = ScrapbookIssue.build(
      days: _days,
      posts: [
        _post('d2', day: 'day2', minute: 1),
        _post('d1a', day: 'day1', minute: 2, likes: 1),
        _post('d1b', day: 'day1', minute: 3, likes: 4),
        stray,
      ],
    );
    expect(issue.chapters, hasLength(3));
    expect(issue.chapters[0].day!.id, 'day1');
    expect(issue.chapters[0].hero!.id, 'd1b');
    expect(issue.chapters[0].gallery.map((p) => p.id), ['d1a']);
    expect(issue.chapters[1].day!.id, 'day2');
    expect(issue.chapters[2].day, isNull);
    expect(issue.chapters[2].posts.single.id, 'p9');
  });

  test('awards need real data, and ties go to the name first in order', () {
    final issue = ScrapbookIssue.build(posts: [
      _post('a', author: 'zara@x.com', name: 'Zara', images: [_img, _img]),
      _post('b', author: 'amir@x.com', name: 'Amir', images: [_img, _img]),
    ]);
    final photographer = issue.awards
        .singleWhere((a) => a.kind == ScrapbookAwardKind.photographer);
    expect(photographer.winnerName, 'Amir');
    expect(photographer.value, 2);
    // Nobody had likes, reels, comments, long captions, two places or tags.
    expect(issue.awards.map((a) => a.kind), [ScrapbookAwardKind.photographer]);
  });

  test('every award goes to the member who earned it', () {
    final issue = ScrapbookIssue.build(
      members: [
        TourMember(
          tourId: 't1',
          email: 'Tuli@x.com',
          displayName: 'Tuli Apa',
          role: TourRole.member,
          status: TourMemberStatus.active,
          joinedAt: DateTime(2026),
        ),
      ],
      posts: [
        _post('r1', author: 'babu@x.com', name: 'Babu', reel: true),
        _post('p1',
            author: 'rina@x.com', likes: 7, comments: 3, location: 'Inani'),
        _post('p2', author: 'rina@x.com', location: 'Himchari'),
        _post('p3',
            author: 'babu@x.com',
            caption: 'A very long caption about the sunset at the beach today',
            tags: ['tuli@x.com', 'babu@x.com']),
      ],
    );
    String winner(ScrapbookAwardKind k) =>
        issue.awards.singleWhere((a) => a.kind == k).winnerName;
    expect(winner(ScrapbookAwardKind.reelStar), 'Babu');
    expect(winner(ScrapbookAwardKind.crowdFavourite), 'Rina');
    expect(winner(ScrapbookAwardKind.conversationStarter), 'Rina');
    expect(winner(ScrapbookAwardKind.explorer), 'Rina');
    expect(winner(ScrapbookAwardKind.storyteller), 'Babu');
    // Tagging yourself does not count; the member list supplies the name.
    expect(winner(ScrapbookAwardKind.mostTagged), 'Tuli Apa');
  });

  test('top moments rank by likes then comments, and skip unloved posts', () {
    final issue = ScrapbookIssue.build(posts: [
      _post('quiet'),
      _post('talked', comments: 3),
      _post('loved', likes: 2),
    ]);
    expect(issue.topMoments.map((p) => p.id), ['loved', 'talked']);
  });

  test('places keep first-visit order and merge case', () {
    final issue = ScrapbookIssue.build(posts: [
      _post('a', location: 'Inani', minute: 1),
      _post('b', location: 'Himchari', minute: 2),
      _post('c', location: 'inani ', minute: 3),
    ]);
    expect(issue.places.map((p) => p.name), ['Inani', 'Himchari']);
    expect(issue.places.first.posts, 2);
  });

  test('stats add up posts, media and the ledger', () {
    final issue = ScrapbookIssue.build(
      days: _days,
      posts: [
        _post('a', images: [_img, _img, _img], likes: 2),
        _post('r', reel: true, comments: 1, author: 'babu@x.com'),
      ],
      expenses: [
        ExpenseItem(
            id: 'e1',
            tourId: 't1',
            title: 'Fish',
            amountPaisa: 150000,
            category: 'Food',
            date: DateTime(2026, 10, 25)),
        ExpenseItem(
            id: 'e2',
            tourId: 't1',
            title: 'Bus',
            amountPaisa: 90000,
            category: 'Transport',
            date: DateTime(2026, 10, 25)),
        ExpenseItem(
            id: 'e3',
            tourId: 't1',
            title: 'Tea',
            amountPaisa: 10000,
            category: 'Food',
            date: DateTime(2026, 10, 25)),
      ],
    );
    final s = issue.stats;
    expect(s.posts, 2);
    expect(s.photos, 3);
    expect(s.reels, 1);
    expect(s.likes, 2);
    expect(s.comments, 1);
    expect(s.contributors, 2);
    expect(s.spentPaisa, 250000);
    expect(s.topSpendCategory, 'Food');
    expect(s.days, 2);
  });

  test('quotes drop hashtags and need a real sentence', () {
    final issue = ScrapbookIssue.build(posts: [
      _post('a', caption: '#sea #fun'),
      _post('b', caption: 'The best sunrise of my life #inani', likes: 1),
    ]);
    expect(issue.quotes.single.text, 'The best sunrise of my life');
  });

  test("a member's recap counts only their own posts and awards", () {
    final posts = [
      _post('a', author: 'Rina@x.com', likes: 3, location: 'Inani'),
      _post('b', author: 'rina@x.com', reel: true, comments: 2),
      _post('c', author: 'babu@x.com', likes: 9),
    ];
    final issue = ScrapbookIssue.build(posts: posts);
    final recap = issue.recapFor('RINA@x.com', posts);
    expect(recap.posts, 2);
    expect(recap.photos, 1);
    expect(recap.reels, 1);
    expect(recap.likesReceived, 3);
    expect(recap.commentsReceived, 2);
    expect(recap.places, 1);
    expect(recap.bestPost!.id, 'a');
    expect(recap.awards, contains(ScrapbookAwardKind.reelStar));
    expect(recap.awards, isNot(contains(ScrapbookAwardKind.crowdFavourite)));
    expect(issue.recapFor('nobody@x.com', posts).isEmpty, isTrue);
  });
}
