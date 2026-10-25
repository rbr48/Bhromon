import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bhromon/features/tour_group/data/tour_channel_repository.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';

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
            content: Text('$channelName চ্যানেলে শেয়ার করা হয়েছে'),
            backgroundColor: const Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('শেয়ার করা যায়নি: $e')),
        );
      }
    }
  }

  Future<void> _shareToStory(BuildContext context) async {
    final media = post.images.isNotEmpty ? post.images.first : post.videoUrl;
    if (media == null) return;

    try {
      await repository.addStory(
        tourId: tourId,
        mediaUrl: media,
        caption: 'পুনঃশেয়ার: ${post.authorName}-এর পোস্ট',
        isVideo: post.isReel,
        videoUrl: post.videoUrl,
      );

      if (context.mounted) {
        Navigator.pop(context);
        onResharedToStory?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('পোস্টটি আপনার স্টোরিতে শেয়ার করা হয়েছে'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('স্টোরিতে শেয়ার ব্যর্থ: $e')),
        );
      }
    }
  }

  void _copyLink(BuildContext context) {
    final link = 'https://app.bhromon.fun/tours/$tourId/posts/${post.id}';
    Clipboard.setData(ClipboardData(text: link));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('পোস্টের লিঙ্ক কপি করা হয়েছে')),
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
            const Text(
              'পোস্টটি শেয়ার করুন',
              style: TextStyle(
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
                backgroundColor: Color(0xFF00C853),
                child: Icon(Icons.auto_stories, color: Colors.white, size: 20),
              ),
              title: const Text('আপনার স্টোরিতে যোগ করুন',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('স্টোরি ট্রে-তে ২৪ ঘণ্টার জন্য থাকবে',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => _shareToStory(context),
            ),
            const Divider(color: Colors.white10),

            // Send to Tour Channels
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'ট্যুর গ্রুপ চ্যানেলে পাঠান',
                style: TextStyle(
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
                title: Text(ch['name'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.send_rounded,
                    size: 16, color: Colors.white38),
                onTap: () => _sendToChannel(
                    context, ch['id'] as String, ch['name'] as String),
              );
            }),

            const Divider(color: Colors.white10),

            // External Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.link,
                  label: 'লিঙ্ক কপি',
                  onTap: () => _copyLink(context),
                ),
                _buildActionButton(
                  icon: Icons.share,
                  label: 'অন্যান্য অ্যাপে',
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
