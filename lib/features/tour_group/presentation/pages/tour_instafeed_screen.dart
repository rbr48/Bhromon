import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_upload.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/tour_post_models.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../domain/services/media_rules.dart';
import '../../domain/services/tour_video_compressor.dart';

// Bengali numeral helper
String toBengaliNum(int number) {
  const digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return number.toString().split('').map((c) {
    final idx = int.tryParse(c);
    return idx != null ? digits[idx] : c;
  }).join('');
}

// Preset locations fallback
const List<String> kTourLandmarks = [
  'প্রধান হোটেল / রিসোর্ট (Hotel / Resort)',
  'দর্শনীয় স্পট ও পয়েন্ট (Scenic Spot)',
  'যাত্রা পথ / হাইওয়ে বিরতি (Journey / Highway)',
  'রেস্তোরাঁ ও ফুড পয়েন্ট (Restaurant & Food)',
  'অন্যান্য স্থান (Others)',
];

// Instagram 8 Color Filter Matrices
const Map<String, List<double>> kFilterMatrices = {
  'normal': [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  'clarendon': [
    1.2,
    0,
    0,
    0,
    -10,
    0,
    1.25,
    0,
    0,
    -10,
    0,
    0,
    1.35,
    0,
    5,
    0,
    0,
    0,
    1,
    0,
  ],
  'juno': [
    1.25,
    0,
    0,
    0,
    5,
    0,
    1.2,
    0,
    0,
    0,
    0,
    0,
    1.05,
    0,
    -10,
    0,
    0,
    0,
    1,
    0,
  ],
  'valencia': [
    1.12,
    0,
    0,
    0,
    10,
    0,
    1.08,
    0,
    0,
    10,
    0,
    0,
    0.95,
    0,
    5,
    0,
    0,
    0,
    1,
    0,
  ],
  'lark': [
    1.05,
    0,
    0,
    0,
    12,
    0,
    1.15,
    0,
    0,
    15,
    0,
    0,
    1.18,
    0,
    18,
    0,
    0,
    0,
    1,
    0,
  ],
  'sunset': [
    1.3,
    0,
    0,
    0,
    15,
    0,
    1.05,
    0,
    0,
    5,
    0,
    0,
    0.85,
    0,
    -15,
    0,
    0,
    0,
    1,
    0,
  ],
  'moon': [
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  'vintage': [
    0.393,
    0.769,
    0.189,
    0,
    0,
    0.349,
    0.686,
    0.168,
    0,
    0,
    0.272,
    0.534,
    0.131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
};

const Map<String, String> kFilterLabels = {
  'normal': 'নরমাল',
  'clarendon': 'ক্ল্যারেন্ডন',
  'juno': 'জুনো',
  'valencia': 'ভ্যালেন্সিয়া',
  'lark': 'লার্ক',
  'sunset': 'সূর্যাস্ত',
  'moon': 'মুন (B&W)',
  'vintage': 'ভিন্টেজ',
};

/// Shows a media URL. Only https links work on every device, so a device path
/// left by an upload that never finished is shown as a placeholder instead.
Widget buildSmartMediaImage(String path,
    {BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    VoidCallback? onLoaded}) {
  Widget placeholder(IconData icon) => Container(
        width: width,
        height: height,
        color: const Color(0xFF14241B),
        child: Center(child: Icon(icon, color: Colors.white24, size: 36)),
      );

  if (!isRemoteMediaUrl(path)) {
    return placeholder(Icons.cloud_off_rounded);
  }
  return CachedNetworkImage(
    imageUrl: path,
    fit: fit,
    width: width,
    height: height,
    imageBuilder: (context, provider) {
      onLoaded?.call();
      return Image(image: provider, fit: fit, width: width, height: height);
    },
    placeholder: (_, __) => Container(
      width: width,
      height: height,
      color: const Color(0xFF14241B),
      child: const Center(
        child: CircularProgressIndicator(
            color: AppColors.mintGreen, strokeWidth: 2),
      ),
    ),
    errorWidget: (_, __, ___) => Container(
      width: width,
      height: height,
      color: Colors.black26,
      child:
          const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
    ),
  );
}

/// Preview of a photo the user just picked. Uses the bytes, so it works on web
/// (blob URL) and on mobile (file path) alike. The bytes are read once per picture.
class PickedImagePreview extends StatefulWidget {
  final XFile file;
  final BoxFit fit;
  final double? width;
  final double? height;

  const PickedImagePreview({
    super.key,
    required this.file,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  State<PickedImagePreview> createState() => _PickedImagePreviewState();
}

class _PickedImagePreviewState extends State<PickedImagePreview> {
  late Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  void didUpdateWidget(covariant PickedImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _bytes = widget.file.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: widget.width,
            height: widget.height,
            color: const Color(0xFF14241B),
          );
        }
        return Image.memory(snap.data!,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            gaplessPlayback: true);
      },
    );
  }
}

class TourInstaFeedScreen extends StatefulWidget {
  final String tourId;

  const TourInstaFeedScreen({super.key, required this.tourId});

  @override
  State<TourInstaFeedScreen> createState() => _TourInstaFeedScreenState();
}

class _TourInstaFeedScreenState extends State<TourInstaFeedScreen> {
  static const int _pageSize = 60;

  final TourGroupRepository _repository = TourGroupRepository();
  final ImagePicker _picker = ImagePicker();

  String _selectedDayFilter = 'all';
  String _selectedMediaFilter = 'all'; // 'all', 'photos', 'reels'
  Set<String> _bookmarkedPostIds = {};
  Set<String> _seenStoryIds = {};
  TourGroup? _tourGroup;

  // Streams are created once here, not in build, so a rebuild does not
  // re-subscribe. Only "load more" replaces the posts stream.
  int _postLimit = _pageSize;
  late Stream<List<TourStoryItem>> _storiesStream;
  late Stream<List<TourPostItem>> _postsStream;

  @override
  void initState() {
    super.initState();
    _storiesStream = _repository.watchStories(widget.tourId);
    _postsStream = _repository.watchPosts(widget.tourId, limit: _postLimit);
    _loadGroup();
    _loadFeedPrefs();
  }

  Future<void> _loadGroup() async {
    final g = await _repository.getGroup(widget.tourId);
    if (mounted) setState(() => _tourGroup = g);
  }

  Future<void> _loadFeedPrefs() async {
    final prefs = await _repository.loadFeedPrefs(widget.tourId);
    if (!mounted) return;
    setState(() {
      _bookmarkedPostIds = Set<String>.from(prefs.bookmarks);
      _seenStoryIds = Set<String>.from(prefs.seenStories);
    });
  }

  void _saveFeedPrefs() {
    _repository.saveFeedPrefs(
      widget.tourId,
      FeedPrefs(bookmarks: _bookmarkedPostIds, seenStories: _seenStoryIds),
    );
  }

  void _toggleBookmark(String postId) {
    setState(() {
      if (!_bookmarkedPostIds.remove(postId)) _bookmarkedPostIds.add(postId);
    });
    _saveFeedPrefs();
  }

  void _markStorySeen(String storyId) {
    if (_seenStoryIds.add(storyId)) {
      setState(() {});
      _saveFeedPrefs();
    }
  }

  void _loadMorePosts() {
    setState(() {
      _postLimit += _pageSize;
      _postsStream = _repository.watchPosts(widget.tourId, limit: _postLimit);
    });
  }

  void _retryPosts() {
    setState(() {
      _postsStream = _repository.watchPosts(widget.tourId, limit: _postLimit);
    });
  }

  /// The tour's own days, from its start date. Empty until the tour has loaded.
  List<TourDayInfo> get _tourDays => _tourGroup?.daysList ?? const [];

  /// Label for a day id such as 'day2'. Falls back to the number, never the raw id.
  String _dayLabel(String dayId) {
    for (final day in _tourDays) {
      if (day.id == dayId) return day.label;
    }
    final number =
        int.tryParse(RegExp(r'\d+').firstMatch(dayId)?.group(0) ?? '');
    return number == null ? 'ডে' : 'ডে ${toBengaliNum(number)}';
  }

  List<Map<String, String>> get _dynamicTourDays {
    return [
      {'id': 'all', 'label': 'সব দিন (All Days)'},
      for (final day in _tourDays) {'id': day.id, 'label': day.label},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isLive = _tourGroup?.isLiveAt(DateTime.now()) ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0A120D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A120D),
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'Tour InstaFeed',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 19,
                letterSpacing: 0.5,
              ),
            ),
            if (isLive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_rounded,
                color: AppColors.mintGreen),
            tooltip: 'নতুন পোস্ট শেয়ার করুন',
            onPressed: () => _showCreatePostModal(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.mintGreen,
        foregroundColor: Colors.black,
        elevation: 6,
        tooltip: 'ক্যামেরা / ছবি যুক্ত করুন',
        onPressed: () => _showCreatePostModal(context),
        child: const Icon(Icons.camera_alt_rounded, size: 28),
      ),
      body: StreamBuilder<List<TourStoryItem>>(
        stream: _storiesStream,
        builder: (context, storiesSnap) {
          final now = DateTime.now();
          final stories = (storiesSnap.data ?? const <TourStoryItem>[])
              .where((s) => s.isActiveAt(now))
              .toList();

          return StreamBuilder<List<TourPostItem>>(
            stream: _postsStream,
            builder: (context, postsSnap) {
              final posts = postsSnap.data ?? const <TourPostItem>[];
              final filteredPosts = posts.where((p) {
                if (_selectedDayFilter != 'all' &&
                    p.tourDay != _selectedDayFilter) {
                  return false;
                }
                if (_selectedMediaFilter == 'photos' && p.isReel) {
                  return false;
                }
                if (_selectedMediaFilter == 'reels' && !p.isReel) {
                  return false;
                }
                return true;
              }).toList();
              final hasMore = posts.length >= _postLimit;

              Widget body;
              if (postsSnap.hasError && !postsSnap.hasData) {
                body = SliverFillRemaining(
                  child: _buildFeedError(context),
                );
              } else if (!postsSnap.hasData) {
                body = const SliverFillRemaining(
                  child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.mintGreen),
                  ),
                );
              } else if (filteredPosts.isEmpty) {
                body = SliverFillRemaining(
                  child: _buildEmptyFeedState(context),
                );
              } else {
                body = SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == filteredPosts.length) {
                        return Center(
                          child: TextButton(
                            onPressed: _loadMorePosts,
                            child: const Text('আরও পোস্ট দেখুন'),
                          ),
                        );
                      }
                      final post = filteredPosts[index];
                      return _TourPostCard(
                        key: ValueKey(post.id),
                        post: post,
                        tourId: widget.tourId,
                        repository: _repository,
                        defaultLocation: _tourGroup?.destination ?? '',
                        dayLabel: _dayLabel(post.tourDay),
                        isBookmarked: _bookmarkedPostIds.contains(post.id),
                        onBookmarkToggle: () => _toggleBookmark(post.id),
                        onOpenReel: (videoUrl) {
                          _openReelModal(context, videoUrl, post, posts);
                        },
                      );
                    },
                    childCount: filteredPosts.length + (hasMore ? 1 : 0),
                  ),
                );
              }

              return CustomScrollView(
                slivers: [
                  // 1. Stories (one bubble per person)
                  SliverToBoxAdapter(
                    child: _buildStoriesBar(context, stories),
                  ),

                  // 2. Media Type Filter Tabs (All, Photos, Reels)
                  SliverToBoxAdapter(
                    child: _buildMediaFilterTabs(),
                  ),

                  // 3. Day-wise Filter Chips
                  SliverToBoxAdapter(
                    child: _buildDayFilterChips(),
                  ),

                  // 4. Posts, empty state or error
                  body,
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFeedError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'পোস্ট লোড করা যায়নি। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.midGreen),
              onPressed: _retryPosts,
              child: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Stories Bar ---

  Widget _buildStoriesBar(BuildContext context, List<TourStoryItem> stories) {
    final groups = groupStoriesByAuthor(stories);
    return Container(
      height: 112,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white10, width: 0.8),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: groups.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            // "Your Story" add circle
            return GestureDetector(
              onTap: () => _showAddStoryModal(context),
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: const CircleAvatar(
                            backgroundColor: Color(0xFF1B4332),
                            child: Icon(Icons.person,
                                color: Colors.white70, size: 32),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppColors.mintGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add,
                                color: Colors.black, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'আপনার স্টোরি',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final group = groups[index - 1];
          final story = group.first;
          final allSeen = group.every((s) => _seenStoryIds.contains(s.id));
          return GestureDetector(
            onTap: () => _openStoryViewer(context, group),
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Gradient ring for unseen stories, grey once all are seen.
                      color: allSeen ? Colors.white24 : null,
                      gradient: allSeen
                          ? null
                          : const LinearGradient(
                              colors: [
                                Color(0xFFF59E0B),
                                Color(0xFFEC4899),
                                Color(0xFF8B5CF6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0A120D),
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.midGreen,
                        backgroundImage: story.authorPhoto != null
                            ? NetworkImage(story.authorPhoto!)
                            : null,
                        child: story.authorPhoto == null
                            ? Text(
                                story.authorName.isNotEmpty
                                    ? story.authorName[0].toUpperCase()
                                    : 'F',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 66,
                    child: Text(
                      story.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Media Type Filter Tabs (All, Photos, Reels) ---

  Widget _buildMediaFilterTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          _buildMediaTabButton(
            id: 'all',
            title: 'সব পোস্ট',
            icon: Icons.grid_view_rounded,
          ),
          _buildMediaTabButton(
            id: 'photos',
            title: 'ছবি (Photos)',
            icon: Icons.photo_library_rounded,
          ),
          _buildMediaTabButton(
            id: 'reels',
            title: '🎬 রিলস (Reels)',
            icon: Icons.movie_creation_rounded,
            isReelTab: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTabButton({
    required String id,
    required String title,
    required IconData icon,
    bool isReelTab = false,
  }) {
    final isSelected = _selectedMediaFilter == id;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedMediaFilter = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            gradient: isSelected
                ? (isReelTab
                    ? const LinearGradient(
                        colors: [Color(0xFFE11D48), Color(0xFF9333EA)],
                      )
                    : const LinearGradient(
                        colors: [AppColors.mintGreen, Color(0xFF10B981)],
                      ))
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? (isReelTab ? Colors.white : Colors.black)
                    : Colors.white60,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? (isReelTab ? Colors.white : Colors.black)
                        : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Day-wise Filter Chips ---

  Widget _buildDayFilterChips() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _dynamicTourDays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = _dynamicTourDays[index];
          final isSelected = _selectedDayFilter == day['id'];

          return ChoiceChip(
            label: Text(day['label']!),
            selected: isSelected,
            selectedColor: AppColors.mintGreen,
            backgroundColor: const Color(0xFF14241B),
            labelStyle: TextStyle(
              color: isSelected ? Colors.black : Colors.white70,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected ? AppColors.mintGreen : Colors.white12,
              ),
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedDayFilter = day['id']!);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyFeedState(BuildContext context) {
    final isReelsTab = _selectedMediaFilter == 'reels';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color:
                    (isReelsTab ? const Color(0xFFE11D48) : AppColors.mintGreen)
                        .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isReelsTab
                    ? Icons.movie_filter_outlined
                    : Icons.photo_library_outlined,
                size: 64,
                color:
                    isReelsTab ? const Color(0xFFE11D48) : AppColors.mintGreen,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isReelsTab ? 'কোনো রিলস পাওয়া যায়নি' : 'কোনো ছবি পাওয়া যায়নি',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isReelsTab
                  ? 'ট্যুরের আনন্দঘন ভিডিও মুহূর্তগুলো এখনই রিলস হিসেবে শেয়ার করুন (সর্বোচ্চ ৩ মিনিট)!'
                  : (_selectedDayFilter == 'all'
                      ? 'ট্যুরের সুন্দর মুহূর্তগুলো এখনই ইনস্টাফিডে শেয়ার করুন!'
                      : 'এই দিনের জন্য এখনও কোনো পোস্ট নেই। প্রথম ছবি শেয়ার করুন!'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  _showCreatePostModal(context, initialModeIsReel: isReelsTab),
              icon: Icon(isReelsTab
                  ? Icons.video_call_rounded
                  : Icons.add_a_photo_rounded),
              label: Text(isReelsTab ? 'রিলস আপলোড করুন' : 'ছবি আপলোড করুন'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isReelsTab ? const Color(0xFFE11D48) : AppColors.midGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Post Creation Studio Modal ---

  void _showCreatePostModal(BuildContext context,
      {bool initialModeIsReel = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreatePostStudioSheet(
        tourId: widget.tourId,
        group: _tourGroup,
        repository: _repository,
        picker: _picker,
        initialModeIsReel: initialModeIsReel,
      ),
    );
  }

  void _showAddStoryModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AddStorySheet(
        tourId: widget.tourId,
        repository: _repository,
        picker: _picker,
      ),
    );
  }

  void _openStoryViewer(BuildContext context, List<TourStoryItem> group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StoryViewerScreen(
          stories: group,
          repository: _repository,
          tourId: widget.tourId,
          onSeen: _markStorySeen,
        ),
      ),
    );
  }

  void _openReelModal(BuildContext context, String videoUrl, TourPostItem post,
      [List<TourPostItem>? allPosts]) {
    final reels = (allPosts ?? [post])
        .where((p) => p.isReel && p.videoUrl != null && p.videoUrl!.isNotEmpty)
        .toList();
    final initialIndex = reels.indexWhere((p) => p.id == post.id);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.black,
      builder: (ctx) => _ReelsPlayerModal(
        reels: reels.isNotEmpty ? reels : [post],
        initialIndex: initialIndex >= 0 ? initialIndex : 0,
        repository: _repository,
      ),
    );
  }
}

// ============================================================================
// Post Card Component (Double Tap Heart, Carousels, Filters, Comments)
// ============================================================================

class _TourPostCard extends StatefulWidget {
  final TourPostItem post;
  final String tourId;
  final TourGroupRepository repository;
  final String defaultLocation;
  final String dayLabel;
  final bool isBookmarked;
  final VoidCallback onBookmarkToggle;
  final void Function(String videoUrl) onOpenReel;

  const _TourPostCard({
    super.key,
    required this.post,
    required this.tourId,
    required this.repository,
    required this.defaultLocation,
    required this.dayLabel,
    required this.isBookmarked,
    required this.onBookmarkToggle,
    required this.onOpenReel,
  });

  @override
  State<_TourPostCard> createState() => _TourPostCardState();
}

class _TourPostCardState extends State<_TourPostCard>
    with SingleTickerProviderStateMixin {
  int _currentImageIndex = 0;
  bool _showHeartAnim = false;
  bool _isExpandedCaption = false;

  late AnimationController _heartAnimCtrl;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnimCtrl);
  }

  @override
  void dispose() {
    _heartAnimCtrl.dispose();
    super.dispose();
  }

  bool get _isMine => widget.post.authorEmail == widget.repository.currentEmail;

  /// The spot the post was tagged with, or the tour destination when none was given.
  String get _locationLabel => widget.post.location.isNotEmpty
      ? widget.post.location
      : widget.defaultLocation;

  void _handleDoubleTapLike() {
    final email = widget.repository.currentEmail;
    if (!widget.post.likes.contains(email)) {
      widget.repository
          .setPostLiked(widget.tourId, widget.post.id, liked: true)
          .catchError((Object _) {});
    }

    setState(() => _showHeartAnim = true);
    _heartAnimCtrl.forward(from: 0.0).then((_) {
      if (mounted) setState(() => _showHeartAnim = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final currentEmail = widget.repository.currentEmail;
    final isLiked = post.likes.contains(currentEmail);
    final matrix = kFilterMatrices[post.filterId] ?? kFilterMatrices['normal']!;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF101C14),
        border: Border(
          top: BorderSide(color: Colors.white10, width: 0.5),
          bottom: BorderSide(color: Colors.white10, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Post Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.midGreen,
                  backgroundImage: post.authorPhoto != null
                      ? NetworkImage(post.authorPhoto!)
                      : null,
                  child: post.authorPhoto == null
                      ? Text(
                          post.authorName.isNotEmpty
                              ? post.authorName[0].toUpperCase()
                              : 'F',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.mintGreen.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.dayLabel,
                              style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 11, color: AppColors.gold),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              _locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatTimeAgo(post.createdAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (_isMine)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Colors.white54),
                    color: const Color(0xFF1B4332),
                    onSelected: (value) {
                      if (value == 'edit') _editCaption();
                      if (value == 'delete') _deletePost();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'edit', child: Text('ক্যাপশন বদলান')),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text('পোস্ট মুছুন',
                              style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
              ],
            ),
          ),

          // 2. Media Viewport (Carousel or Video Reel)
          GestureDetector(
            onDoubleTap: _handleDoubleTapLike,
            onTap: post.isReel && post.videoUrl != null
                ? () => widget.onOpenReel(post.videoUrl!)
                : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: post.isReel ? (9 / 14) : 1.0,
                  child: post.isReel
                      ? (post.images.isNotEmpty
                          ? ColorFiltered(
                              colorFilter: ColorFilter.matrix(matrix),
                              child: buildSmartMediaImage(
                                post.images.first,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF1E1B4B),
                                    Color(0xFF0F172A),
                                    Color(0xFF000000),
                                  ],
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFE11D48),
                                          Color(0xFF9333EA),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFE11D48)
                                              .withValues(alpha: 0.4),
                                          blurRadius: 16,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 42,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    '🎬 ট্যুর রিলস দেখতে ট্যাপ করুন',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _locationLabel,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                      : (post.images.isEmpty
                          ? Container(
                              color: const Color(0xFF1B4332),
                              child: const Center(
                                child: Icon(Icons.image,
                                    size: 54, color: Colors.white30),
                              ),
                            )
                          : ColorFiltered(
                              colorFilter: ColorFilter.matrix(matrix),
                              child: PageView.builder(
                                itemCount: post.images.length,
                                onPageChanged: (i) {
                                  setState(() => _currentImageIndex = i);
                                },
                                itemBuilder: (context, idx) {
                                  return buildSmartMediaImage(
                                    post.images[idx],
                                    fit: BoxFit.cover,
                                  );
                                },
                              ),
                            )),
                ),

                // Floating Reel Pill Badge
                if (post.isReel)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE11D48), Color(0xFF9333EA)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.movie_creation_rounded,
                              color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'REEL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Reel Play Indicator Overlay on cover image
                if (post.isReel &&
                    post.videoUrl != null &&
                    post.images.isNotEmpty)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 40),
                      ),
                    ),
                  ),

                // Multi-image Page Dots
                if (post.images.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentImageIndex + 1}/${post.images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Bursting Heart Double Tap Animation
                if (_showHeartAnim)
                  ScaleTransition(
                    scale: _heartScale,
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                      size: 100,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 20),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // 3. Action Bar (Like, Comment, Share, Bookmark)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.redAccent : Colors.white,
                    size: 26,
                  ),
                  onPressed: () {
                    widget.repository.setPostLiked(widget.tourId, post.id,
                        liked: !post.isLikedBy(widget.repository.currentEmail));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white, size: 24),
                  onPressed: () => _showCommentsSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 23),
                  onPressed: _share,
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    widget.isBookmarked
                        ? Icons.bookmark
                        : Icons.bookmark_border_rounded,
                    color: widget.isBookmarked ? AppColors.gold : Colors.white,
                    size: 25,
                  ),
                  onPressed: widget.onBookmarkToggle,
                ),
              ],
            ),
          ),

          // 4. Like Count & Caption
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.likes.isNotEmpty)
                  Text(
                    '${toBengaliNum(post.likes.length)} টি লাইক',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 4),
                if (post.caption.isNotEmpty) ...[
                  RichText(
                    maxLines: _isExpandedCaption ? null : 2,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${post.authorName} ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: post.caption,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (post.caption.length > 70)
                    GestureDetector(
                      onTap: () {
                        setState(
                            () => _isExpandedCaption = !_isExpandedCaption);
                      },
                      child: Text(
                        _isExpandedCaption ? 'সংক্ষেপ করুন' : 'আরো দেখুন',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _showCommentsSheet(context),
                  child: Text(
                    post.commentCount > 0
                        ? 'সব ${toBengaliNum(post.commentCount)} টি মন্তব্য দেখুন'
                        : 'একটি মন্তব্য লিখুন...',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TourCommentsSheet(
        tourId: widget.tourId,
        postId: widget.post.id,
        repository: widget.repository,
      ),
    );
  }

  void _share() {
    final post = widget.post;
    final media = post.isReel ? post.videoUrl : null;
    final link = isRemoteMediaUrl(media) ? '\n\nভিডিও লিংক: $media' : '';
    final text = post.isReel
        ? '🎬 ${post.authorName}-এর ট্যুর রিলস:\n"${post.caption}"\n📍 স্থান: $_locationLabel$link'
        : '📸 ${post.authorName}-এর ট্যুর স্মৃতি:\n"${post.caption}"\n📍 স্থান: $_locationLabel';
    // ignore: deprecated_member_use
    Share.share(text,
        subject: post.isReel ? 'Bhromon Tour Reel' : 'Bhromon Tour Memory');
  }

  Future<void> _editCaption() async {
    final ctrl = TextEditingController(text: widget.post.caption);
    final newCaption = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title:
            const Text('ক্যাপশন বদলান', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('বাতিল')),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('সংরক্ষণ')),
        ],
      ),
    );
    ctrl.dispose();
    if (newCaption == null || newCaption == widget.post.caption) return;
    try {
      await widget.repository
          .updatePostCaption(widget.tourId, widget.post.id, newCaption);
    } catch (e) {
      if (mounted) _showError('ক্যাপশন বদলানো যায়নি: $e');
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title: const Text('পোস্টটি মুছবেন?',
            style: TextStyle(color: Colors.white)),
        content: const Text('ছবি বা ভিডিও ও মন্তব্যসহ এই পোস্ট মুছে যাবে।',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('মুছুন',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deletePost(widget.post);
    } catch (e) {
      if (mounted) _showError('পোস্ট মোছা যায়নি: $e');
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'এইমাত্র';
    if (diff.inMinutes < 60) return '${toBengaliNum(diff.inMinutes)} মি.';
    if (diff.inHours < 24) return '${toBengaliNum(diff.inHours)} ঘ.';
    return '${toBengaliNum(diff.inDays)} দিন';
  }
}

// ============================================================================
// Real-time Comments Sheet with Emoji Reactions
// ============================================================================

class _TourCommentsSheet extends StatefulWidget {
  final String tourId;
  final String postId;
  final TourGroupRepository repository;

  const _TourCommentsSheet({
    required this.tourId,
    required this.postId,
    required this.repository,
  });

  @override
  State<_TourCommentsSheet> createState() => _TourCommentsSheetState();
}

class _TourCommentsSheetState extends State<_TourCommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final List<String> _quickReactions = ['❤️', '👍', '😂', '🔥', '👏', '😍'];
  // Created once; a rebuild (such as the keyboard opening) must not re-subscribe.
  late final Stream<List<TourCommentItem>> _comments =
      widget.repository.watchComments(widget.tourId, widget.postId);
  bool _isSending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  /// Sends typed text, or a quick reaction. A reaction leaves the typed text
  /// alone, and typed text is cleared only once the comment is saved.
  Future<void> _submitComment({String? reaction}) async {
    final typed = _commentCtrl.text.trim();
    final isReaction = reaction != null;
    if (_isSending || (!isReaction && typed.isEmpty)) return;

    setState(() => _isSending = true);
    try {
      await widget.repository.addComment(
        tourId: widget.tourId,
        postId: widget.postId,
        text: isReaction ? '' : typed,
        reaction: reaction,
      );
      if (!isReaction) _commentCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('মন্তব্য পাঠানো যায়নি: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF14241B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'মন্তব্যসমূহ (Comments)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Divider(color: Colors.white10, height: 20),

          // Comments List
          Expanded(
            child: StreamBuilder<List<TourCommentItem>>(
              stream: _comments,
              builder: (context, snap) {
                final comments = snap.data ?? [];
                if (snap.hasError && comments.isEmpty) {
                  return const Center(
                    child: Text('মন্তব্য লোড করা যায়নি।',
                        style: TextStyle(color: Colors.white54)),
                  );
                }
                if (comments.isEmpty) {
                  return const Center(
                    child: Text(
                      'এখনও কোনো মন্তব্য নেই। প্রথম মন্তব্যটি করুন!',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: comments.length,
                  itemBuilder: (context, idx) {
                    final c = comments[idx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.midGreen,
                            backgroundImage: c.authorPhoto != null
                                ? NetworkImage(c.authorPhoto!)
                                : null,
                            child: c.authorPhoto == null
                                ? Text(
                                    c.authorName.isNotEmpty
                                        ? c.authorName[0].toUpperCase()
                                        : 'M',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      c.authorName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatTimeAgo(c.createdAt),
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // A reaction-only comment is shown once, as its emoji.
                                if (c.text.isNotEmpty)
                                  Text(
                                    c.text,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                              ],
                            ),
                          ),
                          if (c.reaction != null)
                            Text(c.reaction!,
                                style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Quick Reactions Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _quickReactions.map((emoji) {
                return GestureDetector(
                  onTap:
                      _isSending ? null : () => _submitComment(reaction: emoji),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                );
              }).toList(),
            ),
          ),

          // Input Bar
          Container(
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom +
                  12,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1A12),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'একটি মন্তব্য লিখুন...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: AppColors.mintGreen),
                  onPressed: _isSending ? null : () => _submitComment(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'এইমাত্র';
    if (diff.inMinutes < 60) return '${toBengaliNum(diff.inMinutes)} মি.';
    if (diff.inHours < 24) return '${toBengaliNum(diff.inHours)} ঘ.';
    return '${toBengaliNum(diff.inDays)} দিন';
  }
}

// ============================================================================
// Post Creation Studio (Filters, Carousel, Days, Landmarks)
// ============================================================================

class _CreatePostStudioSheet extends StatefulWidget {
  final String tourId;
  final TourGroup? group;
  final TourGroupRepository repository;
  final ImagePicker picker;
  final bool initialModeIsReel;

  const _CreatePostStudioSheet({
    required this.tourId,
    this.group,
    required this.repository,
    required this.picker,
    this.initialModeIsReel = false,
  });

  @override
  State<_CreatePostStudioSheet> createState() => _CreatePostStudioSheetState();
}

class _CreatePostStudioSheetState extends State<_CreatePostStudioSheet> {
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _customSpotCtrl = TextEditingController();
  final List<XFile> _photos = [];
  late String _selectedDay;
  late String _selectedLandmark;
  bool _isCustomSpot = false;
  String _selectedFilter = 'normal';
  bool _isPublishing = false;

  // Reels Mode State
  late bool _isReelMode;
  XFile? _selectedVideo;
  bool _isCompressingVideo = false;
  double _compressionProgress = 0.0;
  VideoPlayerController? _videoPlayerController;
  Duration _videoDuration = Duration.zero;
  bool _isVideoPlaying = false;
  String? _videoError;
  String _uploadStatusText = '';
  double _uploadProgress = 0;
  // Every upload started by the current publish, so a failed post can clean up.
  final List<TourMediaUpload> _startedUploads = [];
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _isReelMode = widget.initialModeIsReel;
    _selectedDay = (widget.group?.daysList.isNotEmpty ?? false)
        ? widget.group!.daysList.first.id
        : 'day1';
    final availableSpots = widget.group?.allSpots ?? kTourLandmarks;
    _selectedLandmark = availableSpots.isNotEmpty
        ? availableSpots.first
        : 'অন্যান্য স্থান (Others)';
  }

  @override
  void dispose() {
    TourVideoCompressor.cancel();
    _captionCtrl.dispose();
    _customSpotCtrl.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _pickImages() async {
    final remaining = kMaxPhotosPerPost - _photos.length;
    if (remaining <= 0) {
      _showError('একটি পোস্টে সর্বোচ্চ $kMaxPhotosPerPost টি ছবি দেওয়া যাবে।');
      return;
    }
    final picked = await widget.picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked.isEmpty || !mounted) return;
    final accepted = picked.take(remaining).toList();
    if (accepted.length < picked.length) {
      _showError(
          'সর্বোচ্চ $kMaxPhotosPerPost টি ছবি। বাকিগুলো বাদ দেওয়া হয়েছে।');
    }
    setState(() => _photos.addAll(accepted));
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await widget.picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: kMaxReelSeconds),
      );
      if (picked == null || !mounted) return;

      XFile fileToUse = picked;
      final originalSize = await picked.length();

      // If video exceeds limit (e.g. 100 MB), compress it on mobile platforms.
      if (originalSize > kMaxVideoBytes) {
        if (kIsWeb) {
          setState(() {
            _selectedVideo = picked;
            _videoError =
                'ভিডিও খুব বড় (${formatMegabytes(originalSize)})। সর্বোচ্চ ${formatMegabytes(kMaxVideoBytes)} হতে পারে।';
          });
          return;
        }

        final prevCtrl = _videoPlayerController;
        _videoPlayerController = null;
        await prevCtrl?.dispose();

        setState(() {
          _selectedVideo = picked;
          _isCompressingVideo = true;
          _compressionProgress = 0.0;
          _videoError = null;
        });

        try {
          fileToUse = await TourVideoCompressor.compressIfNeeded(
            sourceFile: picked,
            targetMaxBytes: kMaxVideoBytes,
            onProgress: (p) {
              if (mounted) setState(() => _compressionProgress = p);
            },
          );
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _isCompressingVideo = false;
            _videoError =
                'ভিডিও অপ্টিমাইজ করা যায়নি ($e)। অনুগ্রহ করে অন্য ভিডিও নির্বাচন করুন।';
          });
          return;
        }

        if (!mounted) return;
        setState(() => _isCompressingVideo = false);

        final newSize = await fileToUse.length();
        if (newSize > kMaxVideoBytes) {
          setState(() {
            _selectedVideo = fileToUse;
            _videoError =
                'ভিডিও কম্প্রেস করার পরও খুব বড় (${formatMegabytes(newSize)})। অনুগ্রহ করে ছোট ভিডিও বাছাই করুন।';
          });
          return;
        }
      }

      final controller = createLocalVideoController(fileToUse);
      await controller.initialize();
      await controller.setLooping(true);
      final duration = controller.value.duration;
      final tooLong = duration.inSeconds > kMaxReelSeconds;
      if (!tooLong) await controller.play();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      final previous = _videoPlayerController;
      setState(() {
        _selectedVideo = fileToUse;
        _videoPlayerController = controller;
        _videoDuration = duration;
        _isVideoPlaying = !tooLong;
        _videoError = tooLong
            ? 'রিলস সর্বোচ্চ ${kMaxReelSeconds ~/ 60} মিনিট হতে পারে। ছোট ভিডিও বাছাই করুন।'
            : null;
      });
      await previous?.dispose();
    } catch (e) {
      if (mounted) {
        setState(() => _isCompressingVideo = false);
        _showError('ভিডিও বাছাই করতে সমস্যা হয়েছে: $e');
      }
    }
  }

  void _toggleVideoPlayback() {
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return;
    }
    setState(() {
      if (_videoPlayerController!.value.isPlaying) {
        _videoPlayerController!.pause();
        _isVideoPlaying = false;
      } else {
        _videoPlayerController!.play();
        _isVideoPlaying = true;
      }
    });
  }

  String? get _spotToSave =>
      _isCustomSpot && _customSpotCtrl.text.trim().isNotEmpty
          ? _customSpotCtrl.text.trim()
          : _selectedLandmark;

  /// Uploads [files] three at a time and returns their URLs in order. Each
  /// upload is recorded so a failed post can remove what was uploaded.
  Future<List<String>> _uploadFiles(List<XFile> files,
      {required String folder, required bool video}) async {
    final email = widget.repository.currentEmail;
    final urls = List<String?>.filled(files.length, null);
    final progress = List<double>.filled(files.length, 0);
    var next = 0;

    void refreshProgress() {
      if (!mounted || files.isEmpty) return;
      setState(() =>
          _uploadProgress = progress.reduce((a, b) => a + b) / files.length);
    }

    Future<void> worker() async {
      while (next < files.length) {
        if (_cancelRequested) throw const TourUploadCancelled();
        final index = next++;
        final file = files[index];
        final upload = await TourMediaUploader.start(
          tourId: widget.tourId,
          folder: folder,
          file: file,
          contentType: video
              ? videoContentType(file.name) ?? 'video/mp4'
              : imageContentType(file.name) ?? 'image/jpeg',
          extension: storedExtension(file.name, video ? 'mp4' : 'jpg'),
          maxBytes: video ? kMaxVideoBytes : kMaxImageBytes,
          uploaderEmail: email,
        );
        _startedUploads.add(upload);
        final sub = upload.progress.listen((value) {
          progress[index] = value;
          refreshProgress();
        });
        try {
          urls[index] = await upload.finish();
          progress[index] = 1;
          refreshProgress();
        } finally {
          await sub.cancel();
        }
      }
    }

    final workers = files.length < 3 ? files.length : 3;
    await Future.wait(List.generate(workers, (_) => worker()));
    return urls.cast<String>();
  }

  /// Cancels anything still uploading and deletes what was uploaded, so a
  /// post that is not saved leaves no orphaned files in Storage.
  Future<void> _discardStartedUploads() async {
    for (final upload in _startedUploads) {
      try {
        await upload.cancel();
      } catch (_) {}
      await upload.discard();
    }
    _startedUploads.clear();
  }

  Future<void> _cancelPublish() async {
    _cancelRequested = true;
    for (final upload in _startedUploads) {
      try {
        await upload.cancel();
      } catch (_) {}
    }
  }

  Future<void> _publishPost() async {
    if (_isPublishing) return;
    final reel = _isReelMode;
    if (reel) {
      if (_selectedVideo == null || _videoError != null) return;
    } else {
      if (_photos.isEmpty) return;
      final badPhoto = _photos.any((f) =>
          storedExtension(f.name, '').isNotEmpty &&
          imageContentType(f.name) == null);
      if (badPhoto) {
        _showError('শুধু JPG, PNG, WEBP, GIF বা HEIC ছবি দেওয়া যাবে।');
        return;
      }
    }

    setState(() {
      _isPublishing = true;
      _cancelRequested = false;
      _uploadProgress = 0;
      _uploadStatusText = reel ? 'রিলস আপলোড হচ্ছে...' : 'ছবি আপলোড হচ্ছে...';
      _startedUploads.clear();
    });

    final spot = _spotToSave;
    final customSpot = _isCustomSpot ? _customSpotCtrl.text.trim() : '';
    try {
      final List<String> images;
      String? videoUrl;
      if (reel) {
        videoUrl = (await _uploadFiles([_selectedVideo!],
                folder: 'reels', video: true))
            .single;
        images = const [];
      } else {
        images =
            await _uploadFiles(List.of(_photos), folder: 'posts', video: false);
      }
      if (_cancelRequested) throw const TourUploadCancelled();

      if (mounted) setState(() => _uploadStatusText = 'পোস্ট সংরক্ষণ হচ্ছে...');
      await widget.repository.addPost(
        tourId: widget.tourId,
        caption: _captionCtrl.text.trim().isEmpty && reel
            ? 'ট্যুর রিলস 🎬'
            : _captionCtrl.text.trim(),
        images: images,
        videoUrl: videoUrl,
        isReel: reel,
        location: spot ?? '',
        tourDay: _selectedDay,
        filterId: _selectedFilter,
      );

      // Saved only after the post is, so a failed post does not leave a spot behind.
      if (customSpot.isNotEmpty) {
        try {
          await widget.repository.addCustomSpot(widget.tourId, customSpot);
        } catch (_) {}
      }
      _startedUploads.clear();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reel
                ? '🎬 রিলস সফলভাবে পাবলিশ হয়েছে!'
                : '📸 পোস্ট সফলভাবে শেয়ার হয়েছে!'),
            backgroundColor: AppColors.darkGreen,
          ),
        );
      }
    } on TourUploadCancelled {
      await _discardStartedUploads();
      _showError('আপলোড বাতিল হয়েছে।');
    } catch (e) {
      await _discardStartedUploads();
      final reason = e is TourUploadException || e is TourAccessException
          ? e.toString()
          : (e is FirebaseException
              ? (e.message ?? e.code)
              : 'সংযোগ বা সার্ভারের সমস্যা। আবার চেষ্টা করুন।');
      _showError(reel ? 'রিলস পাবলিশ হয়নি: $reason' : 'পোস্ট হয়নি: $reason');
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _uploadStatusText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dismissing the sheet mid-upload would leave a half-finished post behind.
    return PopScope(
      canPop: !_isPublishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isPublishing) {
          _showError('আপলোড শেষ হওয়া পর্যন্ত অপেক্ষা করুন, অথবা বাতিল করুন।');
        }
      },
      child: _buildSheet(context),
    );
  }

  /// Instagram-style colour presets. Used for photos and reels alike, so a
  /// reel gets the filter the user picked.
  Widget _buildFilterStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'কালার ফিল্টার সিলেক্ট করুন (Instagram Presets)',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: kFilterLabels.entries.map((entry) {
              final isSelected = _selectedFilter == entry.key;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  selectedColor: AppColors.mintGreen,
                  backgroundColor: Colors.black26,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _selectedFilter = entry.key);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSheet(BuildContext context) {
    final bool canSubmit = _isReelMode
        ? (_selectedVideo != null &&
            _videoError == null &&
            !_isPublishing &&
            !_isCompressingVideo)
        : (_photos.isNotEmpty && !_isPublishing);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF14241B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {
                    if (_isPublishing) {
                      _cancelPublish();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(_isPublishing ? 'আপলোড বাতিল' : 'বাতিল',
                      style: const TextStyle(color: Colors.white60)),
                ),
                Text(
                  _isReelMode
                      ? 'নতুন ট্যুর রিলস পাবলিশ'
                      : 'নতুন ইনস্টাফিড পোস্ট',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                ElevatedButton(
                  onPressed: canSubmit ? _publishPost : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isReelMode
                        ? const Color(0xFFE11D48)
                        : AppColors.mintGreen,
                    foregroundColor: _isReelMode ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isPublishing
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color:
                                    _isReelMode ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _uploadStatusText.isNotEmpty
                                  ? '$_uploadStatusText ${(_uploadProgress * 100).toInt()}%'
                                  : 'আপলোড...',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        )
                      : Text(
                          _isReelMode ? 'রিলস শেয়ার' : 'শেয়ার করুন',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          // Post Type Switcher Tabs (Photos vs Reel)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_isPublishing) return;
                      setState(() => _isReelMode = false);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_isReelMode ? AppColors.mintGreen : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library_rounded,
                              size: 16,
                              color:
                                  !_isReelMode ? Colors.black : Colors.white60),
                          const SizedBox(width: 6),
                          Text(
                            '📸 ছবি (Photos)',
                            style: TextStyle(
                              color:
                                  !_isReelMode ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_isPublishing) return;
                      setState(() => _isReelMode = true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: _isReelMode
                            ? const LinearGradient(
                                colors: [Color(0xFFE11D48), Color(0xFF9333EA)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.movie_creation_rounded,
                              size: 16,
                              color:
                                  _isReelMode ? Colors.white : Colors.white60),
                          const SizedBox(width: 6),
                          Text(
                            '🎬 রিলস (≤ ৩ মি.)',
                            style: TextStyle(
                              color:
                                  _isReelMode ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isReelMode) ...[
                  // ── Reels Mode Video Picker & Preview ──
                  if (_selectedVideo == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE11D48), Color(0xFF9333EA)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE11D48)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.movie_creation_rounded,
                                size: 36, color: Colors.white),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'ডিভাইস থেকে রিলস ভিডিও বাছুন',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'সর্বোচ্চ ৩ মিনিট অনুমোদিত (HD/MP4)\nট্যুরের আনন্দময় ভিডিও মুহূর্ত পরিবারের সাথে শেয়ার করুন',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _pickVideo(ImageSource.gallery),
                                icon: const Icon(Icons.video_library_rounded,
                                    size: 18),
                                label: const Text('গ্যালারি থেকে বাছুন'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE11D48),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 11),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () => _pickVideo(ImageSource.camera),
                                icon: const Icon(Icons.videocam_rounded,
                                    size: 18),
                                label: const Text('ক্যামেরা রেকর্ড'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white30),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 11),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _isCompressingVideo
                                    ? Container(
                                        height: 220,
                                        width: double.infinity,
                                        color: Colors.black87,
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const CircularProgressIndicator(
                                                    color: AppColors.mintGreen),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'ভিডিও অপ্টিমাইজ / কম্প্রেস করা হচ্ছে (${(_compressionProgress * 100).toInt()}%)...',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 8),
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child:
                                                      LinearProgressIndicator(
                                                    value: _compressionProgress >
                                                            0
                                                        ? _compressionProgress
                                                        : null,
                                                    backgroundColor:
                                                        Colors.white24,
                                                    valueColor:
                                                        const AlwaysStoppedAnimation<
                                                                Color>(
                                                            AppColors
                                                                .mintGreen),
                                                    minHeight: 6,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                const Text(
                                                  'বড় ভিডিও ইনস্টাফিডের উপযোগী (720p HD) করতে সাইজ কমানো হচ্ছে',
                                                  style: TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 11),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : AspectRatio(
                                        aspectRatio:
                                            (_videoPlayerController != null &&
                                                    _videoPlayerController!
                                                        .value.isInitialized)
                                                ? _videoPlayerController!
                                                    .value.aspectRatio
                                                : (9 / 14),
                                        child:
                                            (_videoPlayerController != null &&
                                                    _videoPlayerController!
                                                        .value.isInitialized)
                                                ? VideoPlayer(
                                                    _videoPlayerController!)
                                                : const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                            color: AppColors
                                                                .mintGreen),
                                                  ),
                                      ),
                              ),
                              if (!_isCompressingVideo)
                                GestureDetector(
                                  onTap: _toggleVideoPlayback,
                                  child: Container(
                                    color: Colors.transparent,
                                    height: 220,
                                    width: double.infinity,
                                    child: Center(
                                      child: AnimatedOpacity(
                                        opacity: !_isVideoPlaying ? 1.0 : 0.0,
                                        duration:
                                            const Duration(milliseconds: 200),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white30),
                                          ),
                                          child: const Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 36),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '⏱️ দৈর্ঘ্য: ${_videoDuration.inMinutes} মি. ${_videoDuration.inSeconds % 60} সে.',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_videoError != null)
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _videoError!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _pickVideo(ImageSource.gallery),
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16),
                                  label: const Text('অন্য ভিডিও বাছুন'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.pinkAccent,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  TourVideoCompressor.cancel();
                                  _videoPlayerController?.dispose();
                                  setState(() {
                                    _selectedVideo = null;
                                    _videoPlayerController = null;
                                    _videoDuration = Duration.zero;
                                    _videoError = null;
                                    _isCompressingVideo = false;
                                  });
                                },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.redAccent, size: 16),
                                label: const Text('মুছুন',
                                    style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  _buildFilterStrip(),
                ] else ...[
                  // ── Photos Mode Image Picker & Preview ──
                  if (_photos.isEmpty)
                    GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.mintGreen.withValues(alpha: 0.3),
                              style: BorderStyle.solid),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded,
                                size: 48, color: AppColors.mintGreen),
                            SizedBox(height: 10),
                            Text(
                              'গ্যালারি থেকে এক বা একাধিক ছবি নির্বাচন করুন',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 220,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photos.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              if (i == _photos.length) {
                                return GestureDetector(
                                  onTap: _pickImages,
                                  child: Container(
                                    width: 120,
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.add,
                                          color: AppColors.mintGreen, size: 36),
                                    ),
                                  ),
                                );
                              }

                              final matrix = kFilterMatrices[_selectedFilter] ??
                                  kFilterMatrices['normal']!;
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: ColorFiltered(
                                      colorFilter: ColorFilter.matrix(matrix),
                                      child: PickedImagePreview(
                                        file: _photos[i],
                                        width: 180,
                                        height: 220,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _photos.removeAt(i);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close,
                                            size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'নির্বাচিত ছবি: ${_photos.length} টি',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() => _photos.clear());
                              },
                              icon: const Icon(Icons.delete_outline,
                                  size: 16, color: Colors.redAccent),
                              label: const Text('সব মুছুন',
                                  style: TextStyle(
                                      color: Colors.redAccent, fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),

                  _buildFilterStrip(),
                ],

                const SizedBox(height: 20),

                // Tour Day Selector (Dynamic based on tour duration)
                const Text(
                  'ভ্রমণ দিন (Tour Day)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDay,
                  dropdownColor: const Color(0xFF14241B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: (widget.group?.daysList.isNotEmpty ?? false)
                      ? widget.group!.daysList.map((d) {
                          return DropdownMenuItem(
                            value: d.id,
                            child: Text(d.label),
                          );
                        }).toList()
                      : const [
                          DropdownMenuItem(
                              value: 'day1',
                              child: Text('ডে ১ (যাত্রা ও শুরু)')),
                          DropdownMenuItem(
                              value: 'day2',
                              child: Text('ডে ২ (দর্শনীয় স্পট)')),
                          DropdownMenuItem(
                              value: 'day3', child: Text('ডে ৩ (ঘোরাঘুরি)')),
                          DropdownMenuItem(
                              value: 'day4', child: Text('ডে ৪ (শপিং)')),
                          DropdownMenuItem(
                              value: 'day5',
                              child: Text('ডে ৫ (প্রত্যাবর্তন)')),
                        ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedDay = val);
                  },
                ),

                const SizedBox(height: 16),

                // Landmark / Spot Location Dropdown (Dynamic + Custom entry)
                const Text(
                  'লোকেশন বা স্পট ট্যাগ (Spot / Landmark)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue:
                      _isCustomSpot ? '__custom__' : _selectedLandmark,
                  dropdownColor: const Color(0xFF14241B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    ...(widget.group?.allSpots ?? kTourLandmarks).map((loc) {
                      return DropdownMenuItem(
                        value: loc,
                        child: Text(loc, overflow: TextOverflow.ellipsis),
                      );
                    }),
                    const DropdownMenuItem(
                      value: '__custom__',
                      child: Text(
                        '➕ নতুন স্থান লিখুন (Custom Spot)...',
                        style: TextStyle(
                          color: AppColors.mintGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == '__custom__') {
                      setState(() => _isCustomSpot = true);
                    } else if (val != null) {
                      setState(() {
                        _isCustomSpot = false;
                        _selectedLandmark = val;
                      });
                    }
                  },
                ),
                if (_isCustomSpot) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customSpotCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'নতুন স্থানের নাম লিখুন',
                      labelStyle: const TextStyle(
                          color: AppColors.mintGreen, fontSize: 12),
                      hintText: 'e.g. কংলাক পাহাড় চূড়া / স্পট ১',
                      hintStyle:
                          const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Caption
                Text(
                  _isReelMode
                      ? 'রিলস ক্যাপশন লিখুন (Reel Caption)'
                      : 'ক্যাপশন লিখুন (Caption)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _captionCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _isReelMode
                        ? 'রিলস নিয়ে চমৎকার অনুভূতি লিখুন... 🎬🏖️'
                        : 'সুন্দর মুহূর্তের অনুভূতি লিখে পরিবারের সাথে ভাগ করুন...',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
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

// ============================================================================
// Story Viewer Screen (Auto-advancing progress bar)
// ============================================================================

/// Add-a-story sheet. Uploads one photo with progress and cancel; the story is
/// saved only after the upload finishes, and a failed upload is removed again.
class _AddStorySheet extends StatefulWidget {
  final String tourId;
  final TourGroupRepository repository;
  final ImagePicker picker;

  const _AddStorySheet({
    required this.tourId,
    required this.repository,
    required this.picker,
  });

  @override
  State<_AddStorySheet> createState() => _AddStorySheetState();
}

class _AddStorySheetState extends State<_AddStorySheet> {
  final TextEditingController _captionCtrl = TextEditingController();
  XFile? _picked;
  TourMediaUpload? _upload;
  double _progress = 0;
  bool _isUploading = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  Future<void> _pick() async {
    final file = await widget.picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _picked = file);
  }

  Future<void> _share() async {
    final file = _picked;
    if (file == null || _isUploading) return;
    setState(() {
      _isUploading = true;
      _progress = 0;
    });
    TourMediaUpload? upload;
    try {
      upload = await TourMediaUploader.start(
        tourId: widget.tourId,
        folder: 'stories',
        file: file,
        contentType: imageContentType(file.name) ?? 'image/jpeg',
        extension: storedExtension(file.name, 'jpg'),
        maxBytes: kMaxImageBytes,
        uploaderEmail: widget.repository.currentEmail,
      );
      _upload = upload;
      final progressSub = upload.progress.listen((value) {
        if (mounted) setState(() => _progress = value);
      });
      final url = await upload.finish();
      await progressSub.cancel();
      final caption = _captionCtrl.text.trim();
      await widget.repository.addStory(
        tourId: widget.tourId,
        mediaUrl: url,
        caption: caption.isEmpty ? null : caption,
      );
      if (mounted) Navigator.pop(context);
    } on TourUploadCancelled {
      if (mounted) _showMessage('স্টোরি আপলোড বাতিল হয়েছে।');
    } catch (e) {
      await upload?.discard();
      if (mounted) {
        final reason = e is TourUploadException || e is TourAccessException
            ? e.toString()
            : (e is FirebaseException ? (e.message ?? e.code) : 'অজানা সমস্যা');
        _showMessage('স্টোরি যোগ করা যায়নি: $reason', color: Colors.redAccent);
      }
    } finally {
      _upload = null;
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _cancelUpload() async {
    await _upload?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final file = _picked;
    return PopScope(
      canPop: !_isUploading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isUploading) {
          _showMessage(
              'আপলোড শেষ হওয়া পর্যন্ত অপেক্ষা করুন, অথবা বাতিল করুন।');
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'নতুন ট্যুর স্টোরি যুক্ত করুন 📸',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'স্টোরিটি ২৪ ঘণ্টা পর্যন্ত সব সদস্য দেখতে পাবেন',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 18),
            if (file != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: PickedImagePreview(
                  file: file,
                  height: 200,
                  width: double.infinity,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _pick,
                icon: const Icon(Icons.photo_library),
                label: const Text('গ্যালারি থেকে ছবি বাছুন'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4332),
                  foregroundColor: AppColors.mintGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _captionCtrl,
              enabled: !_isUploading,
              maxLength: 140,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ছোট ক্যাপশন লিখুন (ঐচ্ছিক)...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_isUploading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _progress,
                color: AppColors.mintGreen,
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'আপলোড হচ্ছে ${(_progress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: _cancelUpload,
                    child: const Text('বাতিল করুন',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: file == null || _isUploading ? null : _share,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'স্টোরিতে শেয়ার করুন',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen story viewer for one person's stories, in posting order.
/// Timer runs only once the picture has shown; a long press pauses it.
class _StoryViewerScreen extends StatefulWidget {
  final List<TourStoryItem> stories;
  final TourGroupRepository repository;
  final String tourId;
  final void Function(String storyId) onSeen;

  const _StoryViewerScreen({
    required this.stories,
    required this.repository,
    required this.tourId,
    required this.onSeen,
  });

  @override
  State<_StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<_StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _storyDuration = Duration(seconds: 5);
  // If a picture never reports loaded (for example, it is broken), start anyway.
  static const Duration _loadFallback = Duration(seconds: 8);

  int _currentIndex = 0;
  bool _isLoaded = false;
  bool _isPaused = false;
  bool _isDeleting = false;
  late final AnimationController _progressCtrl;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
    _startLoadFallback();
    _markSeen();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  TourStoryItem get _story => widget.stories[_currentIndex];

  void _markSeen() {
    // Runs after the frame so the parent is not updated during a build.
    final id = _story.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSeen(id);
    });
  }

  void _startLoadFallback() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(_loadFallback, () {
      if (!_isLoaded) _onPictureReady();
    });
  }

  void _onPictureReady() {
    if (_isLoaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLoaded) return;
      _isLoaded = true;
      if (!_isPaused) _progressCtrl.forward(from: 0);
    });
  }

  void _goTo(int index) {
    setState(() {
      _currentIndex = index;
      _isLoaded = false;
    });
    _progressCtrl.reset();
    _startLoadFallback();
    _markSeen();
  }

  void _advance() {
    if (_currentIndex < widget.stories.length - 1) {
      _goTo(_currentIndex + 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      _goTo(_currentIndex - 1);
    } else {
      _progressCtrl.forward(from: 0);
    }
  }

  void _pause() {
    _isPaused = true;
    _progressCtrl.stop();
  }

  void _resume() {
    _isPaused = false;
    if (_isLoaded) _progressCtrl.forward();
  }

  Future<void> _deleteCurrent() async {
    final story = _story;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        title:
            const Text('স্টোরি মুছবেন?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('মুছুন',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeleting = true);
    try {
      await widget.repository.deleteStory(widget.tourId, story.id);
      if (!mounted) return;
      if (widget.stories.length <= 1) {
        Navigator.of(context).pop();
      } else {
        // The stream removes it from the list; step to the next remaining one.
        _advance();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('স্টোরি মোছা যায়নি: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final isMine = story.authorEmail == widget.repository.currentEmail;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previous();
          } else {
            _advance();
          }
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onLongPressCancel: _resume,
        child: Stack(
          children: [
            // Picture
            Center(
              child: buildSmartMediaImage(
                story.mediaUrl,
                fit: BoxFit.contain,
                onLoaded: _onPictureReady,
              ),
            ),

            // Progress bars and header. Taps here must not change story.
            SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(widget.stories.length, (idx) {
                          return Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: idx == _currentIndex
                                  ? AnimatedBuilder(
                                      animation: _progressCtrl,
                                      builder: (context, _) {
                                        return FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: _progressCtrl.value,
                                          child: Container(color: Colors.white),
                                        );
                                      },
                                    )
                                  : Container(
                                      color: idx < _currentIndex
                                          ? Colors.white
                                          : Colors.transparent,
                                    ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.midGreen,
                            backgroundImage: story.authorPhoto != null
                                ? NetworkImage(story.authorPhoto!)
                                : null,
                            child: story.authorPhoto == null
                                ? Text(
                                    story.authorName.isNotEmpty
                                        ? story.authorName[0].toUpperCase()
                                        : 'F',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              story.authorName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isMine)
                            IconButton(
                              tooltip: 'এই স্টোরি মুছুন',
                              icon: _isDeleting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.delete_outline,
                                      color: Colors.white),
                              onPressed: _isDeleting ? null : _deleteCurrent,
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Caption overlay
            if (story.caption != null && story.caption!.isNotEmpty)
              Positioned(
                bottom: 40,
                left: 20,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    story.caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Reels Player Modal (9:16 Vertical Video Player)
// ============================================================================

class _ReelsPlayerModal extends StatefulWidget {
  final List<TourPostItem> reels;
  final int initialIndex;
  final TourGroupRepository repository;

  const _ReelsPlayerModal({
    required this.reels,
    this.initialIndex = 0,
    required this.repository,
  });

  @override
  State<_ReelsPlayerModal> createState() => _ReelsPlayerModalState();
}

class _ReelsPlayerModalState extends State<_ReelsPlayerModal> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.reels.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.reels.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reels.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_outlined,
                  size: 64, color: Colors.white38),
              const SizedBox(height: 12),
              const Text('কোনো রিলস পাওয়া যায়নি',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ফিরে যান'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.reels.length,
        onPageChanged: (idx) {
          setState(() => _currentIndex = idx);
        },
        itemBuilder: (context, index) {
          final post = widget.reels[index];
          final isActive = index == _currentIndex;
          return _ReelVideoItem(
            key: ValueKey(post.id),
            post: post,
            isActive: isActive,
            isMuted: _isMuted,
            onToggleMute: () {
              setState(() => _isMuted = !_isMuted);
            },
            onClose: () => Navigator.pop(context),
            repository: widget.repository,
          );
        },
      ),
    );
  }
}

class _ReelVideoItem extends StatefulWidget {
  final TourPostItem post;
  final bool isActive;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onClose;
  final TourGroupRepository repository;

  const _ReelVideoItem({
    super.key,
    required this.post,
    required this.isActive,
    required this.isMuted,
    required this.onToggleMute,
    required this.onClose,
    required this.repository,
  });

  @override
  State<_ReelVideoItem> createState() => _ReelVideoItemState();
}

class _ReelVideoItemState extends State<_ReelVideoItem>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String _errorText = 'ভিডিও লোড করা যায়নি';
  bool _showHeartAnim = false;
  late AnimationController _animCtrl;
  late Animation<double> _heartScale;
  bool _isCaptionExpanded = false;
  // Likes and comment counts stay current while the reel is open.
  late final Stream<TourPostItem?> _postStream =
      widget.repository.watchPost(widget.post.tourId, widget.post.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _heartScale = Tween<double>(begin: 0.2, end: 1.3).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut),
    );
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = widget.post.videoUrl;
    if (!isRemoteMediaUrl(url)) {
      setState(() {
        _hasError = true;
        _errorText = 'এই রিলসের ভিডিও এখনও আপলোড হয়নি';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url!));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _hasError = false;
      });
      if (widget.isActive) {
        await controller.play();
        _isPlaying = true;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = 'ভিডিও লোড করা যায়নি';
        });
      }
    }
  }

  Future<void> _retry() async {
    final old = _controller;
    setState(() {
      _controller = null;
      _isInitialized = false;
      _hasError = false;
    });
    await old?.dispose();
    await _initVideo();
  }

  @override
  void didUpdateWidget(covariant _ReelVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller != null && _isInitialized) {
      if (widget.isActive && !oldWidget.isActive) {
        controller.play();
        _isPlaying = true;
      } else if (!widget.isActive && oldWidget.isActive) {
        controller.pause();
        _isPlaying = false;
      }
      if (widget.isMuted != oldWidget.isMuted) {
        controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      }
    }
  }

  /// Pause when the app goes to the background, resume only if this reel is showing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      if (widget.isActive && _isPlaying) controller.play();
    } else {
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _handleDoubleTapLike(TourPostItem post) {
    // Double-tap only likes; it never unlikes.
    if (!post.isLikedBy(widget.repository.currentEmail)) {
      widget.repository
          .setPostLiked(post.tourId, post.id, liked: true)
          .catchError((Object _) {});
    }
    setState(() => _showHeartAnim = true);
    _animCtrl.forward(from: 0.0).then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _showHeartAnim = false);
        });
      }
    });
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _isPlaying = false;
      } else {
        controller.play();
        _isPlaying = true;
      }
    });
  }

  void _share(TourPostItem post) {
    final link = isRemoteMediaUrl(post.videoUrl)
        ? '\n\nভিডিও লিংক: ${post.videoUrl}'
        : '';
    final place =
        post.location.isNotEmpty ? '\n📍 স্থান: ${post.location}' : '';
    // ignore: deprecated_member_use
    Share.share(
      '🎬 ${post.authorName}-এর ট্যুর রিলস:\n"${post.caption}"$place$link',
      subject: 'Bhromon Tour Reel',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TourPostItem?>(
      stream: _postStream,
      initialData: widget.post,
      builder: (context, snap) {
        final post = snap.data ?? widget.post;
        return _buildReel(context, post);
      },
    );
  }

  Widget _buildReel(BuildContext context, TourPostItem post) {
    final isLiked = post.isLikedBy(widget.repository.currentEmail);
    final matrix = kFilterMatrices[post.filterId] ?? kFilterMatrices['normal']!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video or placeholder
          GestureDetector(
            onTap: _togglePlayPause,
            onDoubleTap: () => _handleDoubleTapLike(post),
            child: Center(
              child: _isInitialized && _controller != null
                  ? ColorFiltered(
                      colorFilter: ColorFilter.matrix(matrix),
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  : (_hasError
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.white54, size: 48),
                            const SizedBox(height: 10),
                            Text(_errorText,
                                style: const TextStyle(color: Colors.white70)),
                            if (isRemoteMediaUrl(post.videoUrl)) ...[
                              const SizedBox(height: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.midGreen),
                                onPressed: _retry,
                                child: const Text('আবার চেষ্টা করুন'),
                              ),
                            ],
                          ],
                        )
                      : const CircularProgressIndicator(
                          color: AppColors.mintGreen, strokeWidth: 2)),
            ),
          ),

          // 2. Play / pause icon
          if (_isInitialized && !_isPlaying)
            Center(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 48),
                ),
              ),
            ),

          // 3. Heart burst
          if (_showHeartAnim)
            Center(
              child: ScaleTransition(
                scale: _heartScale,
                child: const Icon(
                  Icons.favorite,
                  color: Colors.redAccent,
                  size: 110,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 20),
                  ],
                ),
              ),
            ),

          // 4. Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 22),
                  onPressed: widget.onClose,
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE11D48), Color(0xFF9333EA)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.movie_creation_rounded,
                          color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text(
                        'REELS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    widget.isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: widget.onToggleMute,
                ),
              ],
            ),
          ),

          // 5. Right action bar
          Positioned(
            right: 14,
            bottom: 80,
            child: Column(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border_rounded,
                    color: isLiked ? Colors.redAccent : Colors.white,
                    size: 32,
                  ),
                  onPressed: () => widget.repository
                      .setPostLiked(post.tourId, post.id, liked: !isLiked),
                ),
                Text(
                  toBengaliNum(post.likes.length),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 16),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => _TourCommentsSheet(
                        tourId: post.tourId,
                        postId: post.id,
                        repository: widget.repository,
                      ),
                    );
                  },
                ),
                Text(
                  toBengaliNum(post.commentCount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 16),
                IconButton(
                  icon: const Icon(Icons.share_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => _share(post),
                ),
                const Text(
                  'শেয়ার',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),

          // 6. Author, location and caption
          Positioned(
            left: 16,
            right: 80,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.midGreen,
                      backgroundImage: post.authorPhoto != null
                          ? NetworkImage(post.authorPhoto!)
                          : null,
                      child: post.authorPhoto == null
                          ? Text(
                              post.authorName.isNotEmpty
                                  ? post.authorName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        post.authorName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
                if (post.location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: AppColors.mintGreen, size: 13),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            post.location,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (post.caption.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() => _isCaptionExpanded = !_isCaptionExpanded);
                    },
                    child: Text(
                      post.caption,
                      maxLines: _isCaptionExpanded ? 8 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 7. Progress scrubber
          if (_isInitialized && _controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFE11D48),
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
