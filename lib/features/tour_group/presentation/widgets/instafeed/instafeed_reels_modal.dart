import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'instafeed_zoomable_media.dart';
import 'reel_picture.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/utils/logger.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Full-screen vertical Reels player modal with video pre-caching, hold-to-pause
/// clean screen mode, interactive draggable timeline scrubber, rotating vinyl
/// sound attribution, and 1-tap Trip Ledger integration.
class InstafeedReelsModal extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final List<TourPostItem> reels;
  final int initialIndex;
  final void Function(TourPostItem post)? onOpenComments;
  final void Function(TourPostItem post)? onShare;
  final void Function(TourPostItem post)? onAddToLedger;

  const InstafeedReelsModal({
    super.key,
    required this.repository,
    required this.tourId,
    required this.reels,
    this.initialIndex = 0,
    this.onOpenComments,
    this.onShare,
    this.onAddToLedger,
  });

  @override
  State<InstafeedReelsModal> createState() => _InstafeedReelsModalState();
}

class _InstafeedReelsModalState extends State<InstafeedReelsModal> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;
  bool _isGlobalMuted = false;
  // When on, a reel that reaches its end moves to the next one.
  bool _autoAdvance = true;
  int? _advancingFrom;

  // Video controller pool for instant zero-lag playback: index -> controller
  final Map<int, VideoPlayerController> _controllerPool = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.reels.isNotEmpty ? widget.reels.length - 1 : 0,
    );
    _pageCtrl = PageController(initialPage: _currentIndex);
    _initController(_currentIndex);
    _recordReelView(_currentIndex);
    // Pre-cache next reel
    if (_currentIndex + 1 < widget.reels.length) {
      _initController(_currentIndex + 1);
    }
  }

  void _recordReelView(int idx) {
    if (idx >= 0 && idx < widget.reels.length) {
      final post = widget.reels[idx];
      final myEmail = widget.repository.currentEmail;
      if (myEmail.isNotEmpty && !post.isViewedBy(myEmail)) {
        widget.repository.recordPostView(
          tourId: widget.tourId,
          postId: post.id,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _controllerPool.values) {
      c.dispose();
    }
    _controllerPool.clear();
    super.dispose();
  }

  VideoPlayerController? _initController(int index) {
    if (index < 0 || index >= widget.reels.length) return null;
    if (_controllerPool.containsKey(index)) return _controllerPool[index];

    final post = widget.reels[index];
    final url =
        post.videoUrl ?? (post.images.isNotEmpty ? post.images.first : null);
    if (url == null || !isRemoteMediaUrl(url)) return null;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controllerPool[index] = controller;
    controller.addListener(() => _onVideoTick(index, controller));

    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(!_autoAdvance);
      controller.setVolume(_isGlobalMuted ? 0.0 : 1.0);
      if (index == _currentIndex) {
        controller.play();
      }
      setState(() {});
    }).catchError((Object e) {
      logWarning('[ReelsModal] Failed to init controller $index: $e');
    });

    return controller;
  }

  Future<void> _toggleLike(TourPostItem post) async {
    final isLiked = post.isLikedBy(widget.repository.currentEmail);
    try {
      await widget.repository.setPostLiked(
        widget.tourId,
        post.id,
        liked: !isLiked,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_like_failed', args: {'error': e}))),
        );
      }
    }
  }

  void _onPageChanged(int newIndex) {
    _advancingFrom = null;
    // Pause previous
    _controllerPool[_currentIndex]?.pause();

    setState(() {
      _currentIndex = newIndex;
    });

    _recordReelView(newIndex);

    // Play current
    final currentCtrl = _initController(_currentIndex);
    currentCtrl?.play();

    // Pre-buffer next reel
    if (_currentIndex + 1 < widget.reels.length) {
      _initController(_currentIndex + 1);
    }

    // Clean up far controllers to conserve memory (keep window: current - 1 to current + 1)
    final keysToRemove = _controllerPool.keys
        .where((k) => (k < _currentIndex - 1) || (k > _currentIndex + 1))
        .toList();
    for (final k in keysToRemove) {
      _controllerPool[k]?.dispose();
      _controllerPool.remove(k);
    }
  }

  static bool _hasEnded(VideoPlayerValue value) =>
      value.isInitialized &&
      value.duration > Duration.zero &&
      value.position >= value.duration;

  void _onVideoTick(int index, VideoPlayerController controller) {
    if (!_autoAdvance || index != _currentIndex) return;
    final value = controller.value;
    // A scroll that was dragged back never changes the page, so the reel is
    // free to advance again once it is played from before its end.
    if (!_hasEnded(value)) {
      _advancingFrom = null;
      return;
    }
    if (_advancingFrom == index || value.isPlaying) return;
    _advanceFrom(index);
  }

  /// Scrolls to the reel after [index]. The last reel stays on its last frame.
  void _advanceFrom(int index) {
    if (index + 1 >= widget.reels.length) return;
    _advancingFrom = index;
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _toggleAutoAdvance() {
    setState(() => _autoAdvance = !_autoAdvance);
    for (final c in _controllerPool.values) {
      c.setLooping(!_autoAdvance);
    }
    // Turning it on at the end of a reel moves on straight away.
    final current = _controllerPool[_currentIndex];
    if (_autoAdvance && current != null && _hasEnded(current.value)) {
      _advanceFrom(_currentIndex);
    }
  }

  void _toggleMute() {
    setState(() => _isGlobalMuted = !_isGlobalMuted);
    for (final c in _controllerPool.values) {
      c.setVolume(_isGlobalMuted ? 0.0 : 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reels.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Text(context.l10n.translate('ig_no_reels'),
              style: const TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        itemCount: widget.reels.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final post = widget.reels[index];
          final controller = _controllerPool[index];

          return _ReelPageItem(
            post: post,
            controller: controller,
            isActive: index == _currentIndex,
            isMuted: _isGlobalMuted,
            onToggleMute: _toggleMute,
            autoAdvance: _autoAdvance,
            onToggleAutoAdvance: _toggleAutoAdvance,
            onOpenComments: () => widget.onOpenComments?.call(post),
            onShare: () => widget.onShare?.call(post),
            onAddToLedger: () => widget.onAddToLedger?.call(post),
            onLikeToggle: () => _toggleLike(post),
            currentEmail: widget.repository.currentEmail,
          );
        },
      ),
    );
  }
}

class _ReelPageItem extends StatefulWidget {
  final TourPostItem post;
  final VideoPlayerController? controller;
  final bool isActive;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final bool autoAdvance;
  final VoidCallback onToggleAutoAdvance;
  final VoidCallback onOpenComments;
  final VoidCallback onShare;
  final VoidCallback onAddToLedger;
  final VoidCallback onLikeToggle;
  final String currentEmail;

  const _ReelPageItem({
    required this.post,
    required this.controller,
    required this.isActive,
    required this.isMuted,
    required this.onToggleMute,
    required this.autoAdvance,
    required this.onToggleAutoAdvance,
    required this.onOpenComments,
    required this.onShare,
    required this.onAddToLedger,
    required this.onLikeToggle,
    required this.currentEmail,
  });

  @override
  State<_ReelPageItem> createState() => _ReelPageItemState();
}

class _ReelPageItemState extends State<_ReelPageItem>
    with SingleTickerProviderStateMixin {
  bool _isCleanScreen = false;
  bool _showHeartBurst = false;
  bool? _optimisticLiked;
  int _optimisticLikeDelta = 0;
  late final AnimationController _discRotCtrl;

  @override
  void didUpdateWidget(_ReelPageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.likes.length != widget.post.likes.length) {
      _optimisticLiked = null;
      _optimisticLikeDelta = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _discRotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _discRotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLiked =
        _optimisticLiked ?? widget.post.isLikedBy(widget.currentEmail);
    final likeCount =
        math.max(0, widget.post.likes.length + _optimisticLikeDelta);
    final ctrl = widget.controller;
    final isReady = ctrl != null && ctrl.value.isInitialized;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Viewport with Hold-to-Pause Clean Screen Detector
        GestureDetector(
          onTap: () {
            if (isReady) {
              if (ctrl.value.isPlaying) {
                ctrl.pause();
              } else {
                ctrl.play();
              }
            }
          },
          onDoubleTap: () {
            setState(() {
              _showHeartBurst = true;
              final current = _optimisticLiked ??
                  widget.post.isLikedBy(widget.currentEmail);
              if (!current) {
                _optimisticLiked = true;
                _optimisticLikeDelta = 1;
              }
            });
            widget.onLikeToggle();
          },
          onLongPressStart: (_) {
            setState(() => _isCleanScreen = true);
            ctrl?.pause();
          },
          onLongPressEnd: (_) {
            setState(() => _isCleanScreen = false);
            ctrl?.play();
          },
          child: Container(
            color: Colors.black,
            child: isReady
                ? ReelFittedVideo(
                    pictureSize: ctrl.value.size,
                    wholePicture: true,
                    child: VideoPlayer(ctrl),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.post.coverUrl != null &&
                          isRemoteMediaUrl(widget.post.coverUrl!))
                        ReelPoster(
                          imageUrl: widget.post.coverUrl!,
                          pictureAspect: widget.post.aspectRatio,
                          wholePicture: true,
                          errorWidget: Container(color: Colors.black),
                        ),
                      const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white38),
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        // Double-tap heart burst animation
        InstafeedHeartBurst(
          show: _showHeartBurst,
          onComplete: () => setState(() => _showHeartBurst = false),
        ),

        // Animated clean-screen overlay controls
        AnimatedOpacity(
          opacity: _isCleanScreen ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Top Bar: Back button, Mute, Title
              Positioned(
                top: 40,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: context.l10n.translate('ig_back'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      context.l10n.translate('ig_reels_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: widget.autoAdvance
                          ? context.l10n.translate('ig_auto_next_on')
                          : context.l10n.translate('ig_auto_next_off'),
                      icon: Icon(
                        widget.autoAdvance
                            ? Icons.playlist_play_rounded
                            : Icons.repeat_one_rounded,
                        color: Colors.white,
                      ),
                      onPressed: widget.onToggleAutoAdvance,
                    ),
                    IconButton(
                      tooltip: widget.isMuted
                          ? context.l10n.translate('ig_unmute')
                          : context.l10n.translate('ig_mute'),
                      icon: Icon(
                        widget.isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                      ),
                      onPressed: widget.onToggleMute,
                    ),
                  ],
                ),
              ),

              // Right-hand Vertical Action Stack
              Positioned(
                bottom: 60,
                right: 12,
                child: Column(
                  children: [
                    // Like button
                    IconButton(
                      tooltip: isLiked
                          ? context.l10n.translate('ig_unlike')
                          : context.l10n.translate('ig_like'),
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.redAccent : Colors.white,
                        size: 32,
                      ),
                      onPressed: () {
                        setState(() {
                          final current = _optimisticLiked ??
                              widget.post.isLikedBy(widget.currentEmail);
                          _optimisticLiked = !current;
                          _optimisticLikeDelta = !current ? 1 : -1;
                        });
                        widget.onLikeToggle();
                      },
                    ),
                    Text(
                      '$likeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Comments button
                    IconButton(
                      tooltip: context.l10n.translate('ig_comment'),
                      icon: const Icon(Icons.chat_bubble_outline,
                          color: Colors.white, size: 30),
                      onPressed: widget.onOpenComments,
                    ),
                    Text(
                      '${widget.post.commentCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Share button
                    IconButton(
                      tooltip: context.l10n.translate('ig_share'),
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 28),
                      onPressed: widget.onShare,
                    ),
                    const SizedBox(height: 16),

                    // View counter
                    const Icon(Icons.visibility_outlined,
                        color: Colors.white, size: 26),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.post.effectiveViewCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Unique Travel Superpower: Add to Trip Ledger
                    IconButton(
                      icon: const Icon(Icons.receipt_long_rounded,
                          color: AppColors.mintGreen, size: 28),
                      tooltip: context.l10n.translate('ig_add_to_ledger'),
                      onPressed: widget.onAddToLedger,
                    ),
                    Text(
                      context.l10n.translate('ig_ledger_short'),
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Rotating Vinyl Sound Disc
                    RotationTransition(
                      turns: _discRotCtrl,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade900,
                          border: Border.all(color: Colors.white30, width: 2),
                        ),
                        child: const Icon(Icons.music_note,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Left: Author Info, Caption, Landmark Tag & Audio Ticker
              Positioned(
                bottom: 30,
                left: 16,
                right: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author Row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.mintGreen,
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
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.post.authorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 4)
                            ],
                          ),
                        ),
                        if (widget.post.location.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 11, color: Colors.redAccent),
                                const SizedBox(width: 2),
                                Text(
                                  widget.post.location,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Caption
                    if (widget.post.caption.isNotEmpty)
                      Text(
                        widget.post.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 4)
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),

                    // Sound Track Attribution
                    Row(
                      children: [
                        const Icon(Icons.graphic_eq,
                            color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          widget.post.audioTitle ??
                              context.l10n.translate('ig_original_audio'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Interactive Draggable Timeline Scrubber at very bottom
              if (isReady)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder(
                    valueListenable: ctrl,
                    builder: (context, VideoPlayerValue val, _) {
                      final duration = val.duration.inMilliseconds.toDouble();
                      final position = val.position.inMilliseconds
                          .toDouble()
                          .clamp(0.0, duration);

                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4),
                          trackHeight: 2,
                          activeTrackColor: AppColors.mintGreen,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: AppColors.mintGreen,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: position,
                          max: duration > 0 ? duration : 1.0,
                          onChanged: (pos) {
                            ctrl.seekTo(Duration(milliseconds: pos.toInt()));
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
