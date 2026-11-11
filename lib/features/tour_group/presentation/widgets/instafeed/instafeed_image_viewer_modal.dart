import 'dart:ui';
import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'package:bhromon/features/tour_group/domain/services/like_state.dart';
import 'instafeed_carousel.dart';
import 'instafeed_zoomable_media.dart';
import 'tour_safe_network_image.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Full-screen high-resolution image viewer modal supporting multi-photo
/// swipeable carousels, pinch-to-zoom (up to 4.5x), double-tap heart like,
/// caption viewer, and 1-tap Trip Ledger integration.
class InstafeedImageViewerModal extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourPostItem post;
  final int initialIndex;
  final void Function(TourPostItem post, {int? targetMediaIndex})?
      onOpenComments;
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
    void Function(TourPostItem post, {int? targetMediaIndex})? onOpenComments,
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

  /// The like the user last asked for, shown until the server holds it.
  bool? _optimisticLiked;

  @override
  void didUpdateWidget(InstafeedImageViewerModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) _optimisticLiked = null;
    if (LikeState.serverCaughtUp(
      optimistic: _optimisticLiked,
      onServer: widget.post.isLikedBy(widget.repository.currentEmail),
    )) {
      _optimisticLiked = null;
    }
  }

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
    final email = widget.repository.currentEmail;
    if (email.isNotEmpty && !widget.post.isViewedBy(email)) {
      widget.repository.recordPostView(
        tourId: widget.tourId,
        postId: widget.post.id,
      );
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final email = widget.repository.currentEmail;
    final currentLiked = _optimisticLiked ?? widget.post.isLikedBy(email);
    final targetLiked = !currentLiked;

    setState(() {
      _optimisticLiked = targetLiked;
    });

    try {
      await widget.repository.setPostLiked(
        widget.tourId,
        widget.post.id,
        liked: targetLiked,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticLiked = currentLiked;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_like_change_failed', args: {'error': e}))),
        );
      }
    }
  }

  void _onDoubleTap() {
    setState(() => _showHeartBurst = true);
    final email = widget.repository.currentEmail;
    final currentLiked = _optimisticLiked ?? widget.post.isLikedBy(email);
    if (!currentLiked) {
      _toggleLike();
    }
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
    if (_currentIndex < _images.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final email = widget.repository.currentEmail;
    final serverLiked = widget.post.isLikedBy(email);
    final isLiked =
        LikeState.shown(optimistic: _optimisticLiked, onServer: serverLiked);
    final likeCount = LikeState.shownCount(
      onServerCount: widget.post.likes.length,
      shownLiked: isLiked,
      onServerLiked: serverLiked,
    );
    final dateStr = localizedDateFormat('d MMMM, yyyy • h:mm a')
        .format(widget.post.createdAt);

    if (images.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Text(
            context.l10n.translate('ig_no_photos_found'),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final modalBody = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Swipeable Fullscreen Images with Pinch-to-Zoom and Mouse Drag
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
                      child: TourSafeNetworkImage(
                        imageUrl: imgUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Double-tap Heart Burst Animation
          Positioned.fill(
            child: InstafeedHeartBurst(
              show: _showHeartBurst,
              onComplete: () => setState(() => _showHeartBurst = false),
            ),
          ),

          // Left Chevron Navigation Button (Fullscreen)
          if (images.length > 1 && _currentIndex > 0)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: _showOverlays ? 20 : -80,
              top: 0,
              bottom: 0,
              child: Center(
                child: CarouselNavButton(
                  key: const ValueKey('modal_prev_button'),
                  size: 46,
                  iconSize: 28,
                  icon: Icons.chevron_left_rounded,
                  tooltip: context.l10n.translate('ig_prev_photo'),
                  onPressed: _goToPrevious,
                ),
              ),
            ),

          // Right Chevron Navigation Button (Fullscreen)
          if (images.length > 1 && _currentIndex < images.length - 1)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              right: _showOverlays ? 20 : -80,
              top: 0,
              bottom: 0,
              child: Center(
                child: CarouselNavButton(
                  key: const ValueKey('modal_next_button'),
                  size: 46,
                  iconSize: 28,
                  icon: Icons.chevron_right_rounded,
                  tooltip: context.l10n.translate('ig_next_photo'),
                  onPressed: _goToNext,
                ),
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
                    tooltip: context.l10n.translate('ig_back'),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.mintGreen,
                    backgroundImage: widget.post.authorPhoto != null
                        ? NetworkImage(signedMediaUrl(widget.post.authorPhoto!))
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
                              fontSize: 12,
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
                    tooltip: context.l10n.translate('ig_close'),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),

                  // Actions: Like, Comment, Share, Ledger
                  Row(
                    children: [
                      IconButton(
                        tooltip: isLiked
                            ? context.l10n.translate('ig_unlike')
                            : context.l10n.translate('ig_like'),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? Colors.redAccent : Colors.white,
                        ),
                        onPressed: _toggleLike,
                      ),
                      Text(
                        '$likeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: context.l10n.translate('ig_comment'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chat_bubble_outline,
                            color: Colors.white),
                        onPressed: () => widget.onOpenComments?.call(
                            widget.post,
                            targetMediaIndex: _currentIndex),
                      ),
                      IconButton(
                        tooltip: context.l10n.translate('ig_share'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.send_outlined,
                            color: Colors.white),
                        onPressed: () => widget.onShare?.call(widget.post),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.receipt_long,
                            color: AppColors.mintGreen),
                        tooltip: context.l10n.translate('ig_add_to_ledger'),
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

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _goToPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _goToNext,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.maybePop(context);
        },
      },
      child: Focus(
        autofocus: true,
        child: modalBody,
      ),
    );
  }
}
