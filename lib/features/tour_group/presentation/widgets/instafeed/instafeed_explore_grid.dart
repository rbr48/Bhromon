import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';
import '../../../../../core/theme/colors.dart';

/// 3-column Explore / Gallery Grid view matching Instagram's Explore / Profile
/// gallery with video reel badges and multi-photo indicators.
class InstafeedExploreGrid extends StatelessWidget {
  final List<TourPostItem> posts;
  final void Function(TourPostItem post) onPostTap;

  const InstafeedExploreGrid({
    super.key,
    required this.posts,
    required this.onPostTap,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_on_outlined,
                size: 54, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            const Text(
              'এখনও কোনো ছবি বা ভিডিও যোগ করা হয়নি।',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final hasValidCover = post.coverUrl != null &&
            isRemoteMediaUrl(post.coverUrl!) &&
            !post.coverUrl!.toLowerCase().endsWith('.mp4');
        final hasValidImage = post.images.isNotEmpty &&
            isRemoteMediaUrl(post.images.first) &&
            !post.images.first.toLowerCase().endsWith('.mp4');
        final thumbnail = hasValidCover
            ? post.coverUrl
            : (hasValidImage ? post.images.first : null);

        return GestureDetector(
          onTap: () => onPostTap(post),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnail != null)
                CachedNetworkImage(
                  imageUrl: thumbnail,
                  fit: BoxFit.cover,
                  placeholder: (context, _) =>
                      Container(color: Colors.grey.shade900),
                  errorWidget: (context, _, __) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2A2A2A), Color(0xFF141414)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.slow_motion_video,
                          color: AppColors.mintGreen, size: 28),
                    ),
                  ),
                )
              else
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A2A2A), Color(0xFF141414)],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      post.isReel ? Icons.slow_motion_video : Icons.image,
                      color: post.isReel ? AppColors.mintGreen : Colors.white24,
                      size: 28,
                    ),
                  ),
                ),

              // Reel / Video Indicator
              if (post.isReel)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                )
              else if (post.images.length > 1)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.collections,
                    color: Colors.white,
                    size: 16,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                ),

              // Pinned badge
              if (post.isPinned)
                const Positioned(
                  bottom: 6,
                  left: 6,
                  child: Icon(
                    Icons.push_pin,
                    color: Colors.amber,
                    size: 14,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                ),

              // Archived badge
              if (post.isArchived)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.archive_outlined,
                        color: Colors.white, size: 12),
                  ),
                ),

              // Like counter on bottom right
              if (post.likes.isNotEmpty)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite,
                            color: Colors.redAccent, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          '${post.likes.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
