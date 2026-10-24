import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/tour_post_models.dart';
import '../../data/tour_group_repository.dart';
import '../../../../core/theme/colors.dart';

// Bengali numeral helper
String toBengaliNum(int number) {
  const digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return number.toString().split('').map((c) {
    final idx = int.tryParse(c);
    return idx != null ? digits[idx] : c;
  }).join('');
}

// Preset locations
const List<String> kTourLandmarks = [
  'লাবণী ও সুগন্ধা বিচ, কক্সবাজার',
  'হোটেল সি মুন (Hotel Sea Moon)',
  'এভারগ্রীন এসি বাস (রংপুর ➔ কক্সবাজার)',
  'বিআরটিসি ছাদখোলা দোতলা বাস',
  'হিমছড়ি পাহাড় ও ঝর্ণা',
  'ইনানী পাথুরে প্রবাল সৈকত',
  'পটুয়ারটেক বিচ পয়েন্ট',
  'সাবরাং জিরো পয়েন্ট (টেকনাফ)',
  'মহেশখালী আদিনাথ মন্দির',
  'নুনিয়াছড়া ঘাট ও বাঁকখালী নদী',
  'বার্মিজ মার্কেট ফ্যামিলি শপিং',
  'রেডিয়েন্ট ফিশ ওয়ার্ল্ড একুরিয়াম',
];

// Instagram 8 Color Filter Matrices
const Map<String, List<double>> kFilterMatrices = {
  'normal': [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ],
  'clarendon': [
    1.2, 0, 0, 0, -10,
    0, 1.25, 0, 0, -10,
    0, 0, 1.35, 0, 5,
    0, 0, 0, 1, 0,
  ],
  'juno': [
    1.25, 0, 0, 0, 5,
    0, 1.2, 0, 0, 0,
    0, 0, 1.05, 0, -10,
    0, 0, 0, 1, 0,
  ],
  'valencia': [
    1.12, 0, 0, 0, 10,
    0, 1.08, 0, 0, 10,
    0, 0, 0.95, 0, 5,
    0, 0, 0, 1, 0,
  ],
  'lark': [
    1.05, 0, 0, 0, 12,
    0, 1.15, 0, 0, 15,
    0, 0, 1.18, 0, 18,
    0, 0, 0, 1, 0,
  ],
  'sunset': [
    1.3, 0, 0, 0, 15,
    0, 1.05, 0, 0, 5,
    0, 0, 0.85, 0, -15,
    0, 0, 0, 1, 0,
  ],
  'moon': [
    0.33, 0.59, 0.11, 0, 0,
    0.33, 0.59, 0.11, 0, 0,
    0.33, 0.59, 0.11, 0, 0,
    0,    0,    0,    1, 0,
  ],
  'vintage': [
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0,     0,     0,     1, 0,
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


Widget buildSmartMediaImage(String path, {BoxFit fit = BoxFit.cover, double? width, double? height}) {
  if (path.isEmpty) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF14241B),
      child: const Center(child: Icon(Icons.photo, color: Colors.white24, size: 36)),
    );
  }
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return CachedNetworkImage(
      imageUrl: path,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, __) => Container(
        width: width,
        height: height,
        color: const Color(0xFF14241B),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.mintGreen, strokeWidth: 2),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.black26,
        child: const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
      ),
    );
  } else {
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.black26,
          child: const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF14241B),
      child: const Center(child: Icon(Icons.photo, color: Colors.white24, size: 36)),
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
  final TourGroupRepository _repository = TourGroupRepository();
  final ImagePicker _picker = ImagePicker();

  String _selectedDayFilter = 'all';
  final Set<String> _bookmarkedPostIds = {};

  final List<Map<String, String>> _tourDays = [
    {'id': 'all', 'label': 'সব দিন'},
    {'id': 'day1', 'label': 'ডে ১ (যাত্রা ও শুরু)'},
    {'id': 'day2', 'label': 'ডে ২ (লাবণী ও ইনানী)'},
    {'id': 'day3', 'label': 'ডে ৩ (হিমছড়ি সূর্যাস্ত)'},
    {'id': 'day4', 'label': 'ডে ৪ (মার্কেট ও দর্শনীয়)'},
    {'id': 'day5', 'label': 'ডে ৫ (প্রত্যাবর্তন)'},
  ];

  @override
  Widget build(BuildContext context) {
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
        stream: _repository.watchStories(widget.tourId),
        builder: (context, storiesSnap) {
          final stories = storiesSnap.data ?? [];

          return StreamBuilder<List<TourPostItem>>(
            stream: _repository.watchPosts(widget.tourId),
            builder: (context, postsSnap) {
              final posts = postsSnap.data ?? [];
              final filteredPosts = _selectedDayFilter == 'all'
                  ? posts
                  : posts.where((p) => p.tourDay == _selectedDayFilter).toList();

              return CustomScrollView(
                slivers: [
                  // 1. Stories Bar (Top Avatars with Gradient Rings)
                  SliverToBoxAdapter(
                    child: _buildStoriesBar(context, stories),
                  ),

                  // 2. Day-wise Filter Chips
                  SliverToBoxAdapter(
                    child: _buildDayFilterChips(),
                  ),

                  // 3. Post Feed or Empty State
                  if (postsSnap.connectionState == ConnectionState.waiting)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.mintGreen),
                      ),
                    )
                  else if (filteredPosts.isEmpty)
                    SliverFillRemaining(
                      child: _buildEmptyFeedState(context),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final post = filteredPosts[index];
                          return _TourPostCard(
                            post: post,
                            tourId: widget.tourId,
                            repository: _repository,
                            isBookmarked:
                                _bookmarkedPostIds.contains(post.id),
                            onBookmarkToggle: () {
                              setState(() {
                                if (_bookmarkedPostIds.contains(post.id)) {
                                  _bookmarkedPostIds.remove(post.id);
                                } else {
                                  _bookmarkedPostIds.add(post.id);
                                }
                              });
                            },
                            onOpenReel: (videoUrl) {
                              _openReelModal(context, videoUrl, post);
                            },
                          );
                        },
                        childCount: filteredPosts.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // --- Stories Bar ---

  Widget _buildStoriesBar(BuildContext context, List<TourStoryItem> stories) {
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
        itemCount: stories.length + 1,
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
                            border: Border.all(
                                color: Colors.white24, width: 2),
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

          final story = stories[index - 1];
          return GestureDetector(
            onTap: () => _openStoryViewer(context, stories, index - 1),
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
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

  // --- Day-wise Filter Chips ---

  Widget _buildDayFilterChips() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _tourDays.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = _tourDays[index];
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
                color: isSelected
                    ? AppColors.mintGreen
                    : Colors.white12,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 64, color: AppColors.mintGreen),
            ),
            const SizedBox(height: 20),
            const Text(
              'কোনো ছবি পাওয়া যায়নি',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedDayFilter == 'all'
                  ? 'ট্যুরের সুন্দর মুহূর্তগুলো এখনই ইনস্টাফিডে শেয়ার করুন!'
                  : 'এই দিনের জন্য এখনও কোনো পোস্ট নেই। প্রথম ছবি শেয়ার করুন!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showCreatePostModal(context),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('ছবি আপলোড করুন'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.midGreen,
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

  void _showCreatePostModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CreatePostStudioSheet(
        tourId: widget.tourId,
        repository: _repository,
        picker: _picker,
      ),
    );
  }

  void _showAddStoryModal(BuildContext context) {
    final captionCtrl = TextEditingController();
    String? selectedImageUrl;
    bool isUploading = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      backgroundColor: const Color(0xFF14241B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24,
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
                  if (selectedImageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: buildSmartMediaImage(
                        selectedImageUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () async {
                        final picked = await _picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedImageUrl = picked.path;
                          });
                        }
                      },
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
                    controller: captionCtrl,
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
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: selectedImageUrl == null || isUploading
                        ? null
                        : () async {
                            setModalState(() => isUploading = true);
                            String finalUrl = selectedImageUrl!;
                            try {
                              final file = File(selectedImageUrl!);
                              if (file.existsSync()) {
                                final sName = '${const Uuid().v4()}.jpg';
                                final sRef = FirebaseStorage.instance
                                    .ref('tours/${widget.tourId}/stories/$sName');
                                final sTask = await sRef.putFile(file);
                                finalUrl = await sTask.ref.getDownloadURL();
                              }
                            } catch (_) {}

                            await _repository.addStory(
                              tourId: widget.tourId,
                              mediaUrl: finalUrl,
                              caption: captionCtrl.text.trim().isEmpty
                                  ? null
                                  : captionCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'স্টোরিতে শেয়ার করুন',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openStoryViewer(
      BuildContext context, List<TourStoryItem> stories, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StoryViewerScreen(
          stories: stories,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _openReelModal(
      BuildContext context, String videoUrl, TourPostItem post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => _ReelsPlayerModal(
        videoUrl: videoUrl,
        post: post,
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
  final bool isBookmarked;
  final VoidCallback onBookmarkToggle;
  final void Function(String videoUrl) onOpenReel;

  const _TourPostCard({
    required this.post,
    required this.tourId,
    required this.repository,
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

  void _handleDoubleTapLike() {
    final email = widget.repository.currentEmail;
    if (email == null) return;

    if (!widget.post.likes.contains(email)) {
      widget.repository.toggleLikePost(widget.tourId, widget.post.id);
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
    final isLiked = currentEmail != null && post.likes.contains(currentEmail);
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
                              color: AppColors.mintGreen.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              post.tourDay.toUpperCase(),
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
                              post.location,
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
              ],
            ),
          ),

          // 2. Media Viewport (Carousel or Video Reel)
          GestureDetector(
            onDoubleTap: _handleDoubleTapLike,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: post.isReel ? (9 / 14) : 1.0,
                  child: post.images.isEmpty && post.videoUrl == null
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
                        ),
                ),

                // Reel Play Indicator Overlay
                if (post.isReel && post.videoUrl != null)
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onOpenReel(post.videoUrl!),
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
                    widget.repository
                        .toggleLikePost(widget.tourId, post.id);
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
                  onPressed: () {
                    // ignore: deprecated_member_use
                    Share.share(
                      '${post.authorName} shared a tour moment from ${post.location}:\n"${post.caption}"',
                      subject: 'Bhromon Tour Memory',
                    );
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    widget.isBookmarked
                        ? Icons.bookmark
                        : Icons.bookmark_border_rounded,
                    color: widget.isBookmarked
                        ? AppColors.gold
                        : Colors.white,
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
                        setState(() => _isExpandedCaption = !_isExpandedCaption);
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

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _submitComment({String? reaction}) async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty && reaction == null) return;

    await widget.repository.addComment(
      tourId: widget.tourId,
      postId: widget.postId,
      text: text.isEmpty ? (reaction ?? '') : text,
      reaction: reaction,
    );
    _commentCtrl.clear();
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
              stream: widget.repository
                  .watchComments(widget.tourId, widget.postId),
              builder: (context, snap) {
                final comments = snap.data ?? [];
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
                  onTap: () => _submitComment(reaction: emoji),
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
              bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 12,
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
                  onPressed: () => _submitComment(),
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
  final TourGroupRepository repository;
  final ImagePicker picker;

  const _CreatePostStudioSheet({
    required this.tourId,
    required this.repository,
    required this.picker,
  });

  @override
  State<_CreatePostStudioSheet> createState() => _CreatePostStudioSheetState();
}

class _CreatePostStudioSheetState extends State<_CreatePostStudioSheet> {
  final TextEditingController _captionCtrl = TextEditingController();
  final List<String> _selectedImagePaths = [];
  String _selectedDay = 'day1';
  String _selectedLandmark = kTourLandmarks.first;
  String _selectedFilter = 'normal';
  bool _isPublishing = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await widget.picker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) {
      setState(() {
        _selectedImagePaths.addAll(picked.map((x) => x.path));
      });
    }
  }

  Future<void> _publishPost() async {
    if (_selectedImagePaths.isEmpty) return;

    setState(() => _isPublishing = true);
    try {
      final List<String> uploadedUrls = [];
      for (final localPath in _selectedImagePaths) {
        if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
          uploadedUrls.add(localPath);
        } else {
          try {
            final file = File(localPath);
            if (file.existsSync()) {
              final fileName = '${const Uuid().v4()}.jpg';
              final ref = FirebaseStorage.instance
                  .ref('tours/${widget.tourId}/posts/$fileName');
              final task = await ref.putFile(file);
              final dUrl = await task.ref.getDownloadURL();
              uploadedUrls.add(dUrl);
            } else {
              uploadedUrls.add(localPath);
            }
          } catch (_) {
            uploadedUrls.add(localPath);
          }
        }
      }

      await widget.repository.addPost(
        tourId: widget.tourId,
        caption: _captionCtrl.text.trim(),
        images: uploadedUrls,
        location: _selectedLandmark,
        tourDay: _selectedDay,
        filterId: _selectedFilter,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('পোস্ট করতে সমস্যা হয়েছে: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('বাতিল',
                      style: TextStyle(color: Colors.white60)),
                ),
                const Text(
                  'নতুন ইনস্টাফিড পোস্ট',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                ElevatedButton(
                  onPressed: _selectedImagePaths.isEmpty || _isPublishing
                      ? null
                      : _publishPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isPublishing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('শেয়ার করুন',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Media Picker & Preview Area
                if (_selectedImagePaths.isEmpty)
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
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
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
                          itemCount: _selectedImagePaths.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            if (i == _selectedImagePaths.length) {
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
                                    child: buildSmartMediaImage(
                                      _selectedImagePaths[i],
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
                                        _selectedImagePaths.removeAt(i);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close,
                                          color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 20),

                // 8 Instagram Color Filter Selector Strip
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
                  height: 48,
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
                          backgroundColor: const Color(0xFF0D1A12),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _selectedFilter = entry.key);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 20),

                // Tour Day Selector
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
                  items: const [
                    DropdownMenuItem(value: 'day1', child: Text('ডে ১: রংপুর ➔ কক্সবাজার যাত্রা ও পৌঁছানো')),
                    DropdownMenuItem(value: 'day2', child: Text('ডে ২: সুগন্ধা ও লাবণী বিচ গোসল ও ইনানী')),
                    DropdownMenuItem(value: 'day3', child: Text('ডে ৩: হিমছড়ি পাহাড়, ঝর্ণা ও সূর্যাস্ত')),
                    DropdownMenuItem(value: 'day4', child: Text('ডে ৪: মহেশখালী ও বার্মিজ মার্কেট শপিং')),
                    DropdownMenuItem(value: 'day5', child: Text('ডে ৫: বিদায় ও রংপুর প্রত্যাবর্তন')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedDay = val);
                  },
                ),

                const SizedBox(height: 16),

                // Landmark Location Dropdown
                const Text(
                  'লোকেশন ট্যাগ (Landmark)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLandmark,
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
                  items: kTourLandmarks.map((loc) {
                    return DropdownMenuItem(value: loc, child: Text(loc));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLandmark = val);
                  },
                ),

                const SizedBox(height: 16),

                // Caption
                const Text(
                  'ক্যাপশন লিখুন (Caption)',
                  style: TextStyle(
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
                    hintText: 'সুন্দর মুহূর্তের অনুভূতি লিখে পরিবারের সাথে ভাগ করুন...',
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

class _StoryViewerScreen extends StatefulWidget {
  final List<TourStoryItem> stories;
  final int initialIndex;

  const _StoryViewerScreen({
    required this.stories,
    required this.initialIndex,
  });

  @override
  State<_StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<_StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advanceStory();
        }
      });
    _progressCtrl.forward();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  void _advanceStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() => _currentIndex++);
      _progressCtrl.forward(from: 0.0);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _progressCtrl.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previousStory();
          } else {
            _advanceStory();
          }
        },
        child: Stack(
          children: [
            // Media
            Center(
              child: buildSmartMediaImage(
                story.mediaUrl,
                fit: BoxFit.contain,
              ),
            ),

            // Top Status Bars
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                                        child: Container(
                                          color: Colors.white,
                                        ),
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
                        Text(
                          story.authorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
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
  final String videoUrl;
  final TourPostItem post;
  final TourGroupRepository repository;

  const _ReelsPlayerModal({
    required this.videoUrl,
    required this.post,
    required this.repository,
  });

  @override
  State<_ReelsPlayerModal> createState() => _ReelsPlayerModalState();
}

class _ReelsPlayerModalState extends State<_ReelsPlayerModal> {
  late VideoPlayerController _videoCtrl;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoUrl.startsWith('http://') || widget.videoUrl.startsWith('https://')) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    } else {
      _videoCtrl = VideoPlayerController.file(File(widget.videoUrl));
    }
    _videoCtrl.initialize().then((_) {
      if (mounted) {
        setState(() => _isInitialized = true);
        _videoCtrl.setLooping(true);
        _videoCtrl.play();
      }
    });
  }

  @override
  void dispose() {
    _videoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Player
          Center(
            child: _isInitialized
                ? AspectRatio(
                    aspectRatio: _videoCtrl.value.aspectRatio,
                    child: VideoPlayer(_videoCtrl),
                  )
                : const CircularProgressIndicator(color: AppColors.mintGreen),
          ),

          // Top Close Button
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Right Action Column (Like, Comment, Share)
          Positioned(
            right: 16,
            bottom: 60,
            child: Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.favorite,
                      color: Colors.white, size: 30),
                  onPressed: () {
                    widget.repository
                        .toggleLikePost(widget.post.tourId, widget.post.id);
                  },
                ),
                Text(
                  toBengaliNum(widget.post.likes.length),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 14),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => _TourCommentsSheet(
                        tourId: widget.post.tourId,
                        postId: widget.post.id,
                        repository: widget.repository,
                      ),
                    );
                  },
                ),
                Text(
                  toBengaliNum(widget.post.commentCount),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 14),
                IconButton(
                  icon: const Icon(Icons.share_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () {
                    // ignore: deprecated_member_use
                    Share.share(
                      'Check out this tour reel from ${widget.post.location}!',
                      subject: 'Bhromon Tour Reel',
                    );
                  },
                ),
              ],
            ),
          ),

          // Bottom Details
          Positioned(
            bottom: 30,
            left: 16,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.authorName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.post.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
