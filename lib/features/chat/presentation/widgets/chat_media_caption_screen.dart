import 'dart:io';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/logger.dart';

class MediaCaptionResult {
  final List<XFile> files;
  final String caption;
  final bool isViewOnce;

  MediaCaptionResult({
    List<XFile>? files,
    XFile? file,
    required this.caption,
    this.isViewOnce = false,
  }) : files = files != null
            ? List.unmodifiable(files)
            : (file != null ? [file] : const []);

  /// Single file backwards-compatible getter.
  XFile get file => files.isNotEmpty ? files.first : XFile('');
}

/// WhatsApp-style full screen media preview with caption composer before sending.
/// Supports single or multiple images with carousel swipe, thumbnails strip, and adding more photos.
class ChatMediaCaptionScreen extends StatefulWidget {
  final List<XFile> files;
  final bool isVideo;

  ChatMediaCaptionScreen({
    super.key,
    List<XFile>? files,
    XFile? file,
    this.isVideo = false,
  })  : files = files != null
            ? List.unmodifiable(files)
            : (file != null ? [file] : const []),
        assert(files != null || file != null,
            'Either files or file must be provided');

  @override
  State<ChatMediaCaptionScreen> createState() => _ChatMediaCaptionScreenState();
}

class _ChatMediaCaptionScreenState extends State<ChatMediaCaptionScreen> {
  final TextEditingController _captionController = TextEditingController();
  final ScrollController _thumbScrollController = ScrollController();
  late final PageController _pageController;

  late List<XFile> _files;
  int _currentIndex = 0;
  final Map<int, int> _rotations = {};
  bool _isViewOnce = false;

  @override
  void initState() {
    super.initState();
    _files = widget.files.toList();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbScrollController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _rotateCurrentImage() {
    setState(() {
      final currentTurns = _rotations[_currentIndex] ?? 0;
      _rotations[_currentIndex] = (currentTurns + 1) % 4;
    });
  }

  void _removeCurrentImage() {
    if (_files.isEmpty) return;
    if (_files.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _files.removeAt(_currentIndex);
      _rotations.remove(_currentIndex);
      if (_currentIndex >= _files.length) {
        _currentIndex = _files.length - 1;
      }
    });
    _pageController.jumpToPage(_currentIndex);
  }

  Future<void> _pickMoreImages() async {
    try {
      final picker = ImagePicker();
      final newImages = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (newImages.isNotEmpty && mounted) {
        setState(() {
          _files.addAll(newImages);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_thumbScrollController.hasClients) {
            _thumbScrollController.animateTo(
              _thumbScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      logError('Error picking more images: $e');
    }
  }

  void _scrollThumbnailTo(int index) {
    if (!_thumbScrollController.hasClients) return;
    const itemWidth = 60.0;
    final targetOffset = (index * itemWidth) - 100.0;
    _thumbScrollController.animateTo(
      targetOffset.clamp(
        0.0,
        _thumbScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _submit() {
    if (_files.isEmpty) return;
    Navigator.of(context).pop(
      MediaCaptionResult(
        files: _files,
        caption: _captionController.text.trim(),
        isViewOnce: _isViewOnce,
      ),
    );
  }

  Widget _buildThumbnail(XFile xf, int index) {
    final isSelected = index == _currentIndex;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      },
      child: Container(
        width: 52,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF00A884) : Colors.white24,
            width: isSelected ? 2.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            kIsWeb
                ? Image.network(
                    xf.path,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image,
                      color: Colors.white38,
                      size: 20,
                    ),
                  )
                : Image.file(
                    File(xf.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.image,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ),
            if (isSelected)
              Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddMoreThumbnail() {
    return GestureDetector(
      onTap: _pickMoreImages,
      child: Container(
        width: 52,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white38, width: 1.0),
        ),
        child: const Center(
          child: Icon(Icons.add, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Center Image/Media Carousel with InteractiveViewer
            PageView.builder(
              controller: _pageController,
              itemCount: _files.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _scrollThumbnailTo(index);
              },
              itemBuilder: (context, index) {
                final file = _files[index];
                final turns = _rotations[index] ?? 0;
                return Center(
                  child: RotatedBox(
                    quarterTurns: turns,
                    child: InteractiveViewer(
                      maxScale: 4.0,
                      child: kIsWeb
                          ? Image.network(
                              file.path,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_rounded,
                                    size: 64, color: Colors.white54),
                              ),
                            )
                          : Image.file(
                              File(file.path),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_rounded,
                                    size: 64, color: Colors.white54),
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),

            // Top action buttons
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (_files.length > 1) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${_files.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!widget.isVideo) ...[
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white, size: 26),
                      tooltip: context.l10n.translate('chat_add_more_photos'),
                      onPressed: _pickMoreImages,
                    ),
                    if (_files.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white, size: 26),
                        tooltip: context.l10n.translate('chat_remove_photo'),
                        onPressed: _removeCurrentImage,
                      ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.rotate_right,
                        color: Colors.white, size: 26),
                    tooltip: context.l10n.translate('chat_media_rotate'),
                    onPressed: _rotateCurrentImage,
                  ),
                ],
              ),
            ),

            // Bottom Caption Composer Bar (WhatsApp styled)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thumbnails bar when multiple images are selected
                  if (!widget.isVideo && _files.length > 1)
                    Container(
                      height: 56,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListView.builder(
                        controller: _thumbScrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: _files.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _files.length) {
                            return _buildAddMoreThumbnail();
                          }
                          return _buildThumbnail(_files[index], index);
                        },
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2C34),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _captionController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: context.l10n
                                  .translate('chat_media_caption_hint'),
                              hintStyle: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            maxLines: 3,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // WhatsApp View Once (1) toggle button
                      GestureDetector(
                        onTap: () {
                          setState(() => _isViewOnce = !_isViewOnce);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isViewOnce
                                    ? context.l10n
                                        .translate('chat_view_once_on')
                                    : context.l10n
                                        .translate('chat_view_once_off'),
                                style: const TextStyle(fontSize: 13),
                              ),
                              duration: const Duration(seconds: 2),
                              backgroundColor: const Color(0xFF1F2C34),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isViewOnce
                                ? const Color(0xFF00A884)
                                    .withValues(alpha: 0.25)
                                : const Color(0xFF1F2C34),
                            border: Border.all(
                              color: _isViewOnce
                                  ? const Color(0xFF00A884)
                                  : Colors.white54,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '1',
                              style: TextStyle(
                                color: _isViewOnce
                                    ? const Color(0xFF00A884)
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _submit,
                        child: const CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(0xFF00A884),
                          child:
                              Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
