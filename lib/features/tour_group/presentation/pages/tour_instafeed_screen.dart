import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../domain/models/safety_alert_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/tour_post_models.dart';
import '../../domain/services/trip_ledger_engine.dart';
import 'tide_beach_guide_screen.dart';
import '../widgets/instafeed/instafeed_create_studio.dart';
import '../widgets/instafeed/instafeed_comments_sheet.dart';
import '../widgets/instafeed/instafeed_explore_grid.dart';
import '../widgets/instafeed/instafeed_post_card.dart';
import '../widgets/instafeed/instafeed_reels_modal.dart';
import '../widgets/instafeed/instafeed_share_sheet.dart';
import '../widgets/instafeed/instafeed_story_viewer.dart';
import '../widgets/instafeed/instafeed_travel_banners.dart';

// Bengali numeral helper
String toBengaliNum(int number) {
  const digits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return number.toString().split('').map((c) {
    final idx = int.tryParse(c);
    return idx != null ? digits[idx] : c;
  }).join('');
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

  // Feed Slicing & Views
  bool _isGridView = false; // Grid Explore View vs Feed List View
  String _selectedDayFilter = 'all';
  String _selectedMediaFilter = 'all'; // 'all', 'photos', 'reels', 'saved'
  String? _activeHashtagFilter;
  bool _sortByPopular = false;

  Set<String> _bookmarkedPostIds = {};
  Set<String> _seenStoryIds = {};
  TourGroup? _tourGroup;

  // Logistics cache (Seat & Room mappings: email -> seat/room)
  final Map<String, String> _seatMap = {};
  final Map<String, String> _roomMap = {};

  int _postLimit = _pageSize;
  late Stream<List<TourStoryItem>> _storiesStream;
  late Stream<List<TourPostItem>> _postsStream;
  late Stream<List<TourStoryHighlight>> _highlightsStream;
  late Stream<List<SafetyAlert>> _alertsStream;

  @override
  void initState() {
    super.initState();
    _storiesStream = _repository.watchStories(widget.tourId);
    _postsStream = _repository.watchPosts(widget.tourId, limit: _postLimit);
    _highlightsStream = _repository.watchHighlights(widget.tourId);
    _alertsStream = _repository.watchSafetyAlerts(widget.tourId);

    _loadGroup();
    _loadFeedPrefs();
    _loadLogistics();
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

  void _loadLogistics() {
    _repository.watchBusSeats(widget.tourId).listen((seats) {
      if (!mounted) return;
      setState(() {
        _seatMap.clear();
        for (final s in seats) {
          if (s.assignedMemberEmail != null &&
              s.assignedMemberEmail!.isNotEmpty) {
            _seatMap[s.assignedMemberEmail!] = s.seatNumber;
          }
        }
      });
    });

    _repository.watchHotelRooms(widget.tourId).listen((rooms) {
      if (!mounted) return;
      setState(() {
        _roomMap.clear();
        for (final r in rooms) {
          for (final email in r.assignedMemberEmails) {
            if (email.isNotEmpty) {
              _roomMap[email] = r.roomNumber;
            }
          }
        }
      });
    });
  }

  void _toggleBookmark(String postId) {
    setState(() {
      if (!_bookmarkedPostIds.remove(postId)) _bookmarkedPostIds.add(postId);
    });
    _saveFeedPrefs();
  }

  void _loadMorePosts() {
    setState(() {
      _postLimit += _pageSize;
      _postsStream = _repository.watchPosts(widget.tourId, limit: _postLimit);
    });
  }

  bool get _isAdmin {
    if (_tourGroup == null) return false;
    final email = _repository.currentEmail;
    return _tourGroup!.ownerEmail == email;
  }

  List<TourDayInfo> get _tourDays => _tourGroup?.daysList ?? const [];

  void _showCreatePostModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InstafeedCreateStudio(
        repository: _repository,
        tourId: widget.tourId,
        group: _tourGroup,
        picker: _picker,
        onPostCreated: () => setState(() {}),
      ),
    );
  }

  void _showCommentsModal(BuildContext context, TourPostItem post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InstafeedCommentsSheet(
        repository: _repository,
        tourId: widget.tourId,
        post: post,
        isAdmin: _isAdmin,
      ),
    );
  }

  void _showShareModal(BuildContext context, TourPostItem post) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InstafeedShareSheet(
        repository: _repository,
        tourId: widget.tourId,
        post: post,
        onResharedToStory: () => setState(() {}),
      ),
    );
  }

  void _openReelsModal(
      BuildContext context, List<TourPostItem> allReels, int initialIndex) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => InstafeedReelsModal(
          repository: _repository,
          tourId: widget.tourId,
          reels: allReels,
          initialIndex: initialIndex,
          onOpenComments: (post) => _showCommentsModal(context, post),
          onShare: (post) => _showShareModal(context, post),
          onAddToLedger: (post) => _showAddToLedgerDialog(post),
        ),
      ),
    );
  }

  Future<void> _showAddToLedgerDialog(TourPostItem post) async {
    final amountCtrl = TextEditingController(
      text: post.expenseAmount != null
          ? post.expenseAmount!.toStringAsFixed(0)
          : '',
    );
    final titleCtrl = TextEditingController(
      text: post.caption.isNotEmpty
          ? post.caption
          : 'ট্যুর খরচ (${post.authorName})',
    );
    String selectedCategory = post.expenseCategory ?? 'Food';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Color(0xFF00C853)),
            SizedBox(width: 8),
            Text('ট্রিপ লেজারে যোগ করুন',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'খরচের বিবরণ',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'টাকার পরিমাণ (BDT)',
                labelStyle: TextStyle(color: Colors.white70),
                prefixText: '৳ ',
                prefixStyle: TextStyle(color: Color(0xFF00C853)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              dropdownColor: const Color(0xFF222222),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'ক্যাটাগরি',
                labelStyle: TextStyle(color: Colors.white70),
              ),
              items: const [
                DropdownMenuItem(value: 'Food', child: Text('খাবার (Food)')),
                DropdownMenuItem(
                    value: 'Transport', child: Text('পরিবহন (Transport)')),
                DropdownMenuItem(
                    value: 'Hotel', child: Text('হোটেল / থাকার ব্যবস্থা')),
                DropdownMenuItem(
                    value: 'Activity', child: Text('দর্শনীয় ও স্পট')),
                DropdownMenuItem(value: 'Other', child: Text('অন্যান্য')),
              ],
              onChanged: (v) {
                if (v != null) selectedCategory = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00C853)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('যোগ করুন'),
          ),
        ],
      ),
    );

    if (result == true) {
      final paisa = TripLedgerEngine.parseTakaInput(amountCtrl.text.trim());
      if (paisa == null || paisa <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('সঠিক টাকার পরিমাণ দিন।')),
          );
        }
        return;
      }

      try {
        await _repository.addExpense(
          tourId: widget.tourId,
          title: titleCtrl.text.trim(),
          amountPaisa: paisa,
          paidById: post.authorEmail,
          paidByName: post.authorName,
          category: selectedCategory,
          date: DateTime.now(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('খরচটি সফলভাবে ট্রিপ লেজারে যুক্ত হয়েছে!'),
              backgroundColor: Color(0xFF00C853),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('লেজারে যোগ করা যায়নি: $e')),
          );
        }
      }
    }
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
          // View Mode Toggle (Grid vs Feed)
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_agenda_outlined : Icons.grid_on_outlined,
              color: Colors.white70,
            ),
            tooltip: _isGridView ? 'ফিড ভিউ' : 'এক্সপ্লোর গ্রিড ভিউ',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),

          // Sort Toggle (Newest vs Popular)
          IconButton(
            icon: Icon(
              _sortByPopular ? Icons.trending_up : Icons.access_time_rounded,
              color: _sortByPopular ? const Color(0xFF00C853) : Colors.white70,
            ),
            tooltip: _sortByPopular ? 'জনপ্রিয় পোস্ট' : 'সাম্প্রতিক পোস্ট',
            onPressed: () => setState(() => _sortByPopular = !_sortByPopular),
          ),

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
      body: StreamBuilder<List<SafetyAlert>>(
        stream: _alertsStream,
        builder: (context, alertsSnap) {
          final openAlerts = (alertsSnap.data ?? const <SafetyAlert>[])
              .where((a) => a.isOpenAt(DateTime.now()))
              .toList();

          return StreamBuilder<List<TourStoryItem>>(
            stream: _storiesStream,
            builder: (context, storiesSnap) {
              final now = DateTime.now();
              final stories = (storiesSnap.data ?? const <TourStoryItem>[])
                  .where((s) => s.isActiveAt(now))
                  .toList();
              final authorGroups = groupStoriesByAuthor(stories);

              return StreamBuilder<List<TourStoryHighlight>>(
                stream: _highlightsStream,
                builder: (context, highlightsSnap) {
                  final highlights =
                      highlightsSnap.data ?? const <TourStoryHighlight>[];

                  return StreamBuilder<List<TourPostItem>>(
                    stream: _postsStream,
                    builder: (context, postsSnap) {
                      final posts = postsSnap.data ?? const <TourPostItem>[];

                      // Apply filtering
                      var filteredPosts = posts.where((p) {
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
                        if (_selectedMediaFilter == 'saved' &&
                            !_bookmarkedPostIds.contains(p.id)) {
                          return false;
                        }
                        if (_activeHashtagFilter != null &&
                            !p.caption.contains(_activeHashtagFilter!)) {
                          return false;
                        }
                        return true;
                      }).toList();

                      // Apply sorting
                      if (_sortByPopular) {
                        filteredPosts.sort(
                            (a, b) => b.likes.length.compareTo(a.likes.length));
                      } else {
                        // Keep pinned posts at top, then chronological
                        filteredPosts.sort((a, b) {
                          if (a.isPinned && !b.isPinned) return -1;
                          if (!a.isPinned && b.isPinned) return 1;
                          return b.createdAt.compareTo(a.createdAt);
                        });
                      }

                      final hasMore = posts.length >= _postLimit;
                      final reelsList = posts.where((p) => p.isReel).toList();

                      return CustomScrollView(
                        slivers: [
                          // 1. Live SOS Alert Banner (if active)
                          if (openAlerts.isNotEmpty)
                            SliverToBoxAdapter(
                              child: InstafeedSosBanner(
                                tourId: widget.tourId,
                                alert: openAlerts.first,
                              ),
                            ),

                          // 2. Beach Tide & Ocean Safety Banner
                          SliverToBoxAdapter(
                            child: InstafeedTideBanner(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => TideBeachGuideScreen(
                                      tourId: widget.tourId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          // 3. Stories & Story Highlights Tray
                          SliverToBoxAdapter(
                            child: _buildStoriesAndHighlightsBar(
                              context,
                              authorGroups,
                              highlights,
                            ),
                          ),

                          // 4. Hashtag Filter Chip (if active)
                          if (_activeHashtagFilter != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                child: Row(
                                  children: [
                                    Chip(
                                      backgroundColor: const Color(0xFF00C853)
                                          .withValues(alpha: 0.2),
                                      avatar: const Icon(Icons.tag,
                                          size: 16, color: Color(0xFF00C853)),
                                      label: Text(
                                        _activeHashtagFilter!,
                                        style: const TextStyle(
                                            color: Color(0xFF00C853),
                                            fontWeight: FontWeight.bold),
                                      ),
                                      deleteIcon: const Icon(Icons.close,
                                          size: 16, color: Colors.white70),
                                      onDeleted: () => setState(
                                          () => _activeHashtagFilter = null),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 5. Media Filter Tabs (All, Photos, Reels, Saved)
                          SliverToBoxAdapter(
                            child: _buildMediaFilterTabs(),
                          ),

                          // 6. Day-wise Filter Chips
                          SliverToBoxAdapter(
                            child: _buildDayFilterChips(),
                          ),

                          // 7. Posts: Grid View vs Feed List View
                          if (postsSnap.hasError && !postsSnap.hasData)
                            SliverFillRemaining(child: _buildFeedError(context))
                          else if (!postsSnap.hasData)
                            const SliverFillRemaining(
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.mintGreen),
                              ),
                            )
                          else if (filteredPosts.isEmpty)
                            SliverFillRemaining(
                                child: _buildEmptyFeedState(context))
                          else if (_isGridView)
                            SliverFillRemaining(
                              child: InstafeedExploreGrid(
                                posts: filteredPosts,
                                onPostTap: (post) {
                                  if (post.isReel) {
                                    final reelIdx = reelsList.indexOf(post);
                                    _openReelsModal(context, reelsList,
                                        reelIdx >= 0 ? reelIdx : 0);
                                  } else {
                                    setState(() => _isGridView = false);
                                  }
                                },
                              ),
                            )
                          else
                            SliverList(
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
                                  return InstafeedPostCard(
                                    key: ValueKey(post.id),
                                    post: post,
                                    tourId: widget.tourId,
                                    repository: _repository,
                                    isAdmin: _isAdmin,
                                    seatNumber: _seatMap[post.authorEmail],
                                    roomNumber: _roomMap[post.authorEmail],
                                    isBookmarked:
                                        _bookmarkedPostIds.contains(post.id),
                                    onBookmarkToggle: () =>
                                        _toggleBookmark(post.id),
                                    onOpenComments: (p) =>
                                        _showCommentsModal(context, p),
                                    onShare: (p) => _showShareModal(context, p),
                                    onAddToLedger: (p) =>
                                        _showAddToLedgerDialog(p),
                                    onHashtagTap: (tag) => setState(
                                        () => _activeHashtagFilter = tag),
                                    onPostChanged: () => setState(() {}),
                                  );
                                },
                                childCount:
                                    filteredPosts.length + (hasMore ? 1 : 0),
                              ),
                            ),

                          const SliverToBoxAdapter(child: SizedBox(height: 80)),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStoriesAndHighlightsBar(
    BuildContext context,
    List<List<TourStoryItem>> authorGroups,
    List<TourStoryHighlight> highlights,
  ) {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // Your Story add button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => _showCreatePostModal(context),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey.shade900,
                        backgroundImage: _repository.isSignedIn &&
                                _repository.currentDisplayName.isNotEmpty
                            ? null
                            : null,
                        child: const Icon(Icons.person,
                            color: Colors.white54, size: 28),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00C853),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add,
                              size: 14, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('আপনার স্টোরি',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),

          // Author Stories Bubbles
          ...List.generate(authorGroups.length, (idx) {
            final group = authorGroups[idx];
            final first = group.first;
            final isUnseen = group.any((s) => !_seenStoryIds.contains(s.id));

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: GestureDetector(
                onTap: () {
                  for (final s in group) {
                    _seenStoryIds.add(s.id);
                  }
                  _saveFeedPrefs();

                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InstafeedStoryViewer(
                        repository: _repository,
                        tourId: widget.tourId,
                        authorStoryGroups: authorGroups,
                        initialGroupIndex: idx,
                      ),
                    ),
                  );
                },
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isUnseen
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF00E676),
                                  Color(0xFF1DE9B6),
                                  Color(0xFF00B0FF)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.grey.shade700,
                                  Colors.grey.shade800
                                ],
                              ),
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.black,
                        backgroundImage: first.authorPhoto != null
                            ? NetworkImage(first.authorPhoto!)
                            : null,
                        child: first.authorPhoto == null
                            ? Text(
                                first.authorName.isNotEmpty
                                    ? first.authorName[0].toUpperCase()
                                    : 'M',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: Text(
                        first.authorName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Tour Story Highlights
          if (highlights.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              width: 1,
              color: Colors.white12,
            ),
            ...highlights.map((h) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey.shade900,
                      backgroundImage: h.coverUrl.isNotEmpty
                          ? NetworkImage(h.coverUrl)
                          : null,
                      child: h.coverUrl.isEmpty
                          ? const Icon(Icons.star,
                              color: Colors.amber, size: 24)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 60,
                      child: Text(
                        h.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaFilterTabs() {
    final filters = [
      {'id': 'all', 'label': 'সবগুলো (All)'},
      {'id': 'photos', 'label': 'ছবি (Photos)'},
      {'id': 'reels', 'label': 'রিলস (Reels)'},
      {'id': 'saved', 'label': 'সেভ করা (Saved)'},
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.map((f) {
          final isSelected = _selectedMediaFilter == f['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: isSelected,
              selectedColor: const Color(0xFF00C853),
              backgroundColor: const Color(0xFF1E1E1E),
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              onSelected: (_) =>
                  setState(() => _selectedMediaFilter = f['id']!),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDayFilterChips() {
    if (_tourDays.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('সব দিন'),
            selected: _selectedDayFilter == 'all',
            selectedColor: Colors.white24,
            backgroundColor: Colors.transparent,
            labelStyle: const TextStyle(color: Colors.white, fontSize: 11),
            onSelected: (_) => setState(() => _selectedDayFilter = 'all'),
          ),
          const SizedBox(width: 6),
          ..._tourDays.map((d) {
            final isSelected = _selectedDayFilter == d.id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(d.label),
                selected: isSelected,
                selectedColor: Colors.white24,
                backgroundColor: Colors.transparent,
                labelStyle: TextStyle(
                  color: isSelected ? const Color(0xFF00C853) : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) => setState(() => _selectedDayFilter = d.id),
              ),
            );
          }),
        ],
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
                size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            const Text(
              'পোস্টগুলো লোড করা যায়নি',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => setState(() {
                _postsStream =
                    _repository.watchPosts(widget.tourId, limit: _postLimit);
              }),
              child: const Text('পুনরায় চেষ্টা করুন'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFeedState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 54, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'এখনও কোনো পোস্ট নেই',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'ট্যুরের প্রথম ছবিটি আপনিই সবার সাথে শেয়ার করুন!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853)),
              icon: const Icon(Icons.add_a_photo, color: Colors.black),
              label: const Text('পোস্ট তৈরি করুন',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: () => _showCreatePostModal(context),
            ),
          ],
        ),
      ),
    );
  }
}
