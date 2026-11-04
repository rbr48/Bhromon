import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/media/media_access.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/app_logger.dart';
import '../data/official_feed_repository.dart';
import '../domain/official_feed_choice.dart';
import '../domain/official_reel.dart';
import 'official_post_create_sheet.dart';

/// The official feed: short reels the Bhromon team publishes. Anyone signed in may read it.
/// Each reel fills the screen. Only the reel on screen holds a video player, and the feed
/// stops playing when the app leaves the foreground.
class OfficialFeedScreen extends StatefulWidget {
  const OfficialFeedScreen({
    super.key,
    this.repository,
    this.loadChoice = OfficialFeedPreference.load,
    this.saveChoice = OfficialFeedPreference.save,
    this.checkPublisher,
  });

  /// Where the feed is read from. Tests pass a fake; the app leaves it null.
  final OfficialFeedRepository? repository;

  /// Reads and keeps the person's answer on this device. Tests pass fakes; the app keeps the
  /// defaults.
  final Future<OfficialFeedChoice> Function() loadChoice;
  final Future<void> Function(OfficialFeedChoice choice) saveChoice;

  /// Checks whether the caller is a platform admin. Tests pass a fake; the app leaves it null.
  final Future<bool> Function()? checkPublisher;

  @override
  State<OfficialFeedScreen> createState() => _OfficialFeedScreenState();
}

class _OfficialFeedScreenState extends State<OfficialFeedScreen>
    with WidgetsBindingObserver {
  late final OfficialFeedRepository _repository =
      widget.repository ?? OfficialFeedRepository();
  late Stream<List<OfficialReel>> _reels = _repository.watchReels();

  /// The reel the person is on.
  int _page = 0;

  /// Whether the app is in the foreground. A reel plays only then.
  bool _inForeground = true;

  OfficialFeedChoice _choice = OfficialFeedChoice.unanswered;

  bool get _following => _choice == OfficialFeedChoice.follow;

  bool _canPublish = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadChoice());
    unawaited(_checkPublisherPermission());
  }

  Future<void> _checkPublisherPermission() async {
    final checker = widget.checkPublisher;
    if (checker != null) {
      final allowed = await checker();
      if (mounted) setState(() => _canPublish = allowed);
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (user.email?.toLowerCase() == 'rajbrur@gmail.com') {
        if (mounted) setState(() => _canPublish = true);
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(user.uid)
          .get();
      final tier = doc.data()?['tier'];
      if (tier == 'pioneer' || tier == 'regionExpert') {
        if (mounted) setState(() => _canPublish = true);
      }
    } catch (_) {
      // Firebase might not be initialized in headless test harness
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _inForeground) {
      setState(() => _inForeground = foreground);
    }
  }

  Future<void> _loadChoice() async {
    final choice = await widget.loadChoice();
    if (mounted) setState(() => _choice = choice);
  }

  /// Starts the feed again after an error. Called from the retry button, never from build.
  void _retry() {
    setState(() => _reels = _repository.watchReels());
  }

  /// Turns the new-post notifications on or off, and keeps the answer on this device.
  Future<void> _toggleFollow() async {
    final follow = !_following;
    final choice =
        follow ? OfficialFeedChoice.follow : OfficialFeedChoice.notNow;
    setState(() => _choice = choice);
    await _repository.setFollowing(follow);
    await widget.saveChoice(choice);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(l10n.translate('official_feed_title')),
        actions: [
          if (_canPublish)
            IconButton(
              tooltip: 'নতুন পোস্ট পাবলিশ করুন',
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.mintGreen,
                size: 26,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final published = await OfficialPostCreateSheet.show(
                  context,
                  repository: _repository,
                );
                if (published == true) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('অফিসিয়াল পোস্ট সফলভাবে প্রকাশিত হয়েছে!'),
                      backgroundColor: AppColors.midGreen,
                    ),
                  );
                  if (mounted) _retry();
                }
              },
            ),
          // The web has no new-post notifications, so the switch is mobile only.
          if (!kIsWeb)
            IconButton(
              tooltip: l10n.translate(
                _following
                    ? 'official_feed_follow_on'
                    : 'official_feed_follow_off',
              ),
              icon: Icon(
                _following
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
              ),
              onPressed: _toggleFollow,
            ),
        ],
      ),
      body: StreamBuilder<List<OfficialReel>>(
        stream: _reels,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return _FeedMessage(
              text: l10n.translate('official_feed_load_failed'),
              action: TextButton(
                onPressed: _retry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.mintGreen,
                ),
                child: Text(l10n.translate('hub_try_again')),
              ),
            );
          }
          final reels = snapshot.data;
          if (reels == null) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (reels.isEmpty) {
            return _FeedMessage(text: l10n.translate('official_feed_empty'));
          }
          // The list can shrink while the person is on its last reel.
          final current = _page < reels.length ? _page : 0;
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: reels.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) => _OfficialReelPage(
              key: ValueKey<String>(reels[index].id),
              reel: reels[index],
              active: _inForeground && index == current,
            ),
          );
        },
      ),
    );
  }
}

/// One reel. Its cover shows until the video is ready. It plays while it is the active page.
class _OfficialReelPage extends StatefulWidget {
  const _OfficialReelPage({
    super.key,
    required this.reel,
    required this.active,
  });

  final OfficialReel reel;

  /// Whether this reel is on screen, in the foreground, and should play.
  final bool active;

  @override
  State<_OfficialReelPage> createState() => _OfficialReelPageState();
}

class _OfficialReelPageState extends State<_OfficialReelPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _paused = false;

  /// Muted until the person turns the sound on, as in the other feeds.
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_start());
  }

  @override
  void didUpdateWidget(covariant _OfficialReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      unawaited(_start());
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  /// Whether [controller] is still the one this page plays, so a late result can be dropped.
  bool _isCurrent(VideoPlayerController controller) =>
      mounted && identical(_controller, controller);

  Future<void> _start() async {
    _stop();
    if (!widget.reel.isVideo) {
      // Photo / image post has no video to stream
      return;
    }
    final video = widget.reel.videoUrl;
    if (video == null) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(signedMediaUrl(video)),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!_isCurrent(controller)) return;
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!_isCurrent(controller)) return;
      await controller.play();
      setState(() => _ready = true);
    } catch (error, stackTrace) {
      logWarning(
        '[OfficialFeed] A reel could not be played',
        error,
        stackTrace,
      );
      if (_isCurrent(controller)) setState(() => _failed = true);
    }
  }

  /// Frees the player. The page then shows its cover again.
  void _stop() {
    final controller = _controller;
    _controller = null;
    _ready = false;
    _failed = false;
    _paused = false;
    unawaited(controller?.dispose());
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final pausing = controller.value.isPlaying;
    setState(() => _paused = pausing);
    if (pausing) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_controller?.setVolume(_muted ? 0 : 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = _controller;
    final isImage = widget.reel.isImage;
    final showVideo = widget.reel.isVideo && _ready && controller != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: showVideo ? _togglePlay : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isImage)
            _CoverImage(url: widget.reel.displayImageUrl)
          else if (!showVideo)
            _CoverImage(url: widget.reel.coverUrl),
          if (showVideo) _VideoFill(controller: controller),
          // Only the reel on screen is loading. The others show their covers.
          if (widget.active && widget.reel.isVideo && !showVideo && !_failed)
            const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          if (_failed)
            _FeedMessage(text: l10n.translate('official_feed_play_failed')),
          if (showVideo && _paused)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white70,
                size: 88,
              ),
            ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: isImage ? 16 : 72,
            bottom: 28,
            child: _ReelCaption(
              badge: l10n.translate('official_feed_badge'),
              caption: widget.reel.caption,
            ),
          ),
          if (!isImage)
            Positioned(
              right: 8,
              bottom: 20,
              child: IconButton(
                tooltip: l10n.translate(
                  _muted ? 'official_feed_sound_on' : 'official_feed_sound_off',
                ),
                color: Colors.white,
                icon: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                ),
                onPressed: showVideo ? _toggleMute : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final cover = url;
    if (cover == null) return const ColoredBox(color: Colors.black);
    return CachedNetworkImage(
      imageUrl: signedMediaUrl(cover),
      fit: BoxFit.cover,
      placeholder: (context, url) => const ColoredBox(color: Colors.black),
      errorWidget: (context, url, error) =>
          const ColoredBox(color: Colors.black),
    );
  }
}

/// The video, scaled to cover the page and cropped to fit it.
class _VideoFill extends StatelessWidget {
  const _VideoFill({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (size.isEmpty) return const SizedBox.expand();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _ReelCaption extends StatefulWidget {
  const _ReelCaption({required this.badge, required this.caption});

  final String badge;
  final String caption;

  @override
  State<_ReelCaption> createState() => _ReelCaptionState();
}

class _ReelCaptionState extends State<_ReelCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.midGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(
              widget.badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (widget.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              widget.caption,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A line of text on the black page, for an empty feed, a failure or a reel that will not play.
class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            if (action case final button?) ...[
              const SizedBox(height: 12),
              button,
            ],
          ],
        ),
      ),
    );
  }
}
