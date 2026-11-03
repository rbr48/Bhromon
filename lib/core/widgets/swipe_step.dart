import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// Reports a step of one (a day, a filter) when the person flicks or drags
/// the child sideways. The child stays a single page: the caller changes its
/// own state, so no neighbour is built or loaded.
///
/// A flick decides the direction, and a slow drag that goes far enough
/// decides it too. A swipe to the left reports `1` (next), a swipe to the right
/// reports `-1` (previous). A drag that starts within [edgeInset] of either
/// screen edge is left to the system, as in [SwipePager]. Vertical drags go to
/// the child (a list), and a horizontal scroll inside the child, such as a chip
/// strip, takes the drag first. Disabling it keeps the child's own controls.
///
/// [nextLabel] and [previousLabel] add the screen reader's matching actions.
class SwipeStep extends StatefulWidget {
  const SwipeStep({
    super.key,
    required this.child,
    required this.onStep,
    this.enabled = true,
    this.edgeInset = 24,
    this.minVelocity = 300,
    this.minDistance = 80,
    this.nextLabel,
    this.previousLabel,
  });

  final Widget child;

  /// Called with `1` for the next step and `-1` for the previous one.
  final ValueChanged<int> onStep;
  final bool enabled;
  final double edgeInset;

  /// Pixels per second for a flick, and pixels for a slow drag.
  final double minVelocity;
  final double minDistance;

  final String? nextLabel;
  final String? previousLabel;

  @override
  State<SwipeStep> createState() => _SwipeStepState();
}

class _SwipeStepState extends State<SwipeStep> {
  double _dragged = 0;
  bool _startedAtEdge = false;

  void _onDragStart(DragStartDetails details) {
    _dragged = 0;
    final width = context.size?.width ?? 0;
    final x = details.localPosition.dx;
    _startedAtEdge =
        width > 0 && (x < widget.edgeInset || x > width - widget.edgeInset);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragged += details.delta.dx;
  }

  void _onDragEnd(DragEndDetails details) {
    final startedAtEdge = _startedAtEdge;
    _startedAtEdge = false;
    if (!widget.enabled || startedAtEdge) return;
    final velocity = details.primaryVelocity ?? 0;
    final flick = velocity.abs() >= widget.minVelocity;
    final far = _dragged.abs() >= widget.minDistance;
    if (!flick && !far) return;
    final towardsNext = flick ? velocity < 0 : _dragged < 0;
    _step(towardsNext ? 1 : -1);
  }

  void _onDragCancel() {
    _dragged = 0;
    _startedAtEdge = false;
  }

  void _step(int by) {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onStep(by);
  }

  @override
  Widget build(BuildContext context) {
    final gesture = GestureDetector(
      onHorizontalDragStart: widget.enabled ? _onDragStart : null,
      onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
      onHorizontalDragCancel: _onDragCancel,
      child: widget.child,
    );

    final next = widget.nextLabel;
    final previous = widget.previousLabel;
    if (next == null || previous == null || !widget.enabled) return gesture;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: previous): () => _step(-1),
        CustomSemanticsAction(label: next): () => _step(1),
      },
      child: gesture,
    );
  }
}
