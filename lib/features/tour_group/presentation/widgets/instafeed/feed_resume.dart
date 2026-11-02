import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where the Moments feed was left for one tour: its view (the filters, the
/// sort and the layout) and the post at the top of the screen. It is kept while
/// the app runs, so coming back shows the same view at the same post, even when
/// new posts arrived in the meantime.
class FeedResume {
  String day = 'all';
  String media = 'all';
  String? hashtag;
  String? landmark;
  String? bookmarkCollection;
  bool popular = false;
  bool grid = false;

  /// The post at the top of the screen. [anchorDy] is how far its top edge sits
  /// below the screen's top edge, which is negative when it starts above.
  String? anchorPostId;
  double anchorDy = 0;

  /// The scroll offset last seen. It is used only when the anchored post is gone.
  double pixels = 0;

  /// The mean height of the posts last laid out, used to find posts far away.
  double averageHeight = 0;
}

/// A post as it is laid out: its place in the list, and its top edge and height
/// in scroll coordinates.
class FeedRow {
  const FeedRow({
    required this.index,
    required this.id,
    required this.top,
    required this.height,
  });

  final int index;
  final String id;
  final double top;
  final double height;
}

/// The post at the top of the screen, and where its top edge sits relative to
/// the screen's top edge.
class FeedAnchor {
  const FeedAnchor(this.postId, this.dy);

  final String postId;
  final double dy;
}

/// The post at the top of the screen when the feed is scrolled to [pixels]: the
/// first row whose bottom edge is still below the screen's top edge. Null when
/// no row is on screen.
FeedAnchor? pickFeedAnchor(Iterable<FeedRow> rows, double pixels) {
  FeedRow? top;
  for (final row in rows) {
    if (row.top + row.height <= pixels) continue;
    if (top == null || row.top < top.top) top = row;
  }
  return top == null ? null : FeedAnchor(top.id, top.top - pixels);
}

/// The mean height of [rows], or zero when there are none.
double averageFeedRowHeight(Iterable<FeedRow> rows) {
  var total = 0.0;
  var count = 0;
  for (final row in rows) {
    total += row.height;
    count++;
  }
  return count == 0 ? 0 : total / count;
}

/// A guess at the scroll offset of the row at [index], from the laid-out row
/// nearest to it. Null when no row is laid out.
double? estimateFeedOffset({
  required Iterable<FeedRow> rows,
  required int index,
  required double averageHeight,
}) {
  FeedRow? nearest;
  for (final row in rows) {
    if (nearest == null ||
        (row.index - index).abs() < (nearest.index - index).abs()) {
      nearest = row;
    }
  }
  if (nearest == null) return null;
  return nearest.top + (index - nearest.index) * averageHeight;
}

/// The render box of a row, when the row is laid out.
RenderBox? laidOutRow(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  return box is RenderBox && box.hasSize ? box : null;
}

/// The scroll offset at which [box] sits at the top of its viewport.
double? feedRowTop(RenderBox box) {
  if (!box.attached) return null;
  return RenderAbstractViewport.maybeOf(box)?.getOffsetToReveal(box, 0).offset;
}

/// The rows of the feed that are laid out now. [keys] holds each post's row key
/// and [indexOf] each post's place in the list.
List<FeedRow> layoutFeedRows(
  Map<String, GlobalKey> keys,
  Map<String, int> indexOf,
) {
  final rows = <FeedRow>[];
  for (final entry in keys.entries) {
    final index = indexOf[entry.key];
    final box = laidOutRow(entry.value);
    if (index == null || box == null) continue;
    final top = feedRowTop(box);
    if (top == null) continue;
    rows.add(FeedRow(
      index: index,
      id: entry.key,
      top: top,
      height: box.size.height,
    ));
  }
  return rows;
}

/// Whether the user has moved the feed since the restore last put it at
/// [restoredTo]. The target is compared within the current extent, because the
/// extent can shrink as posts lay out, and Flutter then clamps the offset to it.
bool feedMovedByUser({
  required double pixels,
  required double? restoredTo,
  required double maxExtent,
}) {
  if (restoredTo == null) return pixels > 0.5;
  final limit = maxExtent > 0 ? maxExtent : 0.0;
  final expected = restoredTo.clamp(0.0, limit).toDouble();
  return (pixels - expected).abs() > 0.5;
}

/// What the feed does next on its way back to a [FeedResume]. The screen takes
/// one step per frame until a step is [finished].
class FeedRestorePlan {
  const FeedRestorePlan({
    this.jumpTo,
    this.loadMore = false,
    this.finished = false,
  });

  /// Where to scroll to, when the step moves the feed.
  final double? jumpTo;

  /// Whether to ask for the next page of posts.
  final bool loadMore;

  /// Whether the feed is where it should be, or as close as it can get.
  final bool finished;
}

/// Decides the next step back to [resume].
///
/// [anchorTop] is the anchored post's scroll offset when it is laid out, and
/// [estimate] is where to look for it when it is not. [outOfTime] makes the step
/// the last one, at the best position so far.
FeedRestorePlan planFeedRestore({
  required FeedResume resume,
  required bool userScrolled,
  required bool anchorListed,
  required bool hasMore,
  required bool loadRequested,
  required double? anchorTop,
  required double? estimate,
  required bool outOfTime,
  required double maxExtent,
}) {
  final limit = maxExtent > 0 ? maxExtent : 0.0;
  double within(double offset) => offset.clamp(0.0, limit).toDouble();

  // The user has scrolled, so the feed stays where they put it.
  if (userScrolled) return const FeedRestorePlan(finished: true);

  final anchorId = resume.anchorPostId;
  if (anchorId == null) {
    return resume.pixels > 0
        ? FeedRestorePlan(jumpTo: within(resume.pixels), finished: true)
        : const FeedRestorePlan(finished: true);
  }

  if (!anchorListed) {
    if (hasMore && !outOfTime) {
      // Wait for a page that was already asked for, or ask for the next one.
      return loadRequested
          ? const FeedRestorePlan()
          : const FeedRestorePlan(loadMore: true);
    }
    // There are no older posts to find it in, so the saved offset is the best.
    return FeedRestorePlan(jumpTo: within(resume.pixels), finished: true);
  }

  if (anchorTop != null) {
    // The post is laid out, so put it back where it was on the screen.
    return FeedRestorePlan(
      jumpTo: within(anchorTop - resume.anchorDy),
      finished: true,
    );
  }

  // The post is not laid out yet. Move towards it and check again next frame.
  return FeedRestorePlan(
    jumpTo: within(estimate ?? resume.pixels),
    finished: outOfTime,
  );
}
