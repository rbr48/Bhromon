import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bhromon/features/tour_group/data/tour_channel_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/localization/app_localizations.dart';

/// In-app quick send bottom sheet allowing travelers to share a post directly
/// into Tour Channels (#general, #food, #sightseeing, #emergency), reshare to
/// their Story, copy link, or share externally.
class InstafeedShareSheet extends StatelessWidget {
  final TourGroupRepository repository;
  final String tourId;
  final TourPostItem post;
  final VoidCallback? onResharedToStory;

  const InstafeedShareSheet({
    super.key,
    required this.repository,
    required this.tourId,
    required this.post,
    this.onResharedToStory,
  });

  static const List<Map<String, dynamic>> _channels = [
    {
      'id': 'general',
      'name': '# সাধারণ আলোচনা (General)',
      'icon': Icons.chat_bubble_outline,
      'color': Colors.blueAccent,
    },
    {
      'id': 'food',
      'name': '# খাবার ও রেস্তোরাঁ (Food)',
      'icon': Icons.restaurant_menu,
      'color': Colors.orangeAccent,
    },
    {
      'id': 'sightseeing',
      'name': '# দর্শনীয় স্থান (Sightseeing)',
      'icon': Icons.photo_camera_outlined,
      'color': Colors.greenAccent,
    },
    {
      'id': 'emergency',
      'name': '# জরুরি যোগাযোগ (Emergency)',
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
          '📸 [ট্যুর পোস্ট]\n${post.authorName}: ${post.caption.isNotEmpty ? post.caption : "একটি ছবি শেয়ার করেছেন"}\n${post.images.isNotEmpty ? post.images.first : post.videoUrl ?? ""}';

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
      await repository.addStory(
        tourId: tourId,
        mediaUrl: media,
        caption: context.l10n
            .translate('ig_reshare_label', args: {'name': post.authorName}),
        isVideo: post.isReel || post.videoUrl != null,
        videoUrl: post.videoUrl,
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

  void _copyLink(BuildContext context) {
    final link = 'https://app.bhromon.fun/tours/$tourId/posts/${post.id}';
    Clipboard.setData(ClipboardData(text: link));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.translate('ig_link_copied'))),
    );
  }

  void _shareExternal() {
    final link = 'https://app.bhromon.fun/tours/$tourId/posts/${post.id}';
    final text =
        'ভ্রমণ অ্যাপে ${post.authorName}-এর পোস্ট দেখুন:\n${post.caption}\n$link';
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
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
            const SizedBox(height: 14),
            Text(
              context.l10n.translate('ig_share_post_title'),
              style: const TextStyle(
                color: Colors.white,
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
                child: Icon(Icons.auto_stories,
                    color: AppColors.darkGreen, size: 20),
              ),
              title: Text(context.l10n.translate('ig_add_to_story'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(context.l10n.translate('ig_story_lasts'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => _shareToStory(context),
            ),
            const Divider(color: Colors.white10),

            // Send to Tour Channels
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                context.l10n.translate('ig_send_to_channel'),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            ..._channels.map((ch) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      (ch['color'] as Color).withValues(alpha: 0.2),
                  child: Icon(ch['icon'] as IconData,
                      size: 16, color: ch['color'] as Color),
                ),
                title: Text(_channelTitle(context, ch['id'] as String),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.send_rounded,
                    size: 16, color: Colors.white54),
                onTap: () => _sendToChannel(context, ch['id'] as String,
                    _channelTitle(context, ch['id'] as String)),
              );
            }),

            const Divider(color: Colors.white10),

            // External Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.link,
                  label: context.l10n.translate('ig_copy_link'),
                  onTap: () => _copyLink(context),
                ),
                _buildActionButton(
                  icon: Icons.share,
                  label: context.l10n.translate('ig_other_apps'),
                  onTap: () {
                    Navigator.pop(context);
                    _shareExternal();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
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
              backgroundColor: Colors.white12,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
      'name': '# general',
      'icon': Icons.chat_bubble_outline,
      'color': Colors.blueAccent,
    },
    {
      'id': 'food',
      'name': '# food',
      'icon': Icons.restaurant_menu,
      'color': Colors.orangeAccent,
    },
    {
      'id': 'sightseeing',
      'name': '# sightseeing',
      'icon': Icons.photo_camera_outlined,
      'color': Colors.greenAccent,
    },
    {
      'id': 'emergency',
      'name': '# emergency',
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
          '📖 [ট্যুর স্টোরি]\n${story.authorName}: ${story.caption ?? "একটি স্টোরি শেয়ার করেছেন"}\n${story.videoUrl ?? story.mediaUrl}';

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

  void _shareExternal() {
    final link = 'https://app.bhromon.fun/tours/$tourId/stories/${story.id}';
    final text =
        'ভ্রমণ অ্যাপে ${story.authorName}-এর স্টোরি দেখুন:\n${story.caption ?? ""}\n$link';
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
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
            const SizedBox(height: 14),
            Text(
              context.l10n.translate('ig_share_story_title'),
              style: const TextStyle(
                color: Colors.white,
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
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            ..._channels.map((ch) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      (ch['color'] as Color).withValues(alpha: 0.2),
                  child: Icon(ch['icon'] as IconData,
                      size: 16, color: ch['color'] as Color),
                ),
                title: Text(_channelTitle(context, ch['id'] as String),
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.send_rounded,
                    size: 16, color: Colors.white54),
                onTap: () => _sendToChannel(context, ch['id'] as String,
                    _channelTitle(context, ch['id'] as String)),
              );
            }),

            const Divider(color: Colors.white10),

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
                        const CircleAvatar(
                          backgroundColor: Colors.white12,
                          child: Icon(Icons.link, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(context.l10n.translate('ig_copy_link'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _shareExternal();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.white12,
                          child: Icon(Icons.share, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(context.l10n.translate('ig_other_apps'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
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
    );
  }
}
