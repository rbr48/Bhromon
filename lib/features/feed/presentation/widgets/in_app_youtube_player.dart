import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/utils/image_sizing.dart';

// ─────────────────────────────────────────────────────────────
// Utility: Extract YouTube video ID from any common URL format
// ─────────────────────────────────────────────────────────────
String? extractYouTubeId(String url) {
  if (url.isEmpty) return null;

  // youtu.be/<id>
  if (url.contains('youtu.be/')) {
    final part = url.split('youtu.be/').last;
    return part.split(RegExp(r'[?&#]')).first.trim();
  }
  // youtube.com/watch?v=<id>
  if (url.contains('youtube.com/watch')) {
    try {
      final uri = Uri.parse(url);
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
  }
  // youtube.com/shorts/<id>
  if (url.contains('/shorts/')) {
    final part = url.split('/shorts/').last;
    return part.split(RegExp(r'[?&#]')).first.trim();
  }
  // youtube.com/embed/<id>
  if (url.contains('/embed/')) {
    final part = url.split('/embed/').last;
    return part.split(RegExp(r'[?&#]')).first.trim();
  }
  // youtube.com/v/<id>
  if (url.contains('/v/')) {
    final part = url.split('/v/').last;
    return part.split(RegExp(r'[?&#]')).first.trim();
  }

  // Regex fallback – matches 11-char video ID
  final regExp = RegExp(
    r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
    caseSensitive: false,
  );
  final match = regExp.firstMatch(url);
  if (match != null && match.groupCount >= 1) {
    return match.group(1);
  }

  return null;
}

// ─────────────────────────────────────────────────────────────
// InAppYoutubePlayer
//
// Shows a thumbnail + play-button overlay initially.
// On tap (or in detail-mode), replaces itself with an
// InAppWebView that loads the YouTube iframe embed directly.
// ─────────────────────────────────────────────────────────────
class InAppYoutubePlayer extends StatefulWidget {
  final String videoUrl;
  final String caption;

  /// previewMode = true  → show thumbnail in feed, tap to play
  /// previewMode = false → start WebView player immediately (detail modal)
  final bool previewMode;

  const InAppYoutubePlayer({
    super.key,
    required this.videoUrl,
    required this.caption,
    this.previewMode = true,
  });

  @override
  State<InAppYoutubePlayer> createState() => _InAppYoutubePlayerState();
}

class _InAppYoutubePlayerState extends State<InAppYoutubePlayer> {
  bool _isPlaying = false;
  String? _videoId;

  @override
  void initState() {
    super.initState();
    _videoId = extractYouTubeId(widget.videoUrl);
    // In detail mode, start playback after sheet transition completes to prevent lag
    if (!widget.previewMode && widget.videoUrl.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 650), () {
        if (mounted) {
          setState(() => _isPlaying = true);
        }
      });
    }
  }

  void _startPlayback() {
    if (widget.videoUrl.isEmpty) return;
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoUrl.isEmpty) {
      return _buildInvalidUrlFallback();
    }

    final String thumbnailUrl = _videoId != null && _videoId!.isNotEmpty
        ? 'https://img.youtube.com/vi/$_videoId/hqdefault.jpg'
        : '';

    if (!_isPlaying) {
      return _buildThumbnailPreview(thumbnailUrl);
    }

    return _YoutubeWebPlayer(
      videoUrl: widget.videoUrl,
      videoId: _videoId,
      caption: widget.caption,
      autoPlay: true,
    );
  }

  // ── Thumbnail Preview ──────────────────────────────────────
  Widget _buildThumbnailPreview(String thumbnailUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _startPlayback,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Thumbnail image
                thumbnailUrl.isNotEmpty
                    ? CachedNetworkImage(
                        memCacheWidth: context.decodeWidth(),
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
                        height: 210,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          height: 210,
                          color: Colors.black26,
                          child: const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) =>
                            _buildFallbackThumbnail(),
                      )
                    : _buildFallbackThumbnail(),

                // YouTube/Video badge
                Positioned(
                  bottom: 8,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _videoId != null && _videoId!.isNotEmpty
                                ? Icons.play_circle_filled
                                : Icons.video_library_rounded,
                            color: _videoId != null && _videoId!.isNotEmpty
                                ? Colors.red
                                : Colors.lightBlueAccent,
                            size: 13),
                        const SizedBox(width: 4),
                        Text(
                          _videoId != null && _videoId!.isNotEmpty
                              ? 'YouTube'
                              : 'Video',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Big play button
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 38),
                ),
              ],
            ),
          ),
        ),
        if (widget.caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.caption,
            style: const TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      height: 210,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_outline,
              color: Colors.white38, size: 52),
          const SizedBox(height: 8),
          Text(
            widget.caption.isNotEmpty ? widget.caption : 'YouTube Video',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildInvalidUrlFallback() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, color: Colors.black26, size: 32),
            SizedBox(height: 6),
            Text('Video unavailable',
                style: TextStyle(color: Colors.black38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _YoutubeWebPlayer
//
// Uses flutter_inappwebview to render YouTube's official iframe
// embed. This is the most reliable approach on Android — it
// avoids all the WebView bridge / autoplay restrictions that
// plague youtube_player_flutter on API 35.
// ─────────────────────────────────────────────────────────────
class _YoutubeWebPlayer extends StatefulWidget {
  final String videoUrl;
  final String? videoId;
  final String caption;
  final bool autoPlay;

  const _YoutubeWebPlayer({
    required this.videoUrl,
    this.videoId,
    required this.caption,
    this.autoPlay = true,
  });

  @override
  State<_YoutubeWebPlayer> createState() => _YoutubeWebPlayerState();
}

class _YoutubeWebPlayerState extends State<_YoutubeWebPlayer> {
  bool _isLoading = true;

  String get _embedHtml {
    final autoplay = widget.autoPlay ? 1 : 0;
    if (widget.videoId != null && widget.videoId!.isNotEmpty) {
      return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
    .player-container {
      position: relative;
      width: 100%;
      height: 0;
      padding-bottom: 56.25%;
      background: #000;
    }
    iframe {
      position: absolute;
      top: 0; left: 0;
      width: 100%; height: 100%;
      border: none;
    }
  </style>
</head>
<body>
  <div class="player-container">
    <iframe
      src="https://www.youtube.com/embed/${widget.videoId}?autoplay=$autoplay&playsinline=1&rel=0&modestbranding=1&enablejsapi=1"
      allow="autoplay; encrypted-media; fullscreen"
      referrerpolicy="strict-origin-when-cross-origin"
      allowfullscreen>
    </iframe>
  </div>
</body>
</html>
''';
    } else {
      final autoplayAttr = widget.autoPlay ? 'autoplay' : '';
      return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: #000;
    }
  </style>
</head>
<body>
  <video src="${widget.videoUrl}" controls playsinline $autoplayAttr></video>
</body>
</html>
''';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: _embedHtml,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                    baseUrl: WebUri('https://app.bhromon.fun'),
                  ),
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<TapGestureRecognizer>(
                      () => TapGestureRecognizer(),
                    ),
                    Factory<HorizontalDragGestureRecognizer>(
                      () => HorizontalDragGestureRecognizer(),
                    ),
                  },
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    supportZoom: false,
                    userAgent:
                        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
                    allowsInlineMediaPlayback: true,
                    useHybridComposition: false,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    builtInZoomControls: false,
                    displayZoomControls: false,
                    domStorageEnabled: true,
                  ),
                  onLoadStop: (controller, url) {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  },
                ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.red,
                            strokeWidth: 2.5,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Loading video...',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.caption,
            style: const TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
