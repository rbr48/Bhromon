import 'package:flutter/material.dart';

import 'instafeed_zoomable_media.dart';
import 'tour_safe_network_image.dart';
import '../../../../../core/theme/colors.dart';

/// Interactive multi-image carousel with smooth dynamic worm dot indicators,
/// pinch-to-zoom support on every slide, and double-tap heart triggers.
class InstafeedCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final double aspectRatio;
  final VoidCallback? onDoubleTap;
  final void Function(int index)? onImageTap;
  final ColorFilter? colorFilter;

  const InstafeedCarousel({
    super.key,
    required this.imageUrls,
    this.aspectRatio = 1.0,
    this.onDoubleTap,
    this.onImageTap,
    this.colorFilter,
  });

  @override
  State<InstafeedCarousel> createState() => _InstafeedCarouselState();
}

class _InstafeedCarouselState extends State<InstafeedCarousel> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          color: Colors.grey.shade900,
          child: const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 40),
          ),
        ),
      );
    }

    final isMulti = widget.imageUrls.length > 1;

    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media PageView
          PageView.builder(
            controller: _pageCtrl,
            physics: isMulti
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: widget.imageUrls.length,
            onPageChanged: (idx) {
              setState(() => _currentIndex = idx);
            },
            itemBuilder: (context, index) {
              final url = widget.imageUrls[index];
              final imageWidget = TourSafeNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                colorFilter: widget.colorFilter,
              );

              return InstafeedZoomableMedia(
                onTap: () => widget.onImageTap?.call(index),
                onDoubleTap: widget.onDoubleTap,
                child: imageWidget,
              );
            },
          ),

          // Upper-right index badge (e.g., 2/5)
          if (isMulti)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12, width: 0.5),
                ),
                child: Text(
                  '${_currentIndex + 1}/${widget.imageUrls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

          // Bottom smooth expanding dot indicator
          if (isMulti)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.imageUrls.length, (index) {
                      final isActive = index == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.mintGreen
                              : Colors.white.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),

          // Fullscreen view icon button on bottom-right
          Positioned(
            bottom: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => widget.onImageTap?.call(_currentIndex),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: const Icon(
                    Icons.fullscreen,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
