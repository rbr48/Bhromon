import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:bhromon/core/theme/forest_palette.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import 'instafeed_zoomable_media.dart';
import 'tour_safe_network_image.dart';

/// Interactive multi-image carousel with smooth dynamic worm dot indicators,
/// pinch-to-zoom support on every slide, desktop mouse/trackpad drag swiping,
/// clickable pagination dots, and desktop chevron navigation buttons.
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

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.imageUrls.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToPage(int index) {
    if (index >= 0 &&
        index < widget.imageUrls.length &&
        index != _currentIndex) {
      _pageCtrl.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
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

    return ClipRect(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // Media PageView with mouse, trackpad, and touch drag support
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: PageView.builder(
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
            ),

            // Left Chevron Navigation Button (desktop & tablet friendly)
            if (isMulti && _currentIndex > 0)
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: CarouselNavButton(
                    key: const ValueKey('carousel_prev_button'),
                    icon: Icons.chevron_left_rounded,
                    tooltip: context.l10n.translate('ig_prev_photo'),
                    onPressed: _goToPrevious,
                  ),
                ),
              ),

            // Right Chevron Navigation Button (desktop & tablet friendly)
            if (isMulti && _currentIndex < widget.imageUrls.length - 1)
              Positioned(
                right: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: CarouselNavButton(
                    key: const ValueKey('carousel_next_button'),
                    icon: Icons.chevron_right_rounded,
                    tooltip: context.l10n.translate('ig_next_photo'),
                    onPressed: _goToNext,
                  ),
                ),
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

            // Bottom smooth expanding dot indicator with clickable dots
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
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(widget.imageUrls.length, (index) {
                        final isActive = index == _currentIndex;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goToPage(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 4),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                width: isActive ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppColors.mintGreen
                                      : context.forest.text
                                          .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
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
                      Icons.fullscreen_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// High-contrast circular navigation button with hover glow effect for carousels.
class CarouselNavButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;
  final double iconSize;

  const CarouselNavButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 36,
    this.iconSize = 22,
  });

  @override
  State<CarouselNavButton> createState() => _CarouselNavButtonState();
}

class _CarouselNavButtonState extends State<CarouselNavButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered
                  ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                  : Colors.black.withValues(alpha: 0.60),
              border: Border.all(
                color: _isHovered
                    ? AppColors.mintGreen
                    : Colors.white.withValues(alpha: 0.28),
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? AppColors.mintGreen.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.40),
                  blurRadius: _isHovered ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _isHovered ? AppColors.mintGreen : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
