import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../pages/full_screen_media_viewer.dart';
import '../../../../core/utils/image_sizing.dart';

/// Renders an image or video message bubble inside the chat.
///
/// Handles three states:
///  1. **Uploading** – shows a local file/memory preview with a progress overlay.
///  2. **Image** – shows the remote image via [CachedNetworkImage] or [Image.network].
///  3. **Video** – shows a thumbnail with a play‑button overlay.
class ChatMediaBubble extends StatelessWidget {
  /// Remote download URL (null while still uploading).
  final String? mediaUrl;

  /// CDN-generated WebP thumbnail URL (used instead of full mediaUrl in the list).
  final String? thumbnailUrl;

  /// Local file reference used during optimistic upload.
  final File? localFile;

  /// In-memory bytes used during optimistic upload (especially on Web).
  final Uint8List? bytes;

  /// 'image' or 'video'.
  final String type;

  /// Upload progress 0.0 → 1.0. Null means already uploaded.
  final double? uploadProgress;

  /// Whether the bubble is the sender's (green) or receiver's (grey).
  final bool isMe;

  const ChatMediaBubble({
    super.key,
    this.mediaUrl,
    this.thumbnailUrl,
    this.localFile,
    this.bytes,
    required this.type,
    this.uploadProgress,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUploading = uploadProgress != null && uploadProgress! < 1.0;
    final Color bubbleColor =
        isMe ? const Color(0xFF005C4B) : const Color(0xFF202C33);

    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxBubbleWidth = kIsWeb
        ? 340.0
        : (screenWidth * 0.72).clamp(200.0, 320.0);
    const double maxBubbleHeight = 360.0;

    return Container(
      constraints: BoxConstraints(
        maxWidth: maxBubbleWidth,
        maxHeight: maxBubbleHeight,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
          bottomRight: isMe ? Radius.zero : const Radius.circular(12),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: GestureDetector(
        onTap: isUploading
            ? null
            : () {
                if (mediaUrl != null && mediaUrl!.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FullScreenMediaViewer(
                        mediaUrl: mediaUrl!,
                        type: type,
                      ),
                    ),
                  );
                }
              },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Media content ──────────────────────────────────────────────
            _buildMediaContent(
              isUploading,
              context.decodeWidth(maxBubbleWidth),
              maxBubbleWidth,
              maxBubbleHeight,
            ),

            // ── Upload progress overlay ────────────────────────────────────
            if (isUploading)
              Positioned.fill(
                child: _buildProgressOverlay(),
              ),

            // ── Video play button overlay (uploaded) ───────────────────────
            if (!isUploading && type == 'video')
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 2),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent(
    bool isUploading,
    int decodeWidth,
    double maxBubbleWidth,
    double maxBubbleHeight,
  ) {
    // 1. While uploading, show local file or memory bytes preview
    if (isUploading) {
      if (type == 'video') {
        return Container(
          width: maxBubbleWidth,
          height: 200,
          color: const Color(0xFF1A2730),
          child: const Center(
            child: Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
          ),
        );
      }

      if (kIsWeb && bytes != null && bytes!.isNotEmpty) {
        return Image.memory(
          bytes!,
          fit: BoxFit.contain,
        );
      }

      if (!kIsWeb && localFile != null) {
        return Image.file(
          localFile!,
          cacheWidth: decodeWidth,
          fit: BoxFit.contain,
        );
      }

      if (bytes != null && bytes!.isNotEmpty) {
        return Image.memory(
          bytes!,
          fit: BoxFit.contain,
        );
      }

      // Fallback while pending upload starts
      return Container(
        width: maxBubbleWidth,
        height: 200,
        color: const Color(0xFF1A2730),
        child: const Center(
          child: Icon(Icons.image_outlined, color: Colors.white38, size: 40),
        ),
      );
    }

    // 2. Uploaded media
    if (mediaUrl != null && mediaUrl!.isNotEmpty) {
      if (type == 'video') {
        // For video: show thumbnail from Firestore thumbnailUrl or a dark placeholder
        return Container(
          width: maxBubbleWidth,
          height: 200,
          color: const Color(0xFF1A2730),
          child: const Center(
            child: Icon(Icons.movie_outlined, color: Colors.white54, size: 48),
          ),
        );
      } else {
        // Prefer CDN WebP thumbnail for in-list display; fall back to full URL
        final displayUrl = (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
            ? thumbnailUrl!
            : mediaUrl!;

        Widget buildPlaceholder() => Container(
          width: maxBubbleWidth,
          height: 200,
          color: const Color(0xFF1A2730),
          child: const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Color(0xFF00A884),
                strokeWidth: 2,
              ),
            ),
          ),
        );

        Widget buildBrokenPlaceholder() => Container(
          width: maxBubbleWidth,
          height: 180,
          color: const Color(0xFF1A2730),
          child: const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 36),
          ),
        );

        if (kIsWeb) {
          // On Web: use Image.network to avoid XHR CORS and flutter_cache_manager issues
          return Image.network(
            displayUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return buildPlaceholder();
            },
            errorBuilder: (context, error, stackTrace) =>
                buildBrokenPlaceholder(),
          );
        }

        return CachedNetworkImage(
          memCacheWidth: decodeWidth,
          imageUrl: displayUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => buildPlaceholder(),
          errorWidget: (_, __, ___) => Image.network(
            displayUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return buildPlaceholder();
            },
            errorBuilder: (_, __, ___) => buildBrokenPlaceholder(),
          ),
        );
      }
    }

    // Fallback placeholder
    return Container(
      width: maxBubbleWidth,
      height: 180,
      color: const Color(0xFF1A2730),
    );
  }

  Widget _buildProgressOverlay() {
    final percent = ((uploadProgress ?? 0) * 100).toInt();
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: (uploadProgress != null && uploadProgress! > 0)
                    ? uploadProgress
                    : null,
                color: const Color(0xFF00A884),
                backgroundColor: Colors.white24,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
