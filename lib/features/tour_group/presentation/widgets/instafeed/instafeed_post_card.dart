import 'package:bhromon/core/media/media_access.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/like_state.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'instafeed_carousel.dart';
import 'instafeed_day_label.dart';
import 'instafeed_image_viewer_modal.dart';
import 'instafeed_zoomable_media.dart';
import 'reel_picture.dart';
import 'reel_thumbnail_preview.dart';
import '../member_profile/tour_member_profile_modal.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/utils/logger.dart';
import '../../../../../core/localization/localized_date.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Full-featured Post Card with pinch-to-zoom, dynamic aspect ratio, tagged
/// members, clickable hashtags, pinned post badge, audio pill, travel logistics
/// dialog, and 1-tap Trip Ledger shortcut.
class InstafeedPostCard extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourPostItem post;
  final bool isBookmarked;
  final bool isAdmin;
  final ColorFilter? colorFilter;
  final void Function(TourPostItem post, {int? targetMediaIndex})?
      onOpenComments;
  final void Function(TourPostItem post)? onShare;
  final void Function(TourPostItem post)? onAddToLedger;
  final void Function(TourPostItem post)? onReelTap;
  final void Function(String hashtag)? onHashtagTap;
  final VoidCallback onBookmarkToggle;
  final void Function(TourPostItem post)? onSaveToCollection;
  final VoidCallback? onPostChanged;
  final String? seatNumber;
  final String? roomNumber;

  /// The feed picks one video to play. Only that card holds a player.
  final bool videoPlaying;

  /// Selects this card's video, from its play button.
  final VoidCallback? onVideoTap;

  /// The tour's days, for the edit dialog's day picker.
  final List<TourDayInfo> tourDays;

  const InstafeedPostCard({
    super.key,
    required this.repository,
    required this.tourId,
    required this.post,
    required this.isBookmarked,
    this.isAdmin = false,
    this.colorFilter,
    this.onOpenComments,
    this.onShare,
    this.onAddToLedger,
    this.onReelTap,
    this.onHashtagTap,
    required this.onBookmarkToggle,
    this.onSaveToCollection,
    this.onPostChanged,
    this.tourDays = const [],
    this.seatNumber,
    this.roomNumber,
    this.videoPlaying = false,
    this.onVideoTap,
  });

  @override
  State<InstafeedPostCard> createState() => _InstafeedPostCardState();
}

class _InstafeedPostCardState extends State<InstafeedPostCard> {
  bool _showHeartBurst = false;
  bool _showTags = false;
  bool _isPlayingAudio = false;

  /// The like the user last asked for, shown until the server holds it.
  bool? _optimisticLiked;

  VideoPlayerController? _videoCtrl;
  bool _isVideoInitialized = false;
  bool _isVideoMuted = true;
  bool _isVideoPlaying = false;

  final TextEditingController _inlineCommentCtrl = TextEditingController();
  bool _isSendingComment = false;

  Future<void> _submitInlineComment() async {
    final text = _inlineCommentCtrl.text.trim();
    if (text.isEmpty || _isSendingComment) return;
    setState(() => _isSendingComment = true);
    try {
      await widget.repository.addComment(
        tourId: widget.tourId,
        postId: widget.post.id,
        text: text,
      );
      _inlineCommentCtrl.clear();
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n
                .translate('ig_comment_failed', args: {'error': e})),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkAndInitVideo();
  }

  void _checkAndInitVideo() {
    final vUrl = widget.post.videoUrl;
    if (!widget.videoPlaying || _videoCtrl != null) return;
    if (vUrl != null && isRemoteMediaUrl(vUrl)) {
      _initVideoController(vUrl);
    }
  }

  /// Frees the player. A card without its video selected holds none.
  void _disposeVideo() {
    _videoCtrl?.removeListener(_onVideoStateChanged);
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _isVideoInitialized = false;
    _isVideoPlaying = false;
  }

  void _initVideoController(String url) {
    final ctrl =
        VideoPlayerController.networkUrl(Uri.parse(signedMediaUrl(url)));
    _videoCtrl = ctrl;
    ctrl.initialize().then((_) {
      if (!mounted || _videoCtrl != ctrl) return;
      ctrl.setLooping(true);
      ctrl.setVolume(0.0);
      ctrl.play();
      setState(() {
        _isVideoInitialized = true;
      });
    }).catchError((Object e) {
      logWarning('[InstafeedPostCard] Video init error: $e');
    });
    ctrl.addListener(_onVideoStateChanged);
  }

  void _onVideoStateChanged() {
    if (!mounted || _videoCtrl == null) return;
    final isPlaying = _videoCtrl!.value.isPlaying;
    if (isPlaying != _isVideoPlaying) {
      setState(() => _isVideoPlaying = isPlaying);
    }
  }

  @override
  void didUpdateWidget(InstafeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) _optimisticLiked = null;
    if (LikeState.serverCaughtUp(
      optimistic: _optimisticLiked,
      onServer: widget.post.isLikedBy(widget.repository.currentEmail),
    )) {
      _optimisticLiked = null;
    }
    if (oldWidget.post.videoUrl != widget.post.videoUrl) {
      _disposeVideo();
      _checkAndInitVideo();
    } else if (oldWidget.videoPlaying != widget.videoPlaying) {
      if (widget.videoPlaying) {
        _checkAndInitVideo();
      } else {
        _disposeVideo();
      }
    }
  }

  @override
  void dispose() {
    _disposeVideo();
    _inlineCommentCtrl.dispose();
    super.dispose();
  }

  void _toggleVideoPlayback() {
    if (_videoCtrl == null || !_isVideoInitialized) return;
    setState(() {
      if (_videoCtrl!.value.isPlaying) {
        _videoCtrl!.pause();
      } else {
        _videoCtrl!.play();
      }
    });
  }

  void _toggleVideoMute() {
    if (_videoCtrl == null) return;
    setState(() {
      _isVideoMuted = !_isVideoMuted;
      _videoCtrl!.setVolume(_isVideoMuted ? 0.0 : 1.0);
    });
  }

  bool get _isAuthor =>
      widget.post.authorEmail == widget.repository.currentEmail;

  Future<void> _toggleLike() async {
    final currentLiked = _optimisticLiked ??
        widget.post.isLikedBy(widget.repository.currentEmail);
    final targetLiked = !currentLiked;

    // Instant optimistic update
    setState(() {
      _optimisticLiked = targetLiked;
    });

    try {
      await widget.repository.setPostLiked(
        widget.tourId,
        widget.post.id,
        liked: targetLiked,
      );
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticLiked = currentLiked;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_like_failed', args: {'error': e}))),
        );
      }
    }
  }

  void _onDoubleTap() {
    setState(() => _showHeartBurst = true);
    final currentLiked = _optimisticLiked ??
        widget.post.isLikedBy(widget.repository.currentEmail);
    if (!currentLiked) {
      _toggleLike();
    }
  }

  Future<void> _togglePin() async {
    try {
      await widget.repository.setPostPinned(
        widget.tourId,
        widget.post.id,
        isPinned: !widget.post.isPinned,
      );
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_pin_change_failed', args: {'error': e}))),
        );
      }
    }
  }

  Future<void> _toggleLikeCountVisibility() async {
    try {
      await widget.repository.setPostSettings(
        widget.tourId,
        widget.post.id,
        hideLikeCount: !widget.post.hideLikeCount,
      );
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_settings_failed', args: {'error': e}))),
        );
      }
    }
  }

  Future<void> _toggleCommentsDisabled() async {
    try {
      await widget.repository.setPostSettings(
        widget.tourId,
        widget.post.id,
        disableComments: !widget.post.disableComments,
      );
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_settings_failed', args: {'error': e}))),
        );
      }
    }
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.feedSurface,
        title: Text(context.l10n.translate('ig_post_delete_q'),
            style: TextStyle(color: context.forest.text)),
        content: Text(
          context.l10n.translate('ig_post_delete_body'),
          style: TextStyle(color: context.forest.text70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.translate('ig_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.translate('ig_delete')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.repository.deletePost(widget.post);
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_post_delete_failed', args: {'error': e}))),
        );
      }
    }
  }

  Future<void> _showEditDialog() async {
    final captionCtrl = TextEditingController(text: widget.post.caption);
    final locationCtrl = TextEditingController(text: widget.post.location);
    String selectedDay = widget.post.tourDay;
    final dayNumbers = instafeedDayNumbers(widget.tourDays, selectedDay);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: context.forest.feedSurface,
          title: Text(context.l10n.translate('ig_edit_post'),
              style: TextStyle(color: context.forest.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.translate('ig_caption'),
                    style:
                        TextStyle(color: context.forest.text70, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: captionCtrl,
                  maxLines: 3,
                  style: TextStyle(color: context.forest.text),
                  decoration: InputDecoration(
                    hintText: context.l10n.translate('ig_write_caption'),
                    hintStyle: TextStyle(color: context.forest.text54),
                    filled: true,
                    fillColor: context.forest.feedRaised,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Text(context.l10n.translate('ig_place_label'),
                    style:
                        TextStyle(color: context.forest.text70, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: locationCtrl,
                  style: TextStyle(color: context.forest.text),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.location_on,
                        color: context.forest.accentText, size: 18),
                    hintText: context.l10n.translate('ig_place_hint'),
                    hintStyle: TextStyle(color: context.forest.text54),
                    filled: true,
                    fillColor: context.forest.feedRaised,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
                if (widget.tourDays.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(context.l10n.translate('ig_tour_day'),
                      style: TextStyle(
                          color: context.forest.text70, fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDay,
                    dropdownColor: context.forest.feedRaised,
                    style: TextStyle(color: context.forest.text),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.forest.feedRaised,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                    ),
                    items: [
                      for (final n in dayNumbers)
                        DropdownMenuItem(
                          value: instafeedDayId(n),
                          child: Text(instafeedDayLabel(context, n)),
                        ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => selectedDay = val);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.translate('ig_cancel'),
                  style: TextStyle(color: context.forest.text60)),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.translate('ig_save'),
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (updated == true) {
      try {
        await widget.repository.updatePost(
          widget.tourId,
          widget.post.id,
          caption: captionCtrl.text,
          location: locationCtrl.text,
          tourDay: selectedDay,
        );
        widget.onPostChanged?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.translate('ig_post_edited'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.l10n
                    .translate('ig_post_edit_failed', args: {'error': e}))),
          );
        }
      }
    }
    captionCtrl.dispose();
    locationCtrl.dispose();
  }

  Future<void> _toggleArchive() async {
    final newArchived = !widget.post.isArchived;
    try {
      await widget.repository.setPostArchived(
        widget.tourId,
        widget.post.id,
        isArchived: newArchived,
      );
      widget.onPostChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(newArchived
                  ? context.l10n.translate('ig_post_archived')
                  : context.l10n.translate('ig_post_restored'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_archive_failed', args: {'error': e}))),
        );
      }
    }
  }

  void _showPostMenu() {
    final canManage = _isAuthor || widget.isAdmin;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.feedSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          bottom: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                MediaQuery.of(ctx).padding.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.forest.text24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (canManage) ...[
                    ListTile(
                      leading: const Icon(Icons.edit_outlined,
                          color: Colors.lightBlueAccent),
                      title: Text(context.l10n.translate('ig_edit_post'),
                          style: TextStyle(color: context.forest.text)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showEditDialog();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        widget.post.isArchived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        color: Colors.purpleAccent,
                      ),
                      title: Text(
                        widget.post.isArchived
                            ? context.l10n.translate('ig_unarchive')
                            : context.l10n.translate('ig_archive'),
                        style: TextStyle(color: context.forest.text),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleArchive();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        widget.post.isPinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin,
                        color: Colors.amber,
                      ),
                      title: Text(
                        widget.post.isPinned
                            ? context.l10n.translate('ig_unpin_feed')
                            : context.l10n.translate('ig_pin_feed'),
                        style: TextStyle(color: context.forest.text),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _togglePin();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        widget.post.hideLikeCount
                            ? Icons.visibility
                            : Icons.visibility_off_outlined,
                        color: context.forest.text70,
                      ),
                      title: Text(
                        widget.post.hideLikeCount
                            ? context.l10n.translate('ig_show_like_count')
                            : context.l10n.translate('ig_hide_like_count'),
                        style: TextStyle(color: context.forest.text),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleLikeCountVisibility();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        widget.post.disableComments
                            ? Icons.chat_bubble
                            : Icons.chat_bubble_outline,
                        color: context.forest.text70,
                      ),
                      title: Text(
                        widget.post.disableComments
                            ? context.l10n.translate('ig_turn_on_comments')
                            : context.l10n.translate('ig_turn_off_comments'),
                        style: TextStyle(color: context.forest.text),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleCommentsDisabled();
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(Icons.receipt_long,
                        color: context.forest.accentText),
                    title: Text(context.l10n.translate('ig_add_as_expense'),
                        style: TextStyle(color: context.forest.text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onAddToLedger?.call(widget.post);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.bookmark_border,
                        color: context.forest.text70),
                    title: Text(
                      widget.isBookmarked
                          ? context.l10n.translate('ig_remove_from_collection')
                          : context.l10n.translate('ig_save_to_collection'),
                      style: TextStyle(color: context.forest.text),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onBookmarkToggle();
                    },
                  ),
                  if (widget.onSaveToCollection != null)
                    ListTile(
                      leading: const Icon(Icons.folder_special_outlined,
                          color: Colors.amber),
                      title: Text(
                          context.l10n.translate('ig_add_to_collection'),
                          style: TextStyle(color: context.forest.text)),
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onSaveToCollection!(widget.post);
                      },
                    ),
                  if (canManage)
                    ListTile(
                      leading: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      title: Text(
                          context.l10n.translate('ig_delete_post_label'),
                          style: const TextStyle(color: Colors.redAccent)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _deletePost();
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAuthorLogistics() {
    TourMemberProfileModal.show(
      context,
      tourId: widget.tourId.isNotEmpty ? widget.tourId : widget.post.tourId,
      memberEmail: widget.post.authorEmail,
      memberName: widget.post.authorName,
      memberPhoto: widget.post.authorPhoto,
      seatNumber: widget.seatNumber,
      roomNumber: widget.roomNumber,
    );
  }

  List<InlineSpan> _buildCaptionSpans(String text) {
    final spans = <InlineSpan>[];
    final words = text.split(' ');

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.startsWith('#') && word.length > 1) {
        spans.add(
          TextSpan(
            text: '$word ',
            style: TextStyle(
              color: context.forest.accentText,
              fontWeight: FontWeight.bold,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => widget.onHashtagTap?.call(word),
          ),
        );
      } else {
        spans.add(TextSpan(text: '$word '));
      }
    }

    return spans;
  }

  Widget _buildVideoViewport(BuildContext context) {
    final rawAspect = widget.post.aspectRatio ??
        (_isVideoInitialized && _videoCtrl != null
            ? _videoCtrl!.value.aspectRatio
            : 16 / 9);
    final aspect = rawAspect.clamp(0.65, 1.8);

    return ClipRRect(
      clipBehavior: Clip.hardEdge,
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // A landscape reel is letterboxed on black, not cut.
            const ColoredBox(color: Colors.black),

            // 1. Poster background / Cover / Placeholder
            if (widget.post.coverUrl != null &&
                isRemoteMediaUrl(widget.post.coverUrl!))
              ReelPoster(
                imageUrl: widget.post.coverUrl!,
                pictureAspect: widget.post.aspectRatio,
                wholePicture: widget.post.isReel,
                placeholder: Container(color: context.forest.feedPlaceholder),
                errorWidget: Container(
                  color: context.forest.feedPlaceholder,
                  child: Center(
                    child: Icon(Icons.slow_motion_video,
                        size: 40, color: context.forest.text54),
                  ),
                ),
              )
            else if (widget.post.videoUrl != null &&
                isRemoteMediaUrl(widget.post.videoUrl!))
              ReelThumbnailPreview(
                videoUrl: widget.post.videoUrl!,
                wholePicture: widget.post.isReel,
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF262626), Color(0xFF121212)],
                  ),
                ),
                child: Center(
                  child: Icon(Icons.slow_motion_video,
                      size: 40, color: context.forest.text54),
                ),
              ),

            // 2. Video Player when initialized
            if (_isVideoInitialized && _videoCtrl != null)
              GestureDetector(
                onTap: _toggleVideoPlayback,
                onDoubleTap: _onDoubleTap,
                child: ReelFittedVideo(
                  pictureSize: _videoCtrl!.value.size,
                  wholePicture: widget.post.isReel,
                  child: VideoPlayer(_videoCtrl!),
                ),
              )
            else if (widget.videoPlaying)
              Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(context.forest.text38),
                ),
              )
            else if (widget.onVideoTap != null)
              GestureDetector(
                onTap: widget.onVideoTap,
                child: Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Icon(Icons.play_arrow_rounded,
                        size: 48, color: Colors.white),
                  ),
                ),
              ),

            // 3. Play Icon Overlay when paused
            if (!_isVideoPlaying && _isVideoInitialized)
              GestureDetector(
                onTap: _toggleVideoPlayback,
                child: Container(
                  color: Colors.black26,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

            // 4. "রিল দেখুন" (Watch Reel) Button on Top-Right
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onReelTap?.call(widget.post),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE1306C), Color(0xFF833AB4)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.slow_motion_video,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          context.l10n.translate('ig_watch_reel'),
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 5. Mute / Unmute Button on Bottom-Right
            if (_isVideoInitialized && _videoCtrl != null)
              Positioned(
                bottom: 12,
                right: 12,
                child: GestureDetector(
                  onTap: _toggleVideoMute,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.forest.text38),
                    ),
                    child: Icon(
                      _isVideoMuted ? Icons.volume_off : Icons.volume_up,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // 6. Double-tap Heart Burst Animation
            Positioned.fill(
              child: InstafeedHeartBurst(
                show: _showHeartBurst,
                onComplete: () => setState(() => _showHeartBurst = false),
              ),
            ),

            // 7. Tagged Members Icon on bottom left (if tags present)
            if (widget.post.tags.isNotEmpty)
              Positioned(
                bottom: 12,
                left: 12,
                child: GestureDetector(
                  onTap: () => setState(() => _showTags = !_showTags),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.forest.text38),
                    ),
                    child: Icon(
                      _showTags ? Icons.person : Icons.person_outline,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Tagged members popup overlay
            if (_showTags && widget.post.tags.isNotEmpty)
              Positioned(
                bottom: 44,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.post.tags.map((tagEmail) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '@$tagEmail',
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPostHeaderBadges() {
    final widgets = <Widget>[];
    // A tour with no days (a family circle) shows no day badge.
    final dayBadge =
        widget.tourDays.isEmpty ? '' : _formatDayBadge(widget.post.tourDay);
    if (dayBadge.isNotEmpty) {
      widgets.add(const SizedBox(width: 6));
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: Colors.amber.withValues(alpha: 0.35), width: 0.6),
          ),
          child: Text(
            dayBadge,
            style: const TextStyle(
              color: Colors.amberAccent,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (widget.post.isReel) {
      widgets.add(const SizedBox(width: 5));
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.pinkAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: Colors.pinkAccent.withValues(alpha: 0.4), width: 0.6),
          ),
          child: Text(
            '🎬 ${context.l10n.translate('ig_reels_title')}',
            style: const TextStyle(
              color: Colors.pinkAccent,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  String _formatDayBadge(String tourDay) {
    final n = int.tryParse(tourDay.replaceAll(RegExp(r'[^0-9]'), ''));
    return n == null ? '' : instafeedDayLabel(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final serverLiked = widget.post.isLikedBy(widget.repository.currentEmail);
    final isLiked =
        LikeState.shown(optimistic: _optimisticLiked, onServer: serverLiked);
    final effectiveLikeCount = LikeState.shownCount(
      onServerCount: widget.post.likes.length,
      shownLiked: isLiked,
      onServerLiked: serverLiked,
    );
    final isVideoPost =
        widget.post.videoUrl != null && widget.post.videoUrl!.isNotEmpty;
    final mediaList = widget.post.images;
    final timeStr =
        localizedDateFormat('MMM d, h:mm a').format(widget.post.createdAt);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 600;

    return Container(
      margin: EdgeInsets.only(
        bottom: 16,
        left: isWide ? 12 : 0,
        right: isWide ? 12 : 0,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: isWide ? BorderRadius.circular(16) : BorderRadius.zero,
        border: isWide
            ? Border.all(color: context.forest.divider12, width: 0.8)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned post bar if pinned
          if (widget.post.isPinned)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.amber.withValues(alpha: 0.12),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.translate('ig_pinned_post'),
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Header: Avatar, Name, Seat/Room Quick Chip, Location & Menu
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _showAuthorLogistics,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.mintGreen,
                    backgroundImage: widget.post.authorPhoto != null
                        ? ResizeImage(
                            NetworkImage(
                                signedMediaUrl(widget.post.authorPhoto!)),
                            width: 160)
                        : null,
                    child: widget.post.authorPhoto == null
                        ? Text(
                            widget.post.authorName.isNotEmpty
                                ? widget.post.authorName[0].toUpperCase()
                                : 'M',
                            style: TextStyle(
                              color: context.forest.text,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: _showAuthorLogistics,
                              child: Text(
                                widget.post.authorName,
                                style: TextStyle(
                                  color: context.forest.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (widget.seatNumber != null &&
                              widget.seatNumber!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: context.forest.divider10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.seatNumber!,
                                style: TextStyle(
                                  color: context.forest.accentText,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          ..._buildPostHeaderBadges(),
                        ],
                      ),
                      if (widget.post.location.isNotEmpty)
                        Text(
                          widget.post.location,
                          style: TextStyle(
                            color: context.forest.text54,
                            fontSize: 11,
                          ),
                        ),
                      if (widget.post.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(Icons.people_alt_rounded,
                                  size: 11, color: context.forest.accentText),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  context.l10n.translate('ig_with_tags', args: {
                                    'names': widget.post.tags.join(', ')
                                  }),
                                  style: TextStyle(
                                    color: context.forest.accentText,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Audio indicator pill if audio track attached
                if (widget.post.audioTitle != null)
                  InkWell(
                    onTap: () =>
                        setState(() => _isPlayingAudio = !_isPlayingAudio),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _isPlayingAudio
                            ? AppColors.mintGreen.withValues(alpha: 0.2)
                            : context.forest.divider10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isPlayingAudio
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            size: 14,
                            color: _isPlayingAudio
                                ? context.forest.accentText
                                : context.forest.text70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.post.audioTitle!,
                            style: TextStyle(
                              color: _isPlayingAudio
                                  ? context.forest.accentText
                                  : context.forest.text70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                IconButton(
                  tooltip: context.l10n.translate('ig_more_options'),
                  icon: Icon(Icons.more_vert, color: context.forest.text70),
                  onPressed: _showPostMenu,
                ),
              ],
            ),
          ),

          // Media Viewport with Video Player / Pinch-to-Zoom Carousel & Heart Pop
          if (isVideoPost)
            _buildVideoViewport(context)
          else
            Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                InstafeedCarousel(
                  imageUrls: mediaList,
                  aspectRatio: widget.post.aspectRatio ?? 1.0,
                  colorFilter: widget.colorFilter,
                  onDoubleTap: _onDoubleTap,
                  onImageTap: (idx) {
                    InstafeedImageViewerModal.show(
                      context,
                      repository: widget.repository,
                      tourId: widget.tourId,
                      post: widget.post,
                      initialIndex: idx,
                      onOpenComments: widget.onOpenComments,
                      onShare: widget.onShare,
                      onAddToLedger: widget.onAddToLedger,
                    );
                  },
                ),

                // Double-tap heart burst animation
                Positioned.fill(
                  child: InstafeedHeartBurst(
                    show: _showHeartBurst,
                    onComplete: () => setState(() => _showHeartBurst = false),
                  ),
                ),

                // Tagged Members Icon on bottom left
                if (widget.post.tags.isNotEmpty)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: GestureDetector(
                      onTap: () => setState(() => _showTags = !_showTags),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.forest.text38),
                        ),
                        child: Icon(
                          _showTags ? Icons.person : Icons.person_outline,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                // Tagged members popup overlay
                if (_showTags && widget.post.tags.isNotEmpty)
                  Positioned(
                    bottom: 44,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.post.tags.map((tagEmail) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '@$tagEmail',
                              style: TextStyle(
                                color: context.forest.text,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),

          // Action Buttons Bar: Like, Comment, Share, Ledger, Bookmark
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: isLiked
                      ? context.l10n.translate('ig_unlike')
                      : context.l10n.translate('ig_like'),
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.redAccent : context.forest.text,
                    size: 26,
                  ),
                  onPressed: _toggleLike,
                ),
                if (!widget.post.disableComments)
                  IconButton(
                    tooltip: context.l10n.translate('ig_comment'),
                    icon: Icon(Icons.chat_bubble_outline,
                        color: context.forest.text, size: 24),
                    onPressed: () => widget.onOpenComments?.call(widget.post),
                  ),
                IconButton(
                  tooltip: context.l10n.translate('ig_share'),
                  icon: Icon(Icons.send_rounded,
                      color: context.forest.text, size: 22),
                  onPressed: () => widget.onShare?.call(widget.post),
                ),
                const Spacer(),

                // Add to Trip Ledger 1-tap button
                IconButton(
                  icon: Icon(Icons.receipt_long_rounded,
                      color: context.forest.accentText, size: 24),
                  tooltip: context.l10n.translate('ig_add_to_ledger'),
                  onPressed: () => widget.onAddToLedger?.call(widget.post),
                ),

                // Bookmark / Save (tap toggles, long-press opens collections)
                GestureDetector(
                  onLongPress: widget.onSaveToCollection != null
                      ? () => widget.onSaveToCollection!(widget.post)
                      : null,
                  child: IconButton(
                    tooltip: widget.isBookmarked
                        ? context.l10n.translate('ig_unsave')
                        : context.l10n.translate('ig_save'),
                    icon: Icon(
                      widget.isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: widget.isBookmarked
                          ? context.forest.accentText
                          : context.forest.text,
                      size: 24,
                    ),
                    onPressed: widget.onBookmarkToggle,
                  ),
                ),
              ],
            ),
          ),

          // Like counter and View counter
          if ((!widget.post.hideLikeCount && effectiveLikeCount > 0) ||
              widget.post.effectiveViewCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (!widget.post.hideLikeCount && effectiveLikeCount > 0)
                    Text(
                      context.l10n.translate('ig_liked_by_count',
                          args: {'count': effectiveLikeCount}),
                      style: TextStyle(
                        color: context.forest.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  if (!widget.post.hideLikeCount &&
                      effectiveLikeCount > 0 &&
                      widget.post.effectiveViewCount > 0)
                    Text(' • ',
                        style: TextStyle(
                            color: context.forest.text38, fontSize: 13)),
                  if (widget.post.effectiveViewCount > 0)
                    Text(
                      context.l10n.translate('ig_views_count',
                          args: {'count': widget.post.effectiveViewCount}),
                      style: TextStyle(
                        color: (!widget.post.hideLikeCount &&
                                effectiveLikeCount > 0)
                            ? context.forest.text70
                            : context.forest.text,
                        fontWeight: (!widget.post.hideLikeCount &&
                                effectiveLikeCount > 0)
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                ],
              ),
            ),

          // Caption with clickable hashtags
          if (widget.post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: context.forest.text, fontSize: 13.5),
                  children: [
                    TextSpan(
                      text: '${widget.post.authorName} ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._buildCaptionSpans(widget.post.caption),
                  ],
                ),
              ),
            ),

          // Comment count shortcut
          if (!widget.post.disableComments && widget.post.commentCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: GestureDetector(
                onTap: () => widget.onOpenComments?.call(widget.post),
                child: Text(
                  context.l10n.translate('ig_view_all_comments',
                      args: {'count': widget.post.commentCount}),
                  style: TextStyle(color: context.forest.text54, fontSize: 13),
                ),
              ),
            ),

          // Timestamp & edit/archive status
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Row(
              children: [
                Text(
                  timeStr,
                  style: TextStyle(color: context.forest.text54, fontSize: 11),
                ),
                if (widget.post.isEdited) ...[
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.translate('ig_edited_marker'),
                    style: TextStyle(
                        color: context.forest.text54,
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  ),
                ],
                if (widget.post.isArchived) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.purpleAccent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      context.l10n.translate('ig_archived_badge'),
                      style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Quick inline comment input
          if (!widget.post.disableComments)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.midGreen,
                    backgroundImage: widget.repository.currentPhotoUrl != null
                        ? ResizeImage(
                            NetworkImage(signedMediaUrl(
                                widget.repository.currentPhotoUrl!)),
                            width: 96)
                        : null,
                    child: widget.repository.currentPhotoUrl == null
                        ? Text(
                            widget.repository.currentDisplayName.isNotEmpty
                                ? widget.repository.currentDisplayName[0]
                                    .toUpperCase()
                                : 'M',
                            style: TextStyle(
                              color: context.forest.text,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _inlineCommentCtrl,
                        style: TextStyle(
                            color: context.forest.text, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: context.l10n.translate('ig_write_comment'),
                          hintStyle: TextStyle(
                              color: context.forest.text38, fontSize: 11.5),
                          filled: true,
                          fillColor:
                              context.forest.text.withValues(alpha: 0.06),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide:
                                BorderSide(color: context.forest.divider12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide:
                                BorderSide(color: context.forest.divider12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                                color: AppColors.mintGreen, width: 1.2),
                          ),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _inlineCommentCtrl,
                            builder: (context, value, _) {
                              if (value.text.trim().isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return IconButton(
                                padding: EdgeInsets.zero,
                                icon: _isSendingComment
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.mintGreen,
                                        ),
                                      )
                                    : Icon(
                                        Icons.send_rounded,
                                        size: 16,
                                        color: context.forest.accentText,
                                      ),
                                onPressed: _isSendingComment
                                    ? null
                                    : _submitInlineComment,
                              );
                            },
                          ),
                        ),
                        onSubmitted: (_) => _submitInlineComment(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
