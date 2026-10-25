import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';

/// Full-featured Story Viewer supporting both Photos and Videos, interactive
/// Poll stickers with real-time percentages, quick emoji reactions, author
/// viewer analytics drawer, and seamless inter-author story transitions.
class InstafeedStoryViewer extends StatefulWidget {
  final TourGroupRepository repository;
  final String tourId;
  final List<List<TourStoryItem>> authorStoryGroups;
  final int initialGroupIndex;
  final VoidCallback? onHighlightsUpdated;

  const InstafeedStoryViewer({
    super.key,
    required this.repository,
    required this.tourId,
    required this.authorStoryGroups,
    this.initialGroupIndex = 0,
    this.onHighlightsUpdated,
  });

  @override
  State<InstafeedStoryViewer> createState() => _InstafeedStoryViewerState();
}

class _InstafeedStoryViewerState extends State<InstafeedStoryViewer>
    with SingleTickerProviderStateMixin {
  late int _groupIndex;
  int _storyIndex = 0;

  late AnimationController _animCtrl;
  VideoPlayerController? _videoCtrl;
  bool _isVideoLoading = false;
  bool _isPaused = false;

  final TextEditingController _replyCtrl = TextEditingController();

  static const Duration _photoDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex.clamp(
      0,
      widget.authorStoryGroups.isNotEmpty
          ? widget.authorStoryGroups.length - 1
          : 0,
    );

    _animCtrl = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advanceStory();
        }
      });

    _loadCurrentStory();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _videoCtrl?.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  List<TourStoryItem> get _currentAuthorStories =>
      widget.authorStoryGroups.isNotEmpty
          ? widget.authorStoryGroups[_groupIndex]
          : const [];

  TourStoryItem? get _currentStory => _currentAuthorStories.isNotEmpty &&
          _storyIndex < _currentAuthorStories.length
      ? _currentAuthorStories[_storyIndex]
      : null;

  bool get _isAuthor =>
      _currentStory != null &&
      _currentStory!.authorEmail == widget.repository.currentEmail;

  Future<void> _loadCurrentStory() async {
    final story = _currentStory;
    if (story == null) return;

    // Record view in background
    widget.repository.recordStoryView(widget.tourId, story.id);

    _animCtrl.stop();
    _animCtrl.value = 0.0;

    _videoCtrl?.dispose();
    _videoCtrl = null;

    final isVideo = story.isVideo ||
        story.mediaUrl.endsWith('.mp4') ||
        (story.videoUrl != null && story.videoUrl!.isNotEmpty);

    if (isVideo) {
      setState(() => _isVideoLoading = true);
      final videoUrl = story.videoUrl ?? story.mediaUrl;
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

      try {
        await controller.initialize();
        if (!mounted) {
          controller.dispose();
          return;
        }

        setState(() {
          _videoCtrl = controller;
          _isVideoLoading = false;
        });

        final duration = controller.value.duration;
        final animDuration = duration > Duration.zero
            ? (duration.inSeconds > 15 ? const Duration(seconds: 15) : duration)
            : const Duration(seconds: 10);

        _animCtrl.duration = animDuration;
        await controller.play();
        _animCtrl.forward(from: 0.0);
      } catch (e) {
        debugPrint('[StoryViewer] Error loading video: $e');
        if (mounted) {
          setState(() => _isVideoLoading = false);
          _animCtrl.duration = _photoDuration;
          _animCtrl.forward(from: 0.0);
        }
      }
    } else {
      setState(() => _isVideoLoading = false);
      _animCtrl.duration = _photoDuration;
      _animCtrl.forward(from: 0.0);
    }
  }

  void _advanceStory() {
    if (_storyIndex < _currentAuthorStories.length - 1) {
      setState(() => _storyIndex++);
      _loadCurrentStory();
    } else if (_groupIndex < widget.authorStoryGroups.length - 1) {
      // Transition to next author
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _loadCurrentStory();
    } else {
      // Finished all stories
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _loadCurrentStory();
    } else if (_groupIndex > 0) {
      // Transition to previous author's last story
      setState(() {
        _groupIndex--;
        _storyIndex = widget.authorStoryGroups[_groupIndex].length - 1;
      });
      _loadCurrentStory();
    } else {
      _loadCurrentStory();
    }
  }

  void _pause() {
    if (_isPaused) return;
    _isPaused = true;
    _animCtrl.stop();
    _videoCtrl?.pause();
  }

  void _resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _animCtrl.forward();
    _videoCtrl?.play();
  }

  Future<void> _votePoll(int optionIndex) async {
    final story = _currentStory;
    if (story == null || story.poll == null) return;
    if (story.poll!.hasVoted(widget.repository.currentEmail)) return;

    try {
      await widget.repository.voteStoryPoll(
        widget.tourId,
        story.id,
        optionIndex,
      );
      // Local optimistic vote update
      setState(() {
        final updatedPoll =
            story.poll!.withVote(widget.repository.currentEmail, optionIndex);
        _currentAuthorStories[_storyIndex] = story.copyWith(poll: updatedPoll);
      });
    } catch (e) {
      debugPrint('[StoryViewer] Vote error: $e');
    }
  }

  void _sendQuickReaction(String emoji) {
    final story = _currentStory;
    if (story == null) return;

    widget.repository.addStoryReaction(widget.tourId, story.id, emoji);
    final updatedReactions = Map<String, String>.from(story.reactions);
    updatedReactions[widget.repository.currentEmail] = emoji;
    _currentAuthorStories[_storyIndex] =
        story.copyWith(reactions: updatedReactions);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$emoji প্রতিক্রিয়া পাঠানো হয়েছে'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _sendReply() {
    if (_replyCtrl.text.trim().isEmpty) return;
    _replyCtrl.clear();
    FocusScope.of(context).unfocus();
    _resume();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('উত্তর পাঠানো হয়েছে'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showViewersDrawer() {
    _pause();
    final story = _currentStory;
    if (story == null) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.remove_red_eye, color: Color(0xFF00C853)),
                    const SizedBox(width: 8),
                    Text(
                      'দর্শকের তালিকা (${story.viewers.length} জন দেখেছেন)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Poll summary if any
                if (story.poll != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ভোট: ${story.poll!.question}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(story.poll!.options.length, (idx) {
                          final opt = story.poll!.options[idx];
                          final count = story.poll!.voteCountFor(idx);
                          final pct = story.poll!.percentageFor(idx);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(opt,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                ),
                                Text(
                                  '$count ভোট (${pct.toStringAsFixed(0)}%)',
                                  style: const TextStyle(
                                      color: Color(0xFF00C853),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Viewers list
                if (story.viewers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'এখনও কেউ স্টোরিটি দেখেনি।',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: story.viewers.length,
                      itemBuilder: (context, idx) {
                        final email = story.viewers[idx];
                        final reaction = story.reactions[email];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF00C853),
                            child: Text(
                              email.isNotEmpty ? email[0].toUpperCase() : 'M',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            email,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                          trailing: reaction != null
                              ? Text(reaction,
                                  style: const TextStyle(fontSize: 22))
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(_resume);
  }

  Future<void> _saveToHighlight() async {
    final story = _currentStory;
    if (story == null) return;

    _pause();
    final titleCtrl = TextEditingController(text: 'স্মৃতি');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('হাইলাইটে যোগ করুন',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: titleCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'হাইলাইটের নাম',
            labelStyle: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00C853)),
            onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim()),
            child: const Text('যোগ করুন'),
          ),
        ],
      ),
    );

    _resume();

    if (result != null && result.isNotEmpty) {
      await widget.repository.addHighlight(
        widget.tourId,
        title: result,
        coverUrl: story.mediaUrl,
        storyIds: [story.id],
      );
      widget.onHighlightsUpdated?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$result" হাইলাইটে যোগ করা হয়েছে')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    if (story == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (_) => _pause(),
          onTapUp: (details) {
            _resume();
            final width = MediaQuery.of(context).size.width;
            if (details.localPosition.dx < width * 0.3) {
              _previousStory();
            } else {
              _advanceStory();
            }
          },
          onLongPressStart: (_) => _pause(),
          onLongPressEnd: (_) => _resume(),
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -300 &&
                _isAuthor) {
              _showViewersDrawer();
            } else if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Navigator.pop(context);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media Content (Photo or Video)
              Center(
                child: _videoCtrl != null && _videoCtrl!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _videoCtrl!.value.aspectRatio,
                        child: VideoPlayer(_videoCtrl!),
                      )
                    : CachedNetworkImage(
                        imageUrl: story.mediaUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, _) => const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white38),
                          ),
                        ),
                        errorWidget: (context, _, __) => const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.white38, size: 48),
                        ),
                      ),
              ),

              if (_isVideoLoading)
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),

              // Interactive Stickers Layer
              if (story.poll != null)
                Center(
                  child: _buildPollWidget(story.poll!),
                ),

              if (story.sticker != null)
                Positioned(
                  left: MediaQuery.of(context).size.width * story.sticker!.dx -
                      70,
                  top: MediaQuery.of(context).size.height * story.sticker!.dy -
                      25,
                  child: _buildStickerWidget(story.sticker!),
                ),

              // Caption overlay if present
              if (story.caption != null && story.caption!.isNotEmpty)
                Positioned(
                  bottom: 90,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      story.caption!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              // Top Progress Bars & Author Header
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    // Progress bars
                    Row(
                      children:
                          List.generate(_currentAuthorStories.length, (idx) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: AnimatedBuilder(
                              animation: _animCtrl,
                              builder: (context, _) {
                                double progress = 0.0;
                                if (idx < _storyIndex) {
                                  progress = 1.0;
                                } else if (idx == _storyIndex) {
                                  progress = _animCtrl.value;
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white30,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),

                    // Author info & close
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF00C853),
                          backgroundImage: story.authorPhoto != null
                              ? NetworkImage(story.authorPhoto!)
                              : null,
                          child: story.authorPhoto == null
                              ? Text(
                                  story.authorName.isNotEmpty
                                      ? story.authorName[0].toUpperCase()
                                      : 'M',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          story.authorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                        ),
                        const Spacer(),

                        // Highlight button
                        IconButton(
                          icon: const Icon(Icons.bookmark_add_outlined,
                              color: Colors.white),
                          onPressed: _saveToHighlight,
                        ),

                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Bottom Control Bar
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    if (_isAuthor) ...[
                      // Viewers count pill for author
                      Expanded(
                        child: InkWell(
                          onTap: _showViewersDrawer,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.remove_red_eye_outlined,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '${story.viewers.length} জন দেখেছেন (তালিকা দেখতে ট্যাপ করুন)',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Inline reply box for viewers
                      Expanded(
                        child: TextField(
                          controller: _replyCtrl,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendReply(),
                          onTap: _pause,
                          decoration: InputDecoration(
                            hintText: '${story.authorName}-কে বার্তা পাঠান...',
                            hintStyle: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide:
                                  const BorderSide(color: Colors.white38),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Quick emoji reaction chips
                      ...['❤️', '🔥', '😂'].map((emoji) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: () => _sendQuickReaction(emoji),
                            borderRadius: BorderRadius.circular(20),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.black45,
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 18)),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPollWidget(TourStoryPoll poll) {
    final userEmail = widget.repository.currentEmail;
    final hasVoted = poll.hasVoted(userEmail);
    final selectedIdx = poll.selectedOption(userEmail);

    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            poll.question,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(poll.options.length, (idx) {
            final opt = poll.options[idx];
            final pct = poll.percentageFor(idx);
            final isChosen = hasVoted && selectedIdx == idx;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: hasVoted ? null : () => _votePoll(idx),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isChosen
                          ? const Color(0xFF00C853)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Percentage fill bar
                      if (hasVoted)
                        FractionallySizedBox(
                          widthFactor: pct / 100.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isChosen
                                  ? const Color(0xFF00C853)
                                      .withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                opt,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isChosen
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (hasVoted)
                              Text(
                                '${pct.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStickerWidget(TourStorySticker sticker) {
    IconData icon = Icons.location_on;
    Color color = Colors.redAccent;
    if (sticker.type == 'tide') {
      icon = Icons.waves;
      color = Colors.lightBlueAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sticker.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (sticker.subtitle != null)
                Text(
                  sticker.subtitle!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
