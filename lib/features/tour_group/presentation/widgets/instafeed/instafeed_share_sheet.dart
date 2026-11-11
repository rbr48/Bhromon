import 'package:flutter/material.dart';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bhromon/features/tour_group/data/tour_channel_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_media_journal.dart';
import 'package:bhromon/features/tour_group/data/tour_media_uploader.dart';
import 'package:bhromon/features/tour_group/domain/models/channel_models.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import 'cross_group_share_sheet.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/utils/logger.dart';

/// The standard channels a post can be shared into. A channel an admin has hidden is not
/// offered, and a channel an admin has titled shows that title.
class _ShareChannelTargets extends StatefulWidget {
  const _ShareChannelTargets({
    required this.repository,
    required this.tourId,
    required this.channels,
    required this.titleOf,
    required this.onPick,
  });

  final TourGroupRepository repository;
  final String tourId;
  final List<Map<String, dynamic>> channels;
  final String Function(BuildContext context, String channelId) titleOf;
  final void Function(String channelId, String title) onPick;

  @override
  State<_ShareChannelTargets> createState() => _ShareChannelTargetsState();
}

class _ShareChannelTargetsState extends State<_ShareChannelTargets> {
  // Opened once, so rebuilding the sheet does not start another listener.
  late final Stream<List<TourChannel>> _docs = () {
    try {
      return TourChannelRepository(groups: widget.repository)
          .watchChannels(widget.tourId);
    } catch (e, st) {
      logWarning('[ShareSheet] watchChannels fallback: $e', e, st);
      return Stream.value(const <TourChannel>[]);
    }
  }();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TourChannel>>(
      stream: _docs,
      builder: (context, snapshot) {
        final docs = snapshot.data ?? const <TourChannel>[];
        final hidden = hiddenBuiltInChannelIds(docs);
        final byId = {for (final c in docs) c.id: c};
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ch in widget.channels)
              if (!hidden.contains(ch['id'] as String))
                _tile(context, ch, byId[ch['id'] as String]),
          ],
        );
      },
    );
  }

  Widget _tile(
      BuildContext context, Map<String, dynamic> ch, TourChannel? doc) {
    final id = ch['id'] as String;
    final override = doc?.titleOverride ?? '';
    final title = override.isNotEmpty ? override : widget.titleOf(context, id);
    final color = ch['color'] as Color;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(ch['icon'] as IconData,
            size: 16, color: context.forest.readable(color)),
      ),
      title: Text(title,
          style: TextStyle(color: context.forest.text, fontSize: 14)),
      trailing:
          Icon(Icons.send_rounded, size: 16, color: context.forest.text54),
      onTap: () => widget.onPick(id, title),
    );
  }
}

/// In-app quick send bottom sheet allowing travelers to share a post directly
/// into Tour Channels (#general, #food, #sightseeing, #emergency), reshare to
/// their Story, copy link, or share externally.
class InstafeedShareSheet extends StatelessWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourPostItem post;
  final VoidCallback? onResharedToStory;
  final String? groupName;
  final TourGroup? group;

  const InstafeedShareSheet({
    super.key,
    required this.repository,
    required this.tourId,
    required this.post,
    this.onResharedToStory,
    this.groupName,
    this.group,
  });

  static const List<Map<String, dynamic>> _channels = [
    {
      'id': 'general',
      'icon': Icons.chat_bubble_outline_rounded,
      'color': Colors.blueAccent,
    },
    {
      'id': 'food',
      'icon': Icons.restaurant_menu_rounded,
      'color': Colors.orangeAccent,
    },
    {
      'id': 'sightseeing',
      'icon': Icons.photo_camera_outlined,
      'color': Colors.greenAccent,
    },
    {
      'id': 'emergency',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.redAccent,
    },
  ];

  /// The name a channel is shown with. The stored channel ids do not change.
  static String _channelTitle(BuildContext context, String channelId) {
    return switch (channelId) {
      'general' => context.l10n.translate('ig_channel_general'),
      'food' => context.l10n.translate('ig_channel_food'),
      'sightseeing' => context.l10n.translate('ig_channel_sightseeing'),
      _ => context.l10n.translate('ig_channel_emergency'),
    };
  }

  Future<void> _sendToChannel(
      BuildContext context, String channelId, String channelName) async {
    try {
      final msg =
          '📸 [গ্রুপ পোস্ট]\n${post.authorName}: ${post.caption.isNotEmpty ? post.caption : context.l10n.translate('ig_chat_photo_fallback')}\n${post.images.isNotEmpty ? post.images.first : post.videoUrl ?? ""}';

      final channelRepo = TourChannelRepository(groups: repository);
      await channelRepo.sendMessage(
        tourId,
        channelId,
        text: msg,
      );

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('ig_shared_to_channel',
                args: {'name': channelName})),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_share_failed', args: {'error': e}))),
        );
      }
    }
  }

  /// The URL of the story's own copy of a media file. A file that is not on the
  /// media server (legacy storage) cannot be copied, so it is used as it is.
  Future<String> _ownCopy(String url) async {
    if (!url.startsWith(TourMediaRef.publicBaseUrl)) return url;
    try {
      return await TourMediaUploader.copyMedia(
        tourId: tourId,
        sourceUrl: url,
        folder: 'stories',
      );
    } catch (e, st) {
      logWarning(
          '[ShareSheet] copyMedia failed, falling back to original URL: $e',
          e,
          st);
      return url;
    }
  }

  Future<void> _shareToStory(BuildContext context) async {
    final media = post.coverUrl ??
        (post.images.isNotEmpty ? post.images.first : post.videoUrl);
    if (media == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('ig_story_share_no_media')),
        ),
      );
      return;
    }

    try {
      // The story gets its own copy of the media. Sharing the post's file would
      // tie the story to the post, so deleting either one would break the other.
      // Read before the awaits below, so the context is not used across them.
      final caption = context.l10n.translate(
        'ig_reshare_label',
        args: {'name': post.authorName},
      );
      final mediaCopy = await _ownCopy(media);
      final videoCopy = post.videoUrl == null
          ? null
          : (post.coverUrl != null
              ? await _ownCopy(post.videoUrl!)
              : mediaCopy);
      await repository.addStory(
        tourId: tourId,
        mediaUrl: mediaCopy,
        caption: caption,
        isVideo: post.isReel || post.videoUrl != null,
        videoUrl: videoCopy,
      );

      if (context.mounted) {
        Navigator.pop(context);
        onResharedToStory?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('ig_shared_to_story')),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n
                  .translate('ig_story_share_failed', args: {'error': e}))),
        );
      }
    }
  }

  void _openCrossGroupShare(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CrossGroupShareSheet(
        repository: repository,
        sourceTourId: tourId,
        sourceTourName: groupName ?? group?.name ?? 'Tour',
        post: post,
      ),
    );
  }

  void _copyLink(BuildContext context) {
    final link = 'https://app.bhromon.fun/tours/$tourId/posts/${post.id}';
    Clipboard.setData(ClipboardData(text: link));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.translate('ig_link_copied'))),
    );
  }

  void _shareExternal(BuildContext context) {
    final link = 'https://app.bhromon.fun/tours/$tourId/posts/${post.id}';
    final text = context.l10n.translate('ig_share_external_text', args: {
      'author': post.authorName,
      'caption': post.caption,
      'link': link,
    });
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.forest.feedSurface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.forest.text24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.translate('ig_share_post_title'),
                  style: TextStyle(
                    color: context.forest.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Share to Story shortcut
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.mintGreen,
                    child: Icon(Icons.auto_stories_rounded,
                        color: AppColors.darkGreen, size: 20),
                  ),
                  title: Text(context.l10n.translate('ig_add_to_story'),
                      style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold)),
                  subtitle: Text(context.l10n.translate('ig_story_lasts'),
                      style: TextStyle(
                          color: context.forest.text54, fontSize: 12)),
                  onTap: () => _shareToStory(context),
                ),

                // Share to Another Group shortcut
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        Colors.purpleAccent.withValues(alpha: 0.18),
                    child: const Icon(Icons.swap_horiz_rounded,
                        color: Colors.purpleAccent, size: 20),
                  ),
                  title: Text(
                      context.l10n.translate('ig_share_to_another_group'),
                      style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      context.l10n.translate('ig_share_to_another_group_sub'),
                      style: TextStyle(
                          color: context.forest.text54, fontSize: 12)),
                  onTap: () => _openCrossGroupShare(context),
                ),
                Divider(color: context.forest.divider10),

                // Send to Tour Channels
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    context.l10n.translate('ig_send_to_channel'),
                    style: TextStyle(
                        color: context.forest.text70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                _ShareChannelTargets(
                  repository: repository,
                  tourId: tourId,
                  channels: _channels,
                  titleOf: _channelTitle,
                  onPick: (channelId, title) =>
                      _sendToChannel(context, channelId, title),
                ),

                Divider(color: context.forest.divider10),

                // External Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      context: context,
                      icon: Icons.link_rounded,
                      label: context.l10n.translate('ig_copy_link'),
                      onTap: () => _copyLink(context),
                    ),
                    _buildActionButton(
                      context: context,
                      icon: Icons.share_rounded,
                      label: context.l10n.translate('ig_other_apps'),
                      onTap: () {
                        Navigator.pop(context);
                        _shareExternal(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: context.forest.divider12,
              child: Icon(icon, color: context.forest.text),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(color: context.forest.text70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet allowing travelers to share an active Story into Tour Channels,
/// copy its link, or share externally.
class InstafeedStoryShareSheet extends StatelessWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourStoryItem story;

  const InstafeedStoryShareSheet({
    super.key,
    required this.repository,
    required this.tourId,
    required this.story,
  });

  static const List<Map<String, dynamic>> _channels = [
    {
      'id': 'general',
      'icon': Icons.chat_bubble_outline_rounded,
      'color': Colors.blueAccent,
    },
    {
      'id': 'food',
      'icon': Icons.restaurant_menu_rounded,
      'color': Colors.orangeAccent,
    },
    {
      'id': 'sightseeing',
      'icon': Icons.photo_camera_outlined,
      'color': Colors.greenAccent,
    },
    {
      'id': 'emergency',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.redAccent,
    },
  ];

  static String _channelTitle(BuildContext context, String channelId) {
    return switch (channelId) {
      'general' => context.l10n.translate('ig_channel_general'),
      'food' => context.l10n.translate('ig_channel_food'),
      'sightseeing' => context.l10n.translate('ig_channel_sightseeing'),
      _ => context.l10n.translate('ig_channel_emergency'),
    };
  }

  Future<void> _sendToChannel(
      BuildContext context, String channelId, String channelName) async {
    try {
      final msg =
          '📖 [গ্রুপ স্টোরি]\n${story.authorName}: ${story.caption ?? context.l10n.translate('ig_chat_story_fallback')}\n${story.videoUrl ?? story.mediaUrl}';

      final channelRepo = TourChannelRepository(groups: repository);
      await channelRepo.sendMessage(
        tourId,
        channelId,
        text: msg,
      );

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.translate('ig_shared_story_to_channel',
                args: {'name': channelName})),
            backgroundColor: AppColors.mintGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                context.l10n.translate('ig_share_failed', args: {'error': e})),
          ),
        );
      }
    }
  }

  void _copyLink(BuildContext context) {
    final link = 'https://app.bhromon.fun/tours/$tourId/stories/${story.id}';
    Clipboard.setData(ClipboardData(text: link));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.translate('ig_story_link_copied')),
      ),
    );
  }

  void _shareExternal(BuildContext context) {
    final link = 'https://app.bhromon.fun/tours/$tourId/stories/${story.id}';
    final text = context.l10n.translate('ig_share_external_story_text', args: {
      'author': story.authorName,
      'caption': story.caption ?? '',
      'link': link,
    });
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.forest.feedSurface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.forest.text24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.translate('ig_share_story_title'),
                  style: TextStyle(
                    color: context.forest.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Send to Tour Channels
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    context.l10n.translate('ig_send_to_channel'),
                    style: TextStyle(
                        color: context.forest.text70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                _ShareChannelTargets(
                  repository: repository,
                  tourId: tourId,
                  channels: _channels,
                  titleOf: _channelTitle,
                  onPick: (channelId, title) =>
                      _sendToChannel(context, channelId, title),
                ),

                Divider(color: context.forest.divider10),

                // External Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    InkWell(
                      onTap: () => _copyLink(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            CircleAvatar(
                              backgroundColor: context.forest.divider12,
                              child: Icon(Icons.link_rounded,
                                  color: context.forest.text),
                            ),
                            const SizedBox(height: 6),
                            Text(context.l10n.translate('ig_copy_link'),
                                style: TextStyle(
                                    color: context.forest.text70,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _shareExternal(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            CircleAvatar(
                              backgroundColor: context.forest.divider12,
                              child: Icon(Icons.share_rounded,
                                  color: context.forest.text),
                            ),
                            const SizedBox(height: 6),
                            Text(context.l10n.translate('ig_other_apps'),
                                style: TextStyle(
                                    color: context.forest.text70,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
