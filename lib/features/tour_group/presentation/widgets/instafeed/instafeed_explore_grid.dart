import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bhromon/features/tour_group/domain/models/tour_post_models.dart';

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
              style: TextStyle(color: Colors.white38),
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
        final thumbnail = post.coverUrl ??
            (post.images.isNotEmpty ? post.images.first : post.videoUrl);

        return GestureDetector(
          onTap: () => onPostTap(post),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnail != null && isRemoteMediaUrl(thumbnail))
                CachedNetworkImage(
                  imageUrl: thumbnail,
                  fit: BoxFit.cover,
                  placeholder: (context, _) =>
                      Container(color: Colors.grey.shade900),
                  errorWidget: (context, _, __) => Container(
                    color: Colors.grey.shade900,
                    child:
                        const Icon(Icons.broken_image, color: Colors.white24),
                  ),
                )
              else
                Container(
                  color: Colors.grey.shade900,
                  child: const Icon(Icons.videocam, color: Colors.white38),
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
            ],
          ),
        );
      },
    );
  }
}
