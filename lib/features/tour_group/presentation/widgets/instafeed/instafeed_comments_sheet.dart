import 'package:flutter/material.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import '../../../../../core/theme/colors.dart';

/// 2-level nested threaded comments sheet with likes, pins, author badges,
/// and quick emoji reactions.
class InstafeedCommentsSheet extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourPostItem post;
  final bool isAdmin;
  final int? targetMediaIndex;

  const InstafeedCommentsSheet({
    super.key,
    required this.repository,
    required this.tourId,
    required this.post,
    this.isAdmin = false,
    this.targetMediaIndex,
  });

  @override
  State<InstafeedCommentsSheet> createState() => _InstafeedCommentsSheetState();
}

class _InstafeedCommentsSheetState extends State<InstafeedCommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  TourCommentItem? _replyingTo;
  int? _taggedSlideIndex;
  final Set<String> _expandedParentIds = {};
  bool _isSubmitting = false;

  static const List<String> _quickEmojis = ['❤️', '🔥', '👏', '😍', '😂', '🙌'];

  @override
  void initState() {
    super.initState();
    if (widget.targetMediaIndex != null) {
      _taggedSlideIndex = widget.targetMediaIndex;
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isPostAuthor =>
      widget.repository.currentEmail == widget.post.authorEmail;

  Future<void> _submitComment({String? overrideText, String? reaction}) async {
    var text = (overrideText ?? _commentCtrl.text).trim();
    if (text.isEmpty && reaction == null) return;

    if (_taggedSlideIndex != null && text.isNotEmpty && !text.startsWith('[ছবি')) {
      text = '[ছবি ${_taggedSlideIndex! + 1}] $text';
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.repository.addComment(
        tourId: widget.tourId,
        postId: widget.post.id,
        text: text,
        reaction: reaction,
        parentId: _replyingTo?.id,
      );

      if (_replyingTo != null) {
        _expandedParentIds.add(_replyingTo!.id);
      }

      _commentCtrl.clear();
      setState(() {
        _replyingTo = null;
        _taggedSlideIndex = null;
        _isSubmitting = false;
      });
      _focusNode.unfocus();
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('মন্তব্য পাঠানো যায়নি: $e')),
        );
      }
    }
  }

  void _startReply(TourCommentItem comment) {
    setState(() {
      _replyingTo = comment;
      _commentCtrl.text = '@${comment.authorName} ';
      _commentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentCtrl.text.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
      if (_commentCtrl.text.startsWith('@')) {
        _commentCtrl.clear();
      }
    });
    _focusNode.unfocus();
  }

  Future<void> _toggleLike(TourCommentItem comment) async {
    final isLiked = comment.isLikedBy(widget.repository.currentEmail);
    try {
      await widget.repository.setCommentLiked(
        widget.tourId,
        widget.post.id,
        comment.id,
        liked: !isLiked,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('লাইক করা যায়নি: $e')),
        );
      }
    }
  }

  Future<void> _togglePin(TourCommentItem comment) async {
    final newPinned = !comment.isPinned;
    try {
      await widget.repository.setCommentPinned(
        widget.tourId,
        widget.post.id,
        comment.id,
        isPinned: newPinned,
        isAuthorLiked: _isPostAuthor ? true : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('পিন পরিবর্তন করা যায়নি: $e')),
        );
      }
    }
  }

  Future<void> _deleteComment(TourCommentItem comment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('মন্তব্য মুছবেন?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'এই মন্তব্যটি চিরতরে মুছে ফেলা হবে।',
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
      await widget.repository.deleteComment(
        widget.tourId,
        widget.post.id,
        comment.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('মুছে ফেলা যায়নি: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final totalHeight = mediaQuery.size.height * 0.85;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        height: bottomInset > 0
            ? totalHeight - bottomInset
            : (mediaQuery.size.height * 0.78),
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'মন্তব্যসমূহ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_taggedSlideIndex != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.darkGreen,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.mintGreen, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ছবি ${_taggedSlideIndex! + 1}',
                            style: const TextStyle(
                              color: AppColors.mintGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() => _taggedSlideIndex = null),
                            child: const Icon(Icons.close,
                                size: 12, color: AppColors.mintGreen),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'বন্ধ করুন',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: Colors.white10),

          // Comments List
          Expanded(
            child: StreamBuilder<List<TourCommentItem>>(
              stream: widget.repository
                  .watchComments(widget.tourId, widget.post.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'লোড করা যায়নি: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                final allComments = snapshot.data!;
                if (allComments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        const Text(
                          'এখনও কোনো মন্তব্য নেই।\nপ্রথম মন্তব্যটি আপনিই করুন!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, height: 1.4),
                        ),
                      ],
                    ),
                  );
                }

                // Partition into top-level and replies
                final topLevel = allComments.where((c) => !c.isReply).toList();
                final repliesMap = <String, List<TourCommentItem>>{};
                for (final c in allComments.where((c) => c.isReply)) {
                  repliesMap.putIfAbsent(c.parentId!, () => []).add(c);
                }

                // Sort: pinned top comments first, then chronological
                topLevel.sort((a, b) {
                  if (a.isPinned && !b.isPinned) return -1;
                  if (!a.isPinned && b.isPinned) return 1;
                  return a.createdAt.compareTo(b.createdAt);
                });

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: topLevel.length,
                  itemBuilder: (context, index) {
                    final parent = topLevel[index];
                    final replies = repliesMap[parent.id] ?? const [];
                    final isExpanded = _expandedParentIds.contains(parent.id);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCommentRow(parent),
                        if (replies.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 48, top: 4, bottom: 4),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedParentIds.remove(parent.id);
                                  } else {
                                    _expandedParentIds.add(parent.id);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 1,
                                      color: Colors.white24,
                                      margin: const EdgeInsets.only(right: 8),
                                    ),
                                    Text(
                                      isExpanded
                                          ? 'উত্তর লুকান'
                                          : '${replies.length}টি উত্তর দেখুন',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      size: 16,
                                      color: Colors.white54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (isExpanded)
                            ...replies.map((reply) => Padding(
                                  padding: const EdgeInsets.only(left: 44),
                                  child: _buildCommentRow(reply, isReply: true),
                                )),
                        ],
                        const SizedBox(height: 12),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Replying To Banner
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade900,
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: AppColors.mintGreen),
                  const SizedBox(width: 8),
                  Text(
                    'উত্তর দিচ্ছেন: ${_replyingTo!.authorName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'বন্ধ করুন',
                    icon: const Icon(Icons.close,
                        size: 18, color: Colors.white54),
                    onPressed: _cancelReply,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

          // Quick Emoji Bar
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFF181818),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _quickEmojis.map((emoji) {
                return InkWell(
                  onTap: () => _submitComment(reaction: emoji),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
          ),

          // Input field
          SafeArea(
            top: false,
            bottom: bottomInset == 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              color: const Color(0xFF1E1E1E),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      focusNode: _focusNode,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitComment(),
                      decoration: InputDecoration(
                        hintText: _replyingTo == null
                            ? 'মন্তব্য লিখুন...'
                            : '${_replyingTo!.authorName}-এর উত্তরে লিখুন...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'মন্তব্য পাঠান',
                    onPressed: _isSubmitting ? null : () => _submitComment(),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded,
                            color: AppColors.mintGreen),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildCommentRow(TourCommentItem comment, {bool isReply = false}) {
    final currentEmail = widget.repository.currentEmail;
    final isLiked = comment.isLikedBy(currentEmail);
    final canDelete = comment.authorEmail == currentEmail ||
        widget.post.authorEmail == currentEmail ||
        widget.isAdmin;
    final canPin = _isPostAuthor || widget.isAdmin;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: isReply ? 14 : 18,
            backgroundColor: AppColors.mintGreen,
            backgroundImage: comment.authorPhoto != null
                ? NetworkImage(comment.authorPhoto!)
                : null,
            child: comment.authorPhoto == null
                ? Text(
                    comment.authorName.isNotEmpty
                        ? comment.authorName[0].toUpperCase()
                        : 'M',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isReply ? 11 : 14,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row & badges
                Row(
                  children: [
                    Text(
                      comment.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (comment.authorEmail == widget.post.authorEmail) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'লেখক',
                          style: TextStyle(
                            color: AppColors.mintGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (comment.isPinned) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.push_pin, size: 12, color: Colors.amber),
                      const Text(
                        ' পিন্ড',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),

                // Text or Reaction
                if (comment.reaction != null && comment.text.isEmpty)
                  Text(comment.reaction!, style: const TextStyle(fontSize: 26))
                else
                  Text(
                    comment.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),

                // Meta row: Reply action, Pin, Delete
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _startReply(comment),
                        child: const Text(
                          'উত্তর দিন',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (comment.isAuthorLiked) ...[
                        const SizedBox(width: 12),
                        const Row(
                          children: [
                            Icon(Icons.favorite,
                                size: 12, color: Colors.redAccent),
                            SizedBox(width: 3),
                            Text(
                              'লেখকের পছন্দ',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (canPin) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _togglePin(comment),
                          child: Text(
                            comment.isPinned ? 'আনপিন' : 'পিন করুন',
                            style: TextStyle(
                              color: comment.isPinned
                                  ? Colors.amber
                                  : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      if (canDelete) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _deleteComment(comment),
                          child: const Text(
                            'মুছুন',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Heart Like button
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: isLiked ? 'লাইক সরান' : 'লাইক করুন',
                icon: Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: isLiked ? Colors.redAccent : Colors.white38,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => _toggleLike(comment),
              ),
              if (comment.likes.isNotEmpty)
                Text(
                  '${comment.likes.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
