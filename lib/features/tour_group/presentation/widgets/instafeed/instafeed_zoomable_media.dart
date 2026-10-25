import 'package:flutter/material.dart';

/// Wraps feed media with smooth two-finger pinch-to-zoom and automatic
/// springback translation/scale reset on finger lift.
class InstafeedZoomableMedia extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDoubleTap;

  const InstafeedZoomableMedia({
    super.key,
    required this.child,
    this.onDoubleTap,
  });

  @override
  State<InstafeedZoomableMedia> createState() => _InstafeedZoomableMediaState();
}

class _InstafeedZoomableMediaState extends State<InstafeedZoomableMedia>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformCtrl = TransformationController();
  late AnimationController _animCtrl;
  Animation<Matrix4>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_resetAnimation != null) {
          _transformCtrl.value = _resetAnimation!.value;
        }
      });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (_transformCtrl.value == Matrix4.identity()) return;

    _resetAnimation = Matrix4Tween(
      begin: _transformCtrl.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    ));

    _animCtrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: widget.onDoubleTap,
      child: ClipRect(
        child: InteractiveViewer(
          transformationController: _transformCtrl,
          clipBehavior: Clip.none,
          minScale: 1.0,
          maxScale: 3.5,
          panEnabled: true,
          scaleEnabled: true,
          onInteractionEnd: _onInteractionEnd,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Floating heart burst animation that pops in on double tap.
class InstafeedHeartBurst extends StatefulWidget {
  final bool show;
  final VoidCallback? onComplete;

  const InstafeedHeartBurst({
    super.key,
    required this.show,
    this.onComplete,
  });

  @override
  State<InstafeedHeartBurst> createState() => _InstafeedHeartBurstState();
}

class _InstafeedHeartBurstState extends State<InstafeedHeartBurst>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      });

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.3)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
    ]).animate(_ctrl);

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_ctrl);

    if (widget.show) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant InstafeedHeartBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show && !_ctrl.isAnimating) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            return Opacity(
              opacity: _opacity.value,
              child: Transform.scale(
                scale: _scale.value,
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 100,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
