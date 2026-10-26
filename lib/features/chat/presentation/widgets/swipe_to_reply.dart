import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WhatsApp-style swipe-to-reply gesture wrapper.
///
/// Wraps any message bubble. When dragged horizontally, displays a smooth
/// circular reply icon that scales up, gives haptic feedback, and triggers
/// [onReply] upon release.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool isMe;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.isMe = false,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Animation<double> _animation;

  double _dragOffset = 0.0;
  bool _thresholdTriggered = false;
  static const double _kTriggerThreshold = 45.0;
  static const double _kMaxDrag = 70.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragOffset = _animation.value;
        });
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    // Allow dragging right for receiver messages, left or right for sender
    final newOffset = _dragOffset + delta;

    if (widget.isMe) {
      // For sender messages, dragging left
      if (newOffset <= 0 && newOffset >= -_kMaxDrag) {
        setState(() => _dragOffset = newOffset);
      }
    } else {
      // For receiver messages, dragging right
      if (newOffset >= 0 && newOffset <= _kMaxDrag) {
        setState(() => _dragOffset = newOffset);
      }
    }

    final absOffset = _dragOffset.abs();
    if (absOffset >= _kTriggerThreshold && !_thresholdTriggered) {
      _thresholdTriggered = true;
      HapticFeedback.lightImpact();
    } else if (absOffset < _kTriggerThreshold) {
      _thresholdTriggered = false;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_thresholdTriggered) {
      widget.onReply();
    }
    _thresholdTriggered = false;
    // Animate smoothly back to 0
    _animation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final absOffset = _dragOffset.abs();
    final progress = (absOffset / _kTriggerThreshold).clamp(0.0, 1.0);

    return Stack(
      clipBehavior: Clip.none,
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      children: [
        // WhatsApp reply circle icon that appears behind the bubble
        if (absOffset > 2)
          Positioned(
            left: widget.isMe ? null : 8,
            right: widget.isMe ? 8 : null,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.5 + (0.5 * progress),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _thresholdTriggered
                        ? const Color(0xFF00A884)
                        : const Color(0xFF1F2C34),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.reply_rounded,
                    color: _thresholdTriggered ? Colors.white : const Color(0xFF8696A0),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),

        // The message bubble transformed by drag
        GestureDetector(
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
