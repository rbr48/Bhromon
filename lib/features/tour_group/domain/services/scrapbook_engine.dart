import '../models/date_codec.dart';
import '../models/expense_models.dart';
import '../models/tour_group.dart';
import '../models/tour_post_models.dart';

/// The tour magazine, built only from what the family actually posted, who
/// was on the tour and what the ledger recorded. Pages and awards appear only
/// when there is real data behind them; nothing is invented.
class ScrapbookIssue {
  const ScrapbookIssue({
    required this.coverPost,
    required this.chapters,
    required this.stats,
    required this.awards,
    required this.topMoments,
    required this.places,
    required this.quotes,
  });

  /// The most loved photo post, or null when nobody has posted a photo yet.
  final TourPostItem? coverPost;

  /// One chapter per tour day that has posts, in the order they happened.
  final List<ScrapbookChapter> chapters;

  final ScrapbookStats stats;

  /// Awards whose winner passed the award's minimum.
  final List<ScrapbookAward> awards;

  /// The best-received posts with media, best first. At most five.
  final List<TourPostItem> topMoments;

  /// Places posted from, in the order they were first visited.
  final List<ScrapbookPlace> places;

  /// The best-received captions long enough to quote. At most three.
  final List<ScrapbookQuote> quotes;

  bool get isEmpty => stats.posts == 0;

  /// The posts that count are the visible ones: archived posts are left out.
  static ScrapbookIssue build({
    required List<TourPostItem> posts,
    List<TourMember> members = const [],
    List<ExpenseItem> expenses = const [],
    List<TourDayInfo> days = const [],
  }) {
    final visible = posts.where((p) => !p.isArchived).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final people = _People(members, visible);

    return ScrapbookIssue(
      coverPost: _pickCover(visible),
      chapters: _chapters(visible, days),
      stats: _stats(visible, expenses, days),
      awards: _awards(visible, people),
      topMoments: _topMoments(visible),
      places: _places(visible),
      quotes: _quotes(visible, people),
    );
  }

  /// One member's own page: what they posted and what it earned.
  ScrapbookRecap recapFor(String email, List<TourPostItem> posts) {
    final me = normalizeEmail(email);
    final mine = posts
        .where((p) => !p.isArchived && normalizeEmail(p.authorEmail) == me)
        .toList();
    final places = <String>{
      for (final p in mine)
        if (p.location.trim().isNotEmpty) p.location.trim().toLowerCase(),
    };
    TourPostItem? best;
    for (final p in mine) {
      if (best == null || _score(p) > _score(best)) best = p;
    }
    return ScrapbookRecap(
      posts: mine.length,
      photos:
          mine.where((p) => !p.isReel).fold(0, (n, p) => n + p.images.length),
      reels: mine.where((p) => p.isReel).length,
      likesReceived: mine.fold(0, (n, p) => n + p.likes.length),
      commentsReceived: mine.fold(0, (n, p) => n + p.commentCount),
      places: places.length,
      awards: [
        for (final a in awards)
          if (normalizeEmail(a.winnerEmail) == me) a.kind
      ],
      bestPost: best,
    );
  }

  // ── Building blocks ──────────────────────────────────────────────────────

  /// Likes count twice as much as comments.
  static int _score(TourPostItem p) => p.likes.length * 2 + p.commentCount;

  /// Higher score first; on a tie the newer post wins.
  static int _byScore(TourPostItem a, TourPostItem b) {
    final s = _score(b).compareTo(_score(a));
    return s != 0 ? s : b.createdAt.compareTo(a.createdAt);
  }

  static TourPostItem? _pickCover(List<TourPostItem> posts) {
    final photos = posts
        .where((p) => !p.isReel && p.images.isNotEmpty && p.hasRemoteMedia)
        .toList()
      ..sort(_byScore);
    return photos.isEmpty ? null : photos.first;
  }

  static List<ScrapbookChapter> _chapters(
      List<TourPostItem> posts, List<TourDayInfo> days) {
    final dayById = {for (final d in days) d.id: d};
    final groups = <String, List<TourPostItem>>{};
    for (final p in posts) {
      // A post on a known tour day goes to that day; any other post goes to
      // the calendar date it was made on.
      final key = dayById.containsKey(p.tourDay)
          ? p.tourDay
          : 'date:${_dateKey(p.createdAt)}';
      groups.putIfAbsent(key, () => []).add(p);
    }

    final chapters = <ScrapbookChapter>[];
    for (final entry in groups.entries) {
      final dayPosts = entry.value; // already oldest first
      final day = dayById[entry.key];
      final media = dayPosts.where((p) => p.hasRemoteMedia).toList()
        ..sort(_byScore);
      chapters.add(ScrapbookChapter(
        day: day,
        date: day?.date ?? dayPosts.first.createdAt,
        posts: dayPosts,
        hero: media.isEmpty ? null : media.first,
        gallery: media.skip(1).take(4).toList(),
        places: _places(dayPosts).map((p) => p.name).toList(),
        likes: dayPosts.fold(0, (n, p) => n + p.likes.length),
      ));
    }
    chapters.sort((a, b) {
      final ad = a.day?.dayNumber, bd = b.day?.dayNumber;
      if (ad != null && bd != null) return ad.compareTo(bd);
      return a.posts.first.createdAt.compareTo(b.posts.first.createdAt);
    });
    return chapters;
  }

  static ScrapbookStats _stats(List<TourPostItem> posts,
      List<ExpenseItem> expenses, List<TourDayInfo> days) {
    final byCategory = <String, int>{};
    for (final e in expenses) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amountPaisa;
    }
    String? topCategory;
    for (final entry in byCategory.entries) {
      if (topCategory == null || entry.value > byCategory[topCategory]!) {
        topCategory = entry.key;
      }
    }
    return ScrapbookStats(
      posts: posts.length,
      photos:
          posts.where((p) => !p.isReel).fold(0, (n, p) => n + p.images.length),
      reels: posts.where((p) => p.isReel).length,
      likes: posts.fold(0, (n, p) => n + p.likes.length),
      comments: posts.fold(0, (n, p) => n + p.commentCount),
      places: _places(posts).length,
      contributors:
          posts.map((p) => normalizeEmail(p.authorEmail)).toSet().length,
      spentPaisa: expenses.fold(0, (n, e) => n + e.amountPaisa),
      topSpendCategory: topCategory,
      days: days.length,
    );
  }

  static List<ScrapbookAward> _awards(
      List<TourPostItem> posts, _People people) {
    final awards = <ScrapbookAward>[];

    void add(ScrapbookAwardKind kind, Map<String, int> tally, int minimum) {
      String? winner;
      for (final entry in tally.entries) {
        if (entry.value < minimum) continue;
        if (winner == null ||
            entry.value > tally[winner]! ||
            (entry.value == tally[winner]! &&
                people.name(entry.key).compareTo(people.name(winner)) < 0)) {
          winner = entry.key;
        }
      }
      if (winner == null) return;
      awards.add(ScrapbookAward(
        kind: kind,
        winnerEmail: winner,
        winnerName: people.name(winner),
        winnerPhoto: people.photo(winner),
        value: tally[winner]!,
      ));
    }

    Map<String, int> tally(int Function(TourPostItem p) count) {
      final out = <String, int>{};
      for (final p in posts) {
        final who = normalizeEmail(p.authorEmail);
        out[who] = (out[who] ?? 0) + count(p);
      }
      return out;
    }

    add(ScrapbookAwardKind.photographer,
        tally((p) => p.isReel ? 0 : p.images.length), 1);
    add(ScrapbookAwardKind.reelStar, tally((p) => p.isReel ? 1 : 0), 1);

    // The single most-liked post earns its author the crowd favourite.
    final best = <String, int>{};
    for (final p in posts) {
      final who = normalizeEmail(p.authorEmail);
      if (p.likes.length > (best[who] ?? 0)) best[who] = p.likes.length;
    }
    add(ScrapbookAwardKind.crowdFavourite, best, 1);

    add(ScrapbookAwardKind.storyteller, tally((p) => p.caption.trim().length),
        40);
    add(ScrapbookAwardKind.conversationStarter, tally((p) => p.commentCount),
        1);

    final placesBy = <String, Set<String>>{};
    for (final p in posts) {
      final place = p.location.trim().toLowerCase();
      if (place.isEmpty) continue;
      placesBy.putIfAbsent(normalizeEmail(p.authorEmail), () => {}).add(place);
    }
    add(ScrapbookAwardKind.explorer,
        {for (final e in placesBy.entries) e.key: e.value.length}, 2);

    // Tagged in someone else's post.
    final tagged = <String, int>{};
    for (final p in posts) {
      final author = normalizeEmail(p.authorEmail);
      for (final t in p.tags.map(normalizeEmail).toSet()) {
        if (t == author) continue;
        tagged[t] = (tagged[t] ?? 0) + 1;
      }
    }
    add(ScrapbookAwardKind.mostTagged, tagged, 1);

    return awards;
  }

  static List<TourPostItem> _topMoments(List<TourPostItem> posts) {
    final media = posts.where((p) => p.hasRemoteMedia && _score(p) > 0).toList()
      ..sort(_byScore);
    return media.take(5).toList();
  }

  static List<ScrapbookPlace> _places(List<TourPostItem> posts) {
    final order = <String>[];
    final byKey = <String, ScrapbookPlace>{};
    for (final p in posts) {
      final name = p.location.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final known = byKey[key];
      if (known == null) {
        order.add(key);
        byKey[key] =
            ScrapbookPlace(name: name, firstVisit: p.createdAt, posts: 1);
      } else {
        byKey[key] = ScrapbookPlace(
            name: known.name,
            firstVisit: known.firstVisit,
            posts: known.posts + 1);
      }
    }
    return [for (final k in order) byKey[k]!];
  }

  static List<ScrapbookQuote> _quotes(
      List<TourPostItem> posts, _People people) {
    final quotable = posts.where((p) => _quoteText(p).length >= 20).toList()
      ..sort(_byScore);
    return [
      for (final p in quotable.take(3))
        ScrapbookQuote(
          text: _quoteText(p),
          authorName: people.name(normalizeEmail(p.authorEmail),
              fallback: p.authorName),
          post: p,
        ),
    ];
  }

  /// The caption without hashtags, which read badly as a quote.
  static String _quoteText(TourPostItem p) => p.caption
      .replaceAll(RegExp(r'#\S+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Who was on the tour, for names and photos. A post's author name is used
/// when the member list does not have them (for example, someone who left).
class _People {
  _People(List<TourMember> members, List<TourPostItem> posts) {
    for (final p in posts) {
      final key = normalizeEmail(p.authorEmail);
      _names.putIfAbsent(key, () => p.authorName);
      if (p.authorPhoto != null) _photos.putIfAbsent(key, () => p.authorPhoto);
    }
    for (final m in members) {
      final key = normalizeEmail(m.email);
      if (m.displayName.trim().isNotEmpty) _names[key] = m.displayName;
      if (m.photoUrl != null) _photos[key] = m.photoUrl;
    }
  }

  final _names = <String, String>{};
  final _photos = <String, String?>{};

  String name(String email, {String? fallback}) =>
      _names[email] ?? fallback ?? email.split('@').first;

  String? photo(String email) => _photos[email];
}

class ScrapbookChapter {
  const ScrapbookChapter({
    required this.day,
    required this.date,
    required this.posts,
    required this.hero,
    required this.gallery,
    required this.places,
    required this.likes,
  });

  /// The tour day, or null for posts made outside the planned days.
  final TourDayInfo? day;
  final DateTime date;

  /// Every post of the day, oldest first.
  final List<TourPostItem> posts;

  /// The day's best post with media, shown large.
  final TourPostItem? hero;

  /// Up to four more posts with media, best first.
  final List<TourPostItem> gallery;

  final List<String> places;
  final int likes;
}

class ScrapbookStats {
  const ScrapbookStats({
    required this.posts,
    required this.photos,
    required this.reels,
    required this.likes,
    required this.comments,
    required this.places,
    required this.contributors,
    required this.spentPaisa,
    required this.topSpendCategory,
    required this.days,
  });

  final int posts;
  final int photos;
  final int reels;
  final int likes;
  final int comments;
  final int places;
  final int contributors;

  /// Everything the ledger recorded, in paisa.
  final int spentPaisa;

  /// The ledger category with the most money spent, or null with no expenses.
  final String? topSpendCategory;

  final int days;
}

enum ScrapbookAwardKind {
  photographer,
  reelStar,
  crowdFavourite,
  storyteller,
  conversationStarter,
  explorer,
  mostTagged,
}

class ScrapbookAward {
  const ScrapbookAward({
    required this.kind,
    required this.winnerEmail,
    required this.winnerName,
    required this.winnerPhoto,
    required this.value,
  });

  final ScrapbookAwardKind kind;
  final String winnerEmail;
  final String winnerName;
  final String? winnerPhoto;

  /// What the award counts: photos, reels, likes on the best post, caption
  /// characters, comments, places or tags.
  final int value;
}

class ScrapbookPlace {
  const ScrapbookPlace({
    required this.name,
    required this.firstVisit,
    required this.posts,
  });

  final String name;
  final DateTime firstVisit;
  final int posts;
}

class ScrapbookQuote {
  const ScrapbookQuote({
    required this.text,
    required this.authorName,
    required this.post,
  });

  final String text;
  final String authorName;
  final TourPostItem post;
}

class ScrapbookRecap {
  const ScrapbookRecap({
    required this.posts,
    required this.photos,
    required this.reels,
    required this.likesReceived,
    required this.commentsReceived,
    required this.places,
    required this.awards,
    required this.bestPost,
  });

  final int posts;
  final int photos;
  final int reels;
  final int likesReceived;
  final int commentsReceived;
  final int places;
  final List<ScrapbookAwardKind> awards;
  final TourPostItem? bestPost;

  bool get isEmpty => posts == 0;
}
