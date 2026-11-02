import 'dart:math' as math;

import 'package:bhromon/features/tour_group/presentation/widgets/instafeed/feed_resume.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The feed's page size, as the screen loads it.
const int _pageSize = 60;

List<String> _posts(int count, String prefix) =>
    [for (var i = 0; i < count; i++) '$prefix$i'];

Map<String, int> _indexOf(List<String> ids) =>
    {for (var i = 0; i < ids.length; i++) ids[i]: i};

/// Rows are 150 to 349 px tall, varying by post, so positions are not a simple
/// multiple of one height.
double _heightOf(String id) =>
    150 +
    (id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % 200).toDouble();

/// The scroll offset at the top of the post at [index].
double _topOf(List<String> ids, int index) =>
    ids.take(index).fold<double>(0, (sum, id) => sum + _heightOf(id));

FeedRow _row(int index, String id, double top, double height) =>
    FeedRow(index: index, id: id, top: top, height: height);

/// What the screen notes when the user leaves: the post at the top, and where
/// it sits.
FeedResume _leave(_FakeFeed feed) {
  final pixels = feed.controller.offset;
  final rows = layoutFeedRows(feed.keys, feed.indexOf);
  final anchor = pickFeedAnchor(rows, pixels);
  return FeedResume()
    ..pixels = pixels
    ..anchorPostId = anchor?.postId
    ..anchorDy = anchor?.dy ?? 0
    ..averageHeight = averageFeedRowHeight(rows);
}

/// The feed list, built as the screen builds it: one keyed row per post, in a
/// CustomScrollView with the screen's cache extent.
Widget _feedTree(
  List<String> ids,
  Map<String, GlobalKey> keys,
  ScrollController controller,
) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        controller: controller,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final id = ids[index];
                return RepaintBoundary(
                  key: keys.putIfAbsent(id, () => GlobalKey()),
                  child: SizedBox(height: _heightOf(id), child: Text(id)),
                );
              },
              childCount: ids.length,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One visit to the feed: its list, its paging, and the steps the screen takes
/// to get back to a saved place.
class _FakeFeed {
  _FakeFeed(this.all, {int? loaded}) : loaded = loaded ?? all.length;

  final List<String> all;
  int loaded;
  final ScrollController controller = ScrollController();
  final Map<String, GlobalKey> keys = {};
  int? loadRequestedFor;
  double? restoredTo;

  List<String> get shown => all.take(loaded).toList();
  Map<String, int> get indexOf => _indexOf(shown);
  bool get hasMore => loaded < all.length;

  Future<void> show(WidgetTester tester) =>
      tester.pumpWidget(_feedTree(shown, keys, controller));

  /// Runs the screen's restore, one frame at a time, until it finishes.
  Future<void> restore(WidgetTester tester, FeedResume resume) async {
    for (var attempt = 0; attempt < 240; attempt++) {
      final position = controller.position;
      final rows = layoutFeedRows(keys, indexOf);
      final anchorId = resume.anchorPostId;
      final index = anchorId == null ? null : indexOf[anchorId];
      final anchorKey = anchorId == null ? null : keys[anchorId];
      final anchorBox = anchorKey == null ? null : laidOutRow(anchorKey);
      final known = restoredTo;
      final step = planFeedRestore(
        resume: resume,
        userScrolled: feedMovedByUser(
          pixels: position.pixels,
          restoredTo: known,
          maxExtent: position.maxScrollExtent,
        ),
        anchorListed: index != null,
        hasMore: hasMore,
        loadRequested: loadRequestedFor == shown.length,
        anchorTop: anchorBox == null ? null : feedRowTop(anchorBox),
        estimate: index == null
            ? null
            : estimateFeedOffset(
                rows: rows,
                index: index,
                averageHeight: resume.averageHeight > 0
                    ? resume.averageHeight
                    : averageFeedRowHeight(rows),
              ),
        outOfTime: attempt == 239,
        maxExtent: position.maxScrollExtent,
      );
      if (step.loadMore) {
        loadRequestedFor = shown.length;
        loaded = math.min(loaded + _pageSize, all.length);
        await show(tester);
      }
      final target = step.jumpTo;
      if (target != null) {
        restoredTo = target;
        controller.jumpTo(target);
      }
      await tester.pump();
      if (step.finished) return;
    }
    fail('the feed did not finish restoring');
  }
}

void main() {
  group('pickFeedAnchor', () {
    final rows = [
      _row(0, 'a', 0, 100),
      _row(1, 'b', 100, 100),
      _row(2, 'c', 200, 100),
    ];

    test('takes the post that holds the top edge, with its offset from it', () {
      final anchor = pickFeedAnchor(rows, 150)!;
      expect(anchor.postId, 'b');
      expect(anchor.dy, -50);
    });

    test('a post that ends exactly at the top edge is not on screen', () {
      final anchor = pickFeedAnchor(rows, 200)!;
      expect(anchor.postId, 'c');
      expect(anchor.dy, 0);
    });

    test('a post that starts below the top edge has a positive offset', () {
      final anchor = pickFeedAnchor([_row(0, 'a', 50, 100)], 0)!;
      expect(anchor.postId, 'a');
      expect(anchor.dy, 50);
    });

    test('is null when nothing is on screen', () {
      expect(pickFeedAnchor(rows, 300), isNull);
      expect(pickFeedAnchor(const [], 0), isNull);
    });
  });

  group('estimateFeedOffset', () {
    test('extends from the laid-out row nearest to the target', () {
      final rows = [_row(10, 'a', 1000, 100), _row(12, 'b', 1300, 100)];
      expect(
        estimateFeedOffset(rows: rows, index: 20, averageHeight: 100),
        2100,
      );
      expect(
        estimateFeedOffset(rows: rows, index: 0, averageHeight: 100),
        0,
      );
    });

    test('is null with no rows laid out', () {
      expect(
        estimateFeedOffset(rows: const [], index: 3, averageHeight: 100),
        isNull,
      );
    });
  });

  group('feedMovedByUser', () {
    test('before any restore, only a feed off the top counts as moved', () {
      expect(
        feedMovedByUser(pixels: 0, restoredTo: null, maxExtent: 5000),
        isFalse,
      );
      expect(
        feedMovedByUser(pixels: 10, restoredTo: null, maxExtent: 5000),
        isTrue,
      );
    });

    test('after a restore, moving away from the target counts', () {
      expect(
        feedMovedByUser(pixels: 1000, restoredTo: 1000, maxExtent: 5000),
        isFalse,
      );
      expect(
        feedMovedByUser(pixels: 1010, restoredTo: 1000, maxExtent: 5000),
        isTrue,
      );
    });

    test('a target the feed was clamped to is not a move by the user', () {
      // The extent shrank below the target, so Flutter clamped the offset.
      expect(
        feedMovedByUser(pixels: 800, restoredTo: 1000, maxExtent: 800),
        isFalse,
      );
      expect(
        feedMovedByUser(pixels: 600, restoredTo: 1000, maxExtent: 800),
        isTrue,
      );
    });
  });

  group('planFeedRestore', () {
    FeedResume resumeAt(String? id, {double pixels = 500, double dy = -40}) =>
        FeedResume()
          ..anchorPostId = id
          ..anchorDy = dy
          ..pixels = pixels;

    FeedRestorePlan planFor(
      FeedResume resume, {
      bool userScrolled = false,
      bool anchorListed = true,
      bool hasMore = false,
      bool loadRequested = false,
      double? anchorTop,
      double? estimate,
      bool outOfTime = false,
      double maxExtent = 5000,
    }) =>
        planFeedRestore(
          resume: resume,
          userScrolled: userScrolled,
          anchorListed: anchorListed,
          hasMore: hasMore,
          loadRequested: loadRequested,
          anchorTop: anchorTop,
          estimate: estimate,
          outOfTime: outOfTime,
          maxExtent: maxExtent,
        );

    test('leaves the feed where the user put it once they have scrolled', () {
      final step = planFor(resumeAt('a'), userScrolled: true, anchorTop: 1000);
      expect(step.finished, isTrue);
      expect(step.jumpTo, isNull);
    });

    test('with no anchor, goes to the saved offset or stays at the top', () {
      final saved = planFor(resumeAt(null, pixels: 800));
      expect(saved.jumpTo, 800);
      expect(saved.finished, isTrue);

      final top = planFor(resumeAt(null, pixels: 0));
      expect(top.jumpTo, isNull);
      expect(top.finished, isTrue);
    });

    test('puts a laid-out post back where it was on screen', () {
      final step = planFor(resumeAt('a', dy: -40), anchorTop: 1000);
      expect(step.jumpTo, 1040);
      expect(step.finished, isTrue);
    });

    test('asks for the next page when the post is not listed yet', () {
      final step = planFor(resumeAt('a'), anchorListed: false, hasMore: true);
      expect(step.loadMore, isTrue);
      expect(step.finished, isFalse);
    });

    test('waits while a page it asked for is on its way', () {
      final step = planFor(
        resumeAt('a'),
        anchorListed: false,
        hasMore: true,
        loadRequested: true,
      );
      expect(step.loadMore, isFalse);
      expect(step.jumpTo, isNull);
      expect(step.finished, isFalse);
    });

    test('settles for the saved offset when there are no older posts', () {
      final step = planFor(resumeAt('a', pixels: 700), anchorListed: false);
      expect(step.jumpTo, 700);
      expect(step.finished, isTrue);
    });

    test('moves towards a post that is not laid out yet', () {
      final step = planFor(resumeAt('a'), estimate: 2100);
      expect(step.jumpTo, 2100);
      expect(step.finished, isFalse);
    });

    test('stops at its best guess when it runs out of time', () {
      final step = planFor(resumeAt('a'), estimate: 2100, outOfTime: true);
      expect(step.jumpTo, 2100);
      expect(step.finished, isTrue);
    });

    test('never scrolls past the end of the feed', () {
      final step = planFor(
        resumeAt('a', dy: 0),
        anchorTop: 9000,
        maxExtent: 3000,
      );
      expect(step.jumpTo, 3000);
    });
  });

  group('coming back to the feed', () {
    testWidgets('lands on the same post after new posts arrive above it',
        (tester) async {
      final before = _posts(200, 'p');
      final first = _FakeFeed(before);
      await first.show(tester);
      await tester.pump();
      first.controller.jumpTo(2500);
      await tester.pump();
      final resume = _leave(first);
      await tester.pumpWidget(const SizedBox());
      first.controller.dispose();

      final second = _FakeFeed(['n0', 'n1', 'n2', ...before]);
      addTearDown(second.controller.dispose);
      await second.show(tester);
      await tester.pump();
      await second.restore(tester, resume);

      // The content moved down by the three new posts, so a pixel offset
      // would have landed elsewhere.
      expect(second.controller.offset, isNot(closeTo(2500, 0.5)));
      final landed = pickFeedAnchor(
        layoutFeedRows(second.keys, second.indexOf),
        second.controller.offset,
      )!;
      expect(landed.postId, resume.anchorPostId);
      expect(landed.dy, closeTo(resume.anchorDy, 0.5));
    });

    testWidgets('finds a post far down the feed after many posts arrive above',
        (tester) async {
      final before = _posts(300, 'p');
      final first = _FakeFeed(before);
      await first.show(tester);
      await tester.pump();
      first.controller.jumpTo(_topOf(before, 180) + 40);
      await tester.pump();
      final resume = _leave(first);
      expect(resume.anchorPostId, 'p180');
      await tester.pumpWidget(const SizedBox());
      first.controller.dispose();

      final second = _FakeFeed([..._posts(90, 'n'), ...before]);
      addTearDown(second.controller.dispose);
      await second.show(tester);
      await tester.pump();
      await second.restore(tester, resume);

      final landed = pickFeedAnchor(
        layoutFeedRows(second.keys, second.indexOf),
        second.controller.offset,
      )!;
      expect(landed.postId, 'p180');
      expect(landed.dy, closeTo(-40, 0.5));
    });

    testWidgets('loads the page a post is on before going back to it',
        (tester) async {
      final all = _posts(300, 'p');
      final first = _FakeFeed(all);
      await first.show(tester);
      await tester.pump();
      first.controller.jumpTo(_topOf(all, 100) + 30);
      await tester.pump();
      final resume = _leave(first);
      expect(resume.anchorPostId, 'p100');
      await tester.pumpWidget(const SizedBox());
      first.controller.dispose();

      final second = _FakeFeed(all, loaded: 60);
      addTearDown(second.controller.dispose);
      await second.show(tester);
      await tester.pump();
      await second.restore(tester, resume);

      expect(second.loaded, greaterThan(60));
      final landed = pickFeedAnchor(
        layoutFeedRows(second.keys, second.indexOf),
        second.controller.offset,
      )!;
      expect(landed.postId, 'p100');
      expect(landed.dy, closeTo(-30, 0.5));
    });

    testWidgets('falls back to the saved offset when the post is gone',
        (tester) async {
      final all = _posts(200, 'p');
      final first = _FakeFeed(all);
      await first.show(tester);
      await tester.pump();
      first.controller.jumpTo(_topOf(all, 50) + 10);
      await tester.pump();
      final resume = _leave(first);
      final saved = first.controller.offset;
      await tester.pumpWidget(const SizedBox());
      first.controller.dispose();

      final second = _FakeFeed(all.where((id) => id != 'p50').toList());
      addTearDown(second.controller.dispose);
      await second.show(tester);
      await tester.pump();
      await second.restore(tester, resume);

      expect(second.controller.offset, closeTo(saved, 0.5));
    });

    testWidgets('leaves the feed alone once the user has scrolled',
        (tester) async {
      final all = _posts(200, 'p');
      final first = _FakeFeed(all);
      await first.show(tester);
      await tester.pump();
      first.controller.jumpTo(2500);
      await tester.pump();
      final resume = _leave(first);
      await tester.pumpWidget(const SizedBox());
      first.controller.dispose();

      final second = _FakeFeed(all);
      addTearDown(second.controller.dispose);
      await second.show(tester);
      await tester.pump();
      second.controller.jumpTo(100);
      await tester.pump();
      await second.restore(tester, resume);

      expect(second.controller.offset, closeTo(100, 0.5));
    });
  });
}
