import 'package:flutter/material.dart';
import '../theme/theme_context.dart';

/// Shimmer skeleton placeholders shown while content loads.
///
/// No third-party dependency: a single [Shimmer] wrapper animates a gradient
/// sweep over plain [SkeletonBox] shapes via [ShaderMask], so one controller
/// drives an arbitrary composition of boxes.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color highlight = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final double dx = (_controller.value * 2 - 0.5) * bounds.width * 2;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                highlight,
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradientTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double dx;
  const _SlideGradientTransform(this.dx);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx - bounds.width, 0, 0);
}

/// A single skeleton shape.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 10,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.black.withValues(alpha: 0.05),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder matching a feed post card: author row, text lines, media block.
class FeedCardSkeleton extends StatelessWidget {
  const FeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SkeletonBox(height: 40, circle: true),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 140, height: 13),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonBox(height: 13),
          const SizedBox(height: 6),
          const SkeletonBox(width: 220, height: 13),
          const SizedBox(height: 12),
          const SkeletonBox(height: 180, radius: 12),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              3,
              (_) => const Padding(
                padding: EdgeInsets.only(right: 14),
                child: SkeletonBox(width: 56, height: 22, radius: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical list of [FeedCardSkeleton]s wrapped in one shimmer sweep.
class FeedListSkeleton extends StatelessWidget {
  final int count;
  const FeedListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: List.generate(count, (_) => const FeedCardSkeleton()),
      ),
    );
  }
}

/// Horizontal card strip placeholder (stories / pro-tip sliders).
class HorizontalCardsSkeleton extends StatelessWidget {
  final double cardWidth;
  final double cardHeight;
  const HorizontalCardsSkeleton({
    super.key,
    this.cardWidth = 130,
    this.cardHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SizedBox(
        height: cardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, __) =>
              SkeletonBox(width: cardWidth, height: cardHeight, radius: 14),
        ),
      ),
    );
  }
}

/// Panel placeholder (profile sections, rank cards, stats).
class PanelSkeleton extends StatelessWidget {
  final double height;
  const PanelSkeleton({super.key, this.height = 96});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfacePanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderFaint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkeletonBox(width: 120, height: 12),
            const SizedBox(height: 12),
            SkeletonBox(height: height - 60, radius: 10),
          ],
        ),
      ),
    );
  }
}
