import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'instafeed_zoomable_media.dart';

/// Full-screen high-resolution image viewer modal supporting multi-photo
/// swipeable carousels, pinch-to-zoom (up to 4.5x), double-tap heart like,
/// caption viewer, and 1-tap Trip Ledger integration.
class InstafeedImageViewerModal extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourPostItem post;
  final int initialIndex;
  final void Function(TourPostItem post)? onOpenComments;
  final void Function(TourPostItem post)? onShare;
  final void Function(TourPostItem post)? onAddToLedger;

  const InstafeedImageViewerModal({
    super.key,
    required this.repository,
    required this.tourId,
    required this.post,
    this.initialIndex = 0,
    this.onOpenComments,
    this.onShare,
    this.onAddToLedger,
  });

  /// Helper to open the full-size image viewer from anywhere
  static Future<void> show(
    BuildContext context, {
    required TourGroupRepository repository,
    required String tourId,
    required TourPostItem post,
    int initialIndex = 0,
    void Function(TourPostItem post)? onOpenComments,
    void Function(TourPostItem post)? onShare,
    void Function(TourPostItem post)? onAddToLedger,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => InstafeedImageViewerModal(
          repository: repository,
          tourId: tourId,
          post: post,
          initialIndex: initialIndex,
          onOpenComments: onOpenComments,
          onShare: onShare,
          onAddToLedger: onAddToLedger,
        ),
      ),
    );
  }

  @override
  State<InstafeedImageViewerModal> createState() =>
      _InstafeedImageViewerModalState();
}

class _InstafeedImageViewerModalState extends State<InstafeedImageViewerModal> {
  late final PageController _pageCtrl;
  late int _currentIndex;
  bool _showOverlays = true;
  bool _showHeartBurst = false;

  List<String> get _images {
    if (widget.post.images.isNotEmpty) {
      return widget.post.images;
    }
    if (widget.post.coverUrl != null &&
        isRemoteMediaUrl(widget.post.coverUrl!)) {
      return [widget.post.coverUrl!];
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    final maxIdx = _images.isNotEmpty ? _images.length - 1 : 0;
    _currentIndex = widget.initialIndex.clamp(0, maxIdx);
    _pageCtrl = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final email = widget.repository.currentEmail;
    final isLiked = widget.post.isLikedBy(email);
    try {
      await widget.repository.setPostLiked(
        widget.tourId,
        widget.post.id,
        liked: !isLiked,
      );
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('লাইক পরিবর্তন ব্যর্থ: $e')),
        );
      }
    }
  }

  void _onDoubleTap() {
    setState(() => _showHeartBurst = true);
    if (!widget.post.isLikedBy(widget.repository.currentEmail)) {
      _toggleLike();
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final email = widget.repository.currentEmail;
    final isLiked = widget.post.isLikedBy(email);
    final dateStr =
        DateFormat('d MMMM, yyyy • h:mm a').format(widget.post.createdAt);

    if (images.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'কোনো ছবি পাওয়া যায়নি।',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Swipeable Fullscreen Images with Pinch-to-Zoom
          PageView.builder(
            controller: _pageCtrl,
            itemCount: images.length,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemBuilder: (context, index) {
              final imgUrl = images[index];
              return GestureDetector(
                onTap: () => setState(() => _showOverlays = !_showOverlays),
                onDoubleTap: _onDoubleTap,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.5,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: imgUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white38),
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white24, size: 48),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 2. Double-tap Heart Burst Animation
          Positioned.fill(
            child: InstafeedHeartBurst(
              show: _showHeartBurst,
              onComplete: () => setState(() => _showHeartBurst = false),
            ),
          ),

          // 3. Top Header Bar (Animated Overlay)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showOverlays ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 12,
                left: 12,
                right: 12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF00C853),
                    backgroundImage: widget.post.authorPhoto != null
                        ? NetworkImage(widget.post.authorPhoto!)
                        : null,
                    child: widget.post.authorPhoto == null
                        ? Text(
                            widget.post.authorName.isNotEmpty
                                ? widget.post.authorName[0].toUpperCase()
                                : 'M',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.post.authorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.post.location.isNotEmpty)
                          Text(
                            widget.post.location,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (images.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Information & Action Bar (Animated Overlay)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showOverlays ? 0 : -180,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Caption
                  if (widget.post.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        widget.post.caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Date
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 10),

                  // Actions: Like, Comment, Share, Ledger
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? Colors.redAccent : Colors.white,
                        ),
                        onPressed: _toggleLike,
                      ),
                      Text(
                        '${widget.post.likes.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chat_bubble_outline,
                            color: Colors.white),
                        onPressed: () =>
                            widget.onOpenComments?.call(widget.post),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.send_outlined,
                            color: Colors.white),
                        onPressed: () => widget.onShare?.call(widget.post),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.receipt_long,
                            color: Color(0xFF00C853)),
                        tooltip: 'ট্রিপ লেজারে যোগ করুন',
                        onPressed: () =>
                            widget.onAddToLedger?.call(widget.post),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
