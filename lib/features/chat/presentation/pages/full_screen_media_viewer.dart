import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/utils/image_sizing.dart';

/// Full-screen viewer for chat images and videos.
///
/// • Images support pinch-to-zoom via [InteractiveViewer].
/// • Videos use [VideoPlayerController] with a simple play/pause/seek bar.
class FullScreenMediaViewer extends StatefulWidget {
  final String mediaUrl;
  final String type; // 'image' | 'video'

  const FullScreenMediaViewer({
    super.key,
    required this.mediaUrl,
    required this.type,
  });

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl));
    _videoController = controller;
    await controller.initialize();
    if (mounted) {
      setState(() => _isVideoInitialized = true);
      controller.play();
    }
  }

  @override
  void dispose() {
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
                  ? InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5.0,
                      child: CachedNetworkImage(
                        memCacheWidth: kMaxDecodeDimension,
                        imageUrl: widget.mediaUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF00A884)),
                        ),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
                    )
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
                      const Spacer(),
                      // Share placeholder
                      IconButton(
                        icon: const Icon(Icons.share_outlined,
                            color: Colors.white),
                        onPressed: () {},
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
                                color: Colors.white70, fontSize: 11),
                          ),
                          Text(
                            _formatDuration(value.duration),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
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
