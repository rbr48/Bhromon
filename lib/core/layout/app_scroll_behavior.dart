import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The app's scrolling rules. On top of Material's, a sideways strip (member faces, channel
/// chips, prayer times, filter rows) can be dragged with a mouse.
///
/// A mouse wheel scrolls up and down only, and Flutter does not let a mouse drag a list, so
/// on a desktop browser the end of a sideways strip could not be reached at all. Lists that
/// scroll up and down are left alone: there a mouse drag selects text.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    final controller = details.controller;
    if (controller != null &&
        axisDirectionToAxis(details.direction) == Axis.horizontal) {
      return MouseDragScroll(
        controller: controller,
        reversed: details.direction == AxisDirection.left,
        child: child,
      );
    }
    return super.buildScrollbar(context, child, details);
  }
}

/// Lets a mouse drag the sideways scrollable under it. A swipe between pages (a PageView)
/// is left out: dragging there would turn the page while the user selects text on it.
class MouseDragScroll extends StatefulWidget {
  const MouseDragScroll({
    super.key,
    required this.controller,
    required this.child,
    this.reversed = false,
  });

  final ScrollController controller;
  final bool reversed;
  final Widget child;

  @override
  State<MouseDragScroll> createState() => _MouseDragScrollState();
}

class _MouseDragScrollState extends State<MouseDragScroll> {
  /// The mouse pointer that is dragging, if any.
  int? _pointer;

  ScrollPosition? get _position {
    final controller = widget.controller;
    if (!controller.hasClients || controller.positions.length != 1) return null;
    final position = controller.position;
    // A page view snaps to whole pages; it is not a strip.
    if (position is PageMetrics) return null;
    return position;
  }

  void _onDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kPrimaryMouseButton) return;
    _pointer = event.pointer;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final position = _position;
    if (position == null) return;
    if (position.maxScrollExtent <= position.minScrollExtent) return;
    final step = widget.reversed ? event.delta.dx : -event.delta.dx;
    final target = (position.pixels + step)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) position.jumpTo(target);
  }

  void _onEnd(PointerEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      child: widget.child,
    );
  }
}
