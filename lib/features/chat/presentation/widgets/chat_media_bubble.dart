import 'package:bhromon/core/theme/colors.dart';
import 'dart:io';
import 'package:bhromon/features/chat/presentation/chat_palette.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../pages/full_screen_media_viewer.dart';
import '../../../../core/utils/image_sizing.dart';

/// Renders an image or video message bubble inside the chat.
///
/// Handles states:
///  1. **Uploading** – shows a local file/memory preview with a progress overlay.
///  2. **Single Image** – shows the remote image via [CachedNetworkImage] or [Image.network].
///  3. **Multi Image** – shows a WhatsApp-style collage / grid (2-side-by-side, 3 1-large/2-stacked, 4+ 2x2 with +N).
///  4. **Video** – shows a thumbnail with a play‑button overlay.
class ChatMediaBubble extends StatelessWidget {
  /// Remote download URL (null while still uploading).
  final String? mediaUrl;

  /// Remote download URLs when multiple photos are bundled in a single message.
  final List<String>? mediaUrls;

  /// CDN-generated WebP thumbnail URL (used instead of full mediaUrl in the list).
  final String? thumbnailUrl;

  /// Local file reference used during optimistic upload.
  final File? localFile;

  /// Multiple local file references used during optimistic multi-image upload.
  final List<File>? localFiles;

  /// In-memory bytes used during optimistic upload (especially on Web).
  final Uint8List? bytes;

  /// Multiple in-memory bytes used during optimistic multi-image upload.
  final List<Uint8List>? multiBytes;

  /// 'image' or 'video'.
  final String type;

  /// Upload progress 0.0 → 1.0. Null means already uploaded.
  final double? uploadProgress;

  /// Whether the bubble is the sender's (green) or receiver's (grey).
  final bool isMe;

  const ChatMediaBubble({
    super.key,
    this.mediaUrl,
    this.mediaUrls,
    this.thumbnailUrl,
    this.localFile,
    this.localFiles,
    this.bytes,
    this.multiBytes,
    required this.type,
    this.uploadProgress,
    required this.isMe,
  });

  bool get _isMultiImage {
    if (type != 'image') return false;
    final isUploading = uploadProgress != null && uploadProgress! < 1.0;
    if (isUploading) {
      final fCount = localFiles?.length ?? 0;
      final bCount = multiBytes?.length ?? 0;
      return fCount > 1 || bCount > 1;
    }
    return mediaUrls != null && mediaUrls!.length > 1;
  }

  int get _imageCount {
    final isUploading = uploadProgress != null && uploadProgress! < 1.0;
    if (isUploading) {
      final fCount = localFiles?.length ?? 0;
      final bCount = multiBytes?.length ?? 0;
      return fCount > 1 ? fCount : (bCount > 1 ? bCount : 1);
    }
    return mediaUrls?.length ?? 1;
  }

  void _openViewer(BuildContext context, int initialIndex) {
    final urls = (mediaUrls != null && mediaUrls!.isNotEmpty)
        ? mediaUrls!
        : [if (mediaUrl != null && mediaUrl!.isNotEmpty) mediaUrl!];
    if (urls.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FullScreenMediaViewer(
            mediaUrl: urls[initialIndex.clamp(0, urls.length - 1)],
            mediaUrls: urls,
            initialIndex: initialIndex,
            type: type,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isUploading = uploadProgress != null && uploadProgress! < 1.0;
    final Color bubbleColor = isMe ? context.chat.outgoing : context.chat.panel;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxBubbleWidth =
        kIsWeb ? 340.0 : (screenWidth * 0.72).clamp(200.0, 320.0);
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
        onTap: isUploading || _isMultiImage
            ? null
            : () {
                if (mediaUrl != null && mediaUrl!.isNotEmpty) {
                  _openViewer(context, 0);
                }
              },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Media content ──────────────────────────────────────────────
            if (_isMultiImage)
              _buildMultiImageContent(
                context,
                isUploading,
                context.decodeWidth(maxBubbleWidth),
                maxBubbleWidth,
              )
            else
              _buildMediaContent(
                context,
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

  Widget _buildMultiImageContent(
    BuildContext context,
    bool isUploading,
    int decodeWidth,
    double maxBubbleWidth,
  ) {
    final count = _imageCount;
    const double totalHeight = 240.0;
    const double gap = 2.0;

    if (count == 2) {
      final tileW = (maxBubbleWidth - gap) / 2;
      return SizedBox(
        width: maxBubbleWidth,
        height: 220,
        child: Row(
          children: [
            SizedBox(
              width: tileW,
              height: 220,
              child: _buildTile(context, 0, isUploading, decodeWidth),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: tileW,
              height: 220,
              child: _buildTile(context, 1, isUploading, decodeWidth),
            ),
          ],
        ),
      );
    }

    if (count == 3) {
      final leftW = (maxBubbleWidth - gap) * 0.58;
      final rightW = (maxBubbleWidth - gap) * 0.42;
      const halfH = (totalHeight - gap) / 2;
      return SizedBox(
        width: maxBubbleWidth,
        height: totalHeight,
        child: Row(
          children: [
            SizedBox(
              width: leftW,
              height: totalHeight,
              child: _buildTile(context, 0, isUploading, decodeWidth),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: rightW,
              height: totalHeight,
              child: Column(
                children: [
                  SizedBox(
                    width: rightW,
                    height: halfH,
                    child: _buildTile(context, 1, isUploading, decodeWidth),
                  ),
                  const SizedBox(height: gap),
                  SizedBox(
                    width: rightW,
                    height: halfH,
                    child: _buildTile(context, 2, isUploading, decodeWidth),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4 or 5+ photos: 2x2 grid
    final tileW = (maxBubbleWidth - gap) / 2;
    const tileH = (totalHeight - gap) / 2;
    final remainingCount = count - 4;

    return SizedBox(
      width: maxBubbleWidth,
      height: totalHeight,
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: tileW,
                height: tileH,
                child: _buildTile(context, 0, isUploading, decodeWidth),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: tileW,
                height: tileH,
                child: _buildTile(context, 1, isUploading, decodeWidth),
              ),
            ],
          ),
          const SizedBox(height: gap),
          Row(
            children: [
              SizedBox(
                width: tileW,
                height: tileH,
                child: _buildTile(context, 2, isUploading, decodeWidth),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: tileW,
                height: tileH,
                child: remainingCount > 0
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildTile(context, 3, isUploading, decodeWidth),
                          IgnorePointer(
                            child: Container(
                              color: Colors.black54,
                              alignment: Alignment.center,
                              child: Text(
                                '+${remainingCount + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _buildTile(context, 3, isUploading, decodeWidth),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    int index,
    bool isUploading,
    int decodeWidth,
  ) {
    return GestureDetector(
      onTap: isUploading ? null : () => _openViewer(context, index),
      child: Container(
        decoration: BoxDecoration(
          color: context.chat.recessed,
        ),
        clipBehavior: Clip.hardEdge,
        child: _buildTileImage(context, index, isUploading, decodeWidth),
      ),
    );
  }

  Widget _buildTileImage(
    BuildContext context,
    int index,
    bool isUploading,
    int decodeWidth,
  ) {
    if (isUploading) {
      if (!kIsWeb && localFiles != null && index < localFiles!.length) {
        return Image.file(
          localFiles![index],
          cacheWidth: decodeWidth,
          fit: BoxFit.cover,
        );
      }
      if (multiBytes != null && index < multiBytes!.length) {
        return Image.memory(
          multiBytes![index],
          fit: BoxFit.cover,
        );
      }
      if (bytes != null) {
        return Image.memory(bytes!, fit: BoxFit.cover);
      }
      return Container(color: context.chat.recessed);
    }

    final url = (mediaUrls != null && index < mediaUrls!.length)
        ? mediaUrls![index]
        : (mediaUrl ?? '');

    if (url.isEmpty) {
      return Container(color: context.chat.recessed);
    }

    if (kIsWeb) {
      return Image.network(
        signedMediaUrl(url),
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: context.chat.recessed,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.chatGreen,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: context.chat.recessed,
          child: const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 24),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      memCacheWidth: decodeWidth,
      imageUrl: signedMediaUrl(url),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: context.chat.recessed,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.chatGreen,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: context.chat.recessed,
        child: const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 24),
        ),
      ),
    );
  }

  Widget _buildMediaContent(
    BuildContext context,
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
          color: context.chat.recessed,
          child: Center(
            child: Icon(Icons.movie_outlined,
                color: context.chat.text54, size: 48),
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
        color: context.chat.recessed,
        child: Center(
          child:
              Icon(Icons.image_outlined, color: context.chat.text38, size: 40),
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
          color: context.chat.recessed,
          child: Center(
            child: Icon(Icons.movie_outlined,
                color: context.chat.text54, size: 48),
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
              color: context.chat.recessed,
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: AppColors.chatGreen,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );

        Widget buildBrokenPlaceholder() => Container(
              width: maxBubbleWidth,
              height: 180,
              color: context.chat.recessed,
              child: Center(
                child: Icon(Icons.broken_image_outlined,
                    color: context.chat.text54, size: 36),
              ),
            );

        if (kIsWeb) {
          // On Web: use Image.network to avoid XHR CORS and flutter_cache_manager issues
          return Image.network(
            signedMediaUrl(displayUrl),
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
          imageUrl: signedMediaUrl(displayUrl),
          fit: BoxFit.contain,
          placeholder: (_, __) => buildPlaceholder(),
          errorWidget: (_, __, ___) => Image.network(
            signedMediaUrl(displayUrl),
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
      color: context.chat.recessed,
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
                color: AppColors.chatGreen,
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
