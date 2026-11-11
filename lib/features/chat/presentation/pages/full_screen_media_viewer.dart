import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/utils/image_sizing.dart';

/// Full-screen viewer for chat images and videos.
///
/// • Images support pinch-to-zoom via [InteractiveViewer].
/// • Videos use [VideoPlayerController] with a simple play/pause/seek bar.
class FullScreenMediaViewer extends StatefulWidget {
  final String mediaUrl;
  final List<String>? mediaUrls;
  final int initialIndex;
  final String type; // 'image' | 'video'

  const FullScreenMediaViewer({
    super.key,
    required this.mediaUrl,
    this.mediaUrls,
    this.initialIndex = 0,
    required this.type,
  });

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _controlsVisible = true;
  late final List<String> _urls;
  late int _currentIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _urls = (widget.mediaUrls != null && widget.mediaUrls!.isNotEmpty)
        ? widget.mediaUrls!
        : [widget.mediaUrl];
    _currentIndex = widget.initialIndex.clamp(0, _urls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    if (widget.type == 'video') {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.networkUrl(
        Uri.parse(signedMediaUrl(widget.mediaUrl)));
    _videoController = controller;
    await controller.initialize();
    if (mounted) {
      setState(() => _isVideoInitialized = true);
      controller.play();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _togglePlayPause() {
    final c = _videoController;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  Widget _buildImageView(String url) {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5.0,
      child: kIsWeb
          ? Image.network(
              signedMediaUrl(url),
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00A884)),
                );
              },
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            )
          : CachedNetworkImage(
              memCacheWidth: kMaxDecodeDimension,
              imageUrl: signedMediaUrl(url),
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Color(0xFF00A884)),
              ),
              errorWidget: (_, __, ___) => Image.network(
                signedMediaUrl(url),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Media content ────────────────────────────────────────────────
          GestureDetector(
            onTap: _toggleControls,
            child: Center(
              child: widget.type == 'image'
                  ? (_urls.length > 1
                      ? PageView.builder(
                          controller: _pageController,
                          itemCount: _urls.length,
                          onPageChanged: (i) =>
                              setState(() => _currentIndex = i),
                          itemBuilder: (context, i) =>
                              Center(child: _buildImageView(_urls[i])),
                        )
                      : _buildImageView(_urls.first))
                  : _buildVideoPlayer(),
            ),
          ),

          // ── Overlay controls ─────────────────────────────────────────────
          if (_controlsVisible) ...[
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      if (_urls.length > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${_currentIndex + 1} / ${_urls.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Share media link
                      IconButton(
                        icon: const Icon(Icons.share_outlined,
                            color: Colors.white),
                        tooltip: context.l10n.translate('chat_media_share'),
                        onPressed: () {
                          final currentUrl = _urls.isNotEmpty
                              ? _urls[_currentIndex]
                              : widget.mediaUrl;
                          SharePlus.instance.share(
                            ShareParams(
                              text: currentUrl,
                              subject: context.l10n
                                  .translate('chat_media_share_subject'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Video controls at bottom
            if (widget.type == 'video' && _isVideoInitialized)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildVideoControls(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (!_isVideoInitialized || _videoController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00A884)),
      );
    }
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: VideoPlayer(_videoController!),
    );
  }

  Widget _buildVideoControls() {
    final c = _videoController!;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Video progress bar
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (context, value, _) {
                final position = value.position.inMilliseconds.toDouble();
                final duration = value.duration.inMilliseconds.toDouble();
                return Column(
                  children: [
                    Slider(
                      value: position.clamp(0.0, duration > 0 ? duration : 1.0),
                      min: 0,
                      max: duration > 0 ? duration : 1.0,
                      activeColor: const Color(0xFF00A884),
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        c.seekTo(Duration(milliseconds: v.toInt()));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(value.position),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            _formatDuration(value.duration),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            // Play / Pause button
            GestureDetector(
              onTap: _togglePlayPause,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (context, value, _) {
                  return Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
