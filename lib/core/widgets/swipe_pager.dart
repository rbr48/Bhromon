import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// A horizontal pager that changes page only when the swipe has come to rest.
///
/// The caller owns the [controller] and the selection. [onSettled] is called
/// with the page the swipe came to rest on, never midway through a drag, so a
/// neighbour page that is only half on screen changes nothing. When
/// [selectedIndex] changes from elsewhere (a chip tap, say), the pager moves to
/// it: animated, or at once when the phone asks for reduced motion. The pager
/// never moves on its own when the selection is unchanged.
///
/// A drag that starts within [edgeInset] of either screen edge is left to the
/// system, because those edges are the back gesture on iPhone and the system
/// gesture zone on Android. Disabling the pager stops swiping but keeps taps
/// and the caller's own controls working.
class SwipePager extends StatefulWidget {
  const SwipePager({
    super.key,
    required this.controller,
    required this.count,
    required this.selectedIndex,
    required this.itemBuilder,
    required this.onSettled,
    this.enabled = true,
    this.edgeInset = 24,
    this.nextLabel,
    this.previousLabel,
  });

  final PageController controller;
  final int count;
  final int selectedIndex;
  final IndexedWidgetBuilder itemBuilder;

  /// Called once a user swipe has come to rest on a different page.
  final ValueChanged<int> onSettled;
  final bool enabled;
  final double edgeInset;

  /// Labels for the screen reader's "next" and "previous" actions. Without them
  /// the pager adds no actions.
  final String? nextLabel;
  final String? previousLabel;

  @override
  State<SwipePager> createState() => _SwipePagerState();
}

class _SwipePagerState extends State<SwipePager> {
  /// Whether the pointer that is down started inside an edge dead zone.
  bool _startedAtEdge = false;

  @override
  void initState() {
    super.initState();
    _syncAfterFrame();
  }

  @override
  void didUpdateWidget(covariant SwipePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _moveTo(widget.selectedIndex);
    } else if (widget.count != oldWidget.count) {
      _syncAfterFrame();
    }
  }

  /// Places the pager on the selected page once the controller has a position,
  /// for the first build and for a list that arrives after the first frame.
  void _syncAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moveTo(widget.selectedIndex, animate: false);
    });
  }

  /// Moves the pager to [index] unless it is already there.
  void _moveTo(int index, {bool animate = true}) {
    if (index < 0 || index >= widget.count) return;
    final controller = widget.controller;
    if (!controller.hasClients) return;
    if (controller.page?.round() == index) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!animate || reduceMotion) {
      controller.jumpToPage(index);
    } else {
      controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    // Only the horizontal pager counts. The lists inside a page scroll vertically.
    if (notification.metrics.axis != Axis.horizontal) return false;
    final page = widget.controller.page?.round();
    if (page != null &&
        page >= 0 &&
        page < widget.count &&
        page != widget.selectedIndex) {
      HapticFeedback.selectionClick();
      widget.onSettled(page);
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_startedAtEdge || !_inEdgeZone(event.localPosition)) return;
    setState(() => _startedAtEdge = true);
  }

  void _onPointerEnd() {
    if (_startedAtEdge) setState(() => _startedAtEdge = false);
  }

  bool _inEdgeZone(Offset local) {
    final width = (context.findRenderObject() as RenderBox?)?.size.width;
    if (width == null) return false;
    return local.dx < widget.edgeInset || local.dx > width - widget.edgeInset;
  }

  void _step(int by) {
    if (!widget.enabled) return;
    final target = widget.selectedIndex + by;
    if (target < 0 || target >= widget.count) return;
    _moveTo(target);
    widget.onSettled(target);
  }

  @override
  Widget build(BuildContext context) {
    final pageView = PageView.builder(
      controller: widget.controller,
      itemCount: widget.count,
      physics: widget.enabled && !_startedAtEdge
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemBuilder: widget.itemBuilder,
    );

    final swipeable = NotificationListener<ScrollEndNotification>(
      onNotification: _onScrollEnd,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: (_) => _onPointerEnd(),
        onPointerCancel: (_) => _onPointerEnd(),
        child: pageView,
      ),
    );

    final next = widget.nextLabel;
    final previous = widget.previousLabel;
    if (next == null || previous == null || !widget.enabled) return swipeable;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: previous): () => _step(-1),
        CustomSemanticsAction(label: next): () => _step(1),
      },
      child: swipeable,
    );
  }
}
