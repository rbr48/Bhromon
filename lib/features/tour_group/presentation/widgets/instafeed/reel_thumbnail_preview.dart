import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../../core/theme/colors.dart';

/// Renders the first frame of a remote video URL as an instant thumbnail poster.
/// Used for reels and videos that do not yet have a dedicated static cover image URL.
class ReelThumbnailPreview extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;
  final Widget? placeholder;

  const ReelThumbnailPreview({
    super.key,
    required this.videoUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<ReelThumbnailPreview> createState() => _ReelThumbnailPreviewState();
}

class _ReelThumbnailPreviewState extends State<ReelThumbnailPreview> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  @override
  void didUpdateWidget(covariant ReelThumbnailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _controller?.dispose();
      _controller = null;
      _initialized = false;
      _hasError = false;
      _initThumbnail();
    }
  }

  Future<void> _initThumbnail() async {
    if (widget.videoUrl.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = ctrl;
      await ctrl.initialize();
      await ctrl.setVolume(0.0);
      await ctrl.pause();
      await ctrl.seekTo(Duration.zero);
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized &&
        _controller != null &&
        _controller!.value.isInitialized) {
      final size = _controller!.value.size;
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width > 0 ? size.width : 360,
              height: size.height > 0 ? size.height : 640,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
      );
    }

    if (_hasError) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF262626), Color(0xFF141414)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.slow_motion_video,
              color: AppColors.mintGreen, size: 28),
        ),
      );
    }

    return widget.placeholder ??
        Container(
          color: const Color(0xFF141414),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.mintGreen,
              ),
            ),
          ),
        );
  }
}
