import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'instafeed_carousel.dart';
import 'instafeed_travel_banners.dart';
import 'instafeed_zoomable_media.dart';

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
  final void Function(TourPostItem post)? onOpenComments;
  final void Function(TourPostItem post)? onShare;
  final void Function(TourPostItem post)? onAddToLedger;
  final void Function(String hashtag)? onHashtagTap;
  final VoidCallback onBookmarkToggle;
  final VoidCallback? onPostChanged;
  final String? seatNumber;
  final String? roomNumber;

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
    this.onHashtagTap,
    required this.onBookmarkToggle,
    this.onPostChanged,
    this.seatNumber,
    this.roomNumber,
  });

  @override
  State<InstafeedPostCard> createState() => _InstafeedPostCardState();
}

class _InstafeedPostCardState extends State<InstafeedPostCard> {
  bool _showHeartBurst = false;
  bool _showTags = false;
  bool _isPlayingAudio = false;

  bool get _isAuthor =>
      widget.post.authorEmail == widget.repository.currentEmail;

  Future<void> _toggleLike() async {
    final isLiked = widget.post.isLikedBy(widget.repository.currentEmail);
    try {
      await widget.repository.setPostLiked(
        widget.tourId,
        widget.post.id,
        liked: !isLiked,
      );
      widget.onPostChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('লাইক করা যায়নি: $e')),
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
          SnackBar(content: Text('পিন পরিবর্তন ব্যর্থ: $e')),
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
          SnackBar(content: Text('সেটিংস পরিবর্তন ব্যর্থ: $e')),
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
          SnackBar(content: Text('সেটিংস পরিবর্তন ব্যর্থ: $e')),
        );
      }
    }
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('পোস্ট মুছবেন?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'পোস্ট এবং এর সকল মন্তব্য ও মিডিয়া চিরতরে মুছে যাবে।',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('মুছুন'),
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
          SnackBar(content: Text('পোস্ট মুছে ফেলা যায়নি: $e')),
        );
      }
    }
  }

  void _showPostMenu() {
    final canManage = _isAuthor || widget.isAdmin;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (canManage) ...[
                ListTile(
                  leading: Icon(
                    widget.post.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    color: Colors.amber,
                  ),
                  title: Text(
                    widget.post.isPinned ? 'ফিড থেকে আনপিন করুন' : 'ফিডের শীর্ষে পিন করুন',
                    style: const TextStyle(color: Colors.white),
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
                    color: Colors.white70,
                  ),
                  title: Text(
                    widget.post.hideLikeCount ? 'লাইক সংখ্যা দেখান' : 'লাইক সংখ্যা লুকান',
                    style: const TextStyle(color: Colors.white),
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
                    color: Colors.white70,
                  ),
                  title: Text(
                    widget.post.disableComments
                        ? 'মন্তব্য চালু করুন'
                        : 'মন্তব্য বন্ধ করুন',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleCommentsDisabled();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Color(0xFF00C853)),
                title: const Text('ট্রিপ লেজারে খরচ হিসেবে যোগ করুন',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onAddToLedger?.call(widget.post);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_border, color: Colors.white70),
                title: Text(
                  widget.isBookmarked ? 'সংগ্রহ থেকে সরান' : 'সংগ্রহে সেভ করুন',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onBookmarkToggle();
                },
              ),
              if (canManage)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('পোস্ট মুছুন',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deletePost();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAuthorLogistics() {
    InstafeedMemberLogisticsDialog.show(
      context,
      authorName: widget.post.authorName,
      authorEmail: widget.post.authorEmail,
      authorPhoto: widget.post.authorPhoto,
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
            style: const TextStyle(
              color: Color(0xFF00C853),
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

  @override
  Widget build(BuildContext context) {
    final isLiked = widget.post.isLikedBy(widget.repository.currentEmail);
    final mediaList = widget.post.images.isNotEmpty
        ? widget.post.images
        : (widget.post.videoUrl != null ? [widget.post.videoUrl!] : <String>[]);
    final timeStr = DateFormat('MMM d, h:mm a').format(widget.post.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF161616),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned post bar if pinned
          if (widget.post.isPinned)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Colors.amber.withValues(alpha: 0.12),
              child: const Row(
                children: [
                  Icon(Icons.push_pin, size: 14, color: Colors.amber),
                  SizedBox(width: 6),
                  Text(
                    'পিন্ড পোস্ট (Pinned Post)',
                    style: TextStyle(
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
                                style: const TextStyle(
                                  color: Colors.white,
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
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.seatNumber!,
                                style: const TextStyle(
                                  color: Color(0xFF00C853),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (widget.post.location.isNotEmpty)
                        Text(
                          widget.post.location,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),

                // Audio indicator pill if audio track attached
                if (widget.post.audioTitle != null)
                  InkWell(
                    onTap: () => setState(() => _isPlayingAudio = !_isPlayingAudio),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: _isPlayingAudio
                            ? const Color(0xFF00C853).withValues(alpha: 0.2)
                            : Colors.white10,
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
                                ? const Color(0xFF00C853)
                                : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.post.audioTitle!,
                            style: TextStyle(
                              color: _isPlayingAudio
                                  ? const Color(0xFF00C853)
                                  : Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  onPressed: _showPostMenu,
                ),
              ],
            ),
          ),

          // Media Viewport with Pinch-to-Zoom, Carousel & Double Tap Heart Pop
          Stack(
            children: [
              InstafeedCarousel(
                imageUrls: mediaList,
                aspectRatio: widget.post.aspectRatio ?? 1.0,
                colorFilter: widget.colorFilter,
                onDoubleTap: _onDoubleTap,
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
                        border: Border.all(color: Colors.white30),
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
                            style: const TextStyle(
                              color: Colors.white,
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
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.redAccent : Colors.white,
                    size: 26,
                  ),
                  onPressed: _toggleLike,
                ),
                if (!widget.post.disableComments)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline,
                        color: Colors.white, size: 24),
                    onPressed: () => widget.onOpenComments?.call(widget.post),
                  ),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => widget.onShare?.call(widget.post),
                ),
                const Spacer(),

                // Add to Trip Ledger 1-tap button
                IconButton(
                  icon: const Icon(Icons.receipt_long_rounded,
                      color: Color(0xFF00C853), size: 24),
                  tooltip: 'ট্রিপ লেজারে যোগ করুন',
                  onPressed: () => widget.onAddToLedger?.call(widget.post),
                ),

                // Bookmark / Save
                IconButton(
                  icon: Icon(
                    widget.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: widget.isBookmarked
                        ? const Color(0xFF00C853)
                        : Colors.white,
                    size: 24,
                  ),
                  onPressed: widget.onBookmarkToggle,
                ),
              ],
            ),
          ),

          // Like counter (unless hidden)
          if (!widget.post.hideLikeCount && widget.post.likes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '${widget.post.likes.length} জন পছন্দ করেছেন',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),

          // Caption with clickable hashtags
          if (widget.post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
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
                  'সকল ${widget.post.commentCount}টি মন্তব্য দেখুন',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),

          // Timestamp
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Text(
              timeStr,
              style: const TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
