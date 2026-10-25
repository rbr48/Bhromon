import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_journal.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/safety_alert_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/tour_post_models.dart';
import '../../domain/services/trip_ledger_engine.dart';
import 'tide_beach_guide_screen.dart';
import '../widgets/instafeed/instafeed_create_studio.dart';
import '../widgets/instafeed/instafeed_comments_sheet.dart';
import '../widgets/instafeed/instafeed_explore_grid.dart';
import '../widgets/instafeed/instafeed_image_viewer_modal.dart';
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
  String _selectedMediaFilter =
      'all'; // 'all', 'photos', 'reels', 'saved', 'archived'
  String? _activeHashtagFilter;
  String? _selectedLandmarkFilter;
  bool _sortByPopular = false;

  Set<String> _bookmarkedPostIds = {};
  Map<String, List<String>> _bookmarkCollections = {};
  String? _selectedBookmarkCollection;
  Set<String> _seenStoryIds = {};
  List<TourPostItem> _latestPosts = const [];
  TourGroup? _tourGroup;

  // Logistics cache (Seat & Room mappings: email -> seat/room)
  final Map<String, String> _seatMap = {};
  final Map<String, String> _roomMap = {};

  int _postLimit = _pageSize;

  // Filtered pages can come back empty, so the feed pages in more posts while
  // nothing matches. Capped, so a filter that never matches stops on its own.
  static const int _maxEmptyAutoLoads = 3;
  int _emptyAutoLoads = 0;
  bool _autoLoadScheduled = false;
  String _autoLoadFilterKey = '';

  TourRole? _myRole;
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
    _loadMyRole();
    _loadFeedPrefs();
    _loadLogistics();
    unawaited(TourMediaJournal.instance.sweep(
      isReferenced: _repository.isMediaReferenced,
      deleteRemote: TourMediaUploader.deleteMedia,
    ));
  }

  Future<void> _loadGroup() async {
    final g = await _repository.getGroup(widget.tourId);
    if (mounted) setState(() => _tourGroup = g);
  }

  Future<void> _loadMyRole() async {
    final role = await _repository.myRole(widget.tourId);
    if (mounted) setState(() => _myRole = role);
  }

  Future<void> _loadFeedPrefs() async {
    final prefs = await _repository.loadFeedPrefs(widget.tourId);
    if (!mounted) return;
    setState(() {
      _bookmarkedPostIds = Set<String>.from(prefs.bookmarks);
      _seenStoryIds = Set<String>.from(prefs.seenStories);
      _bookmarkCollections = Map<String, List<String>>.from(prefs.collections);
    });
  }

  void _saveFeedPrefs() {
    _repository.saveFeedPrefs(
      widget.tourId,
      FeedPrefs(
        bookmarks: _bookmarkedPostIds,
        seenStories: _seenStoryIds,
        collections: _bookmarkCollections,
      ),
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
      if (!_bookmarkedPostIds.remove(postId)) {
        _bookmarkedPostIds.add(postId);
      } else {
        // Also remove from collections if unbookmarked
        for (final list in _bookmarkCollections.values) {
          list.remove(postId);
        }
      }
    });
    _saveFeedPrefs();
  }

  void _showSaveToCollectionSheet(TourPostItem post) {
    final newCollectionCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                  const Text(
                    'সংগ্রহ ফোল্ডারে যোগ করুন (Collections)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'পছন্দের পোস্টগুলোকে আলাদা ফোল্ডারে সংরক্ষণ করুন',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Divider(color: Colors.white12, height: 20),

                  // Existing Collections
                  if (_bookmarkCollections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'এখনও কোনো ফোল্ডার তৈরি করা হয়নি। নিচে নতুন ফোল্ডার তৈরি করুন।',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView(
                        shrinkWrap: true,
                        children: _bookmarkCollections.entries.map((entry) {
                          final collectionName = entry.key;
                          final list = entry.value;
                          final isIncluded = list.contains(post.id);

                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(collectionName,
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${list.length}টি পোস্ট সংরক্ষিত',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                            value: isIncluded,
                            activeColor: const Color(0xFF00C853),
                            onChanged: (bool? val) {
                              setSheetState(() {
                                if (val == true) {
                                  if (!list.contains(post.id)) {
                                    list.add(post.id);
                                  }
                                  _bookmarkedPostIds.add(post.id);
                                } else {
                                  list.remove(post.id);
                                }
                              });
                              setState(() {});
                              _saveFeedPrefs();
                            },
                          );
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 12),
                  // Create New Collection Input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newCollectionCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'নতুন ফোল্ডারের নাম (যেমন: খাবার, হোটেল)',
                            hintStyle: const TextStyle(
                                color: Colors.white38, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFF2C2C2C),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        onPressed: () {
                          final name = newCollectionCtrl.text.trim();
                          if (name.isNotEmpty) {
                            setSheetState(() {
                              _bookmarkCollections
                                  .putIfAbsent(name, () => [])
                                  .add(post.id);
                              _bookmarkedPostIds.add(post.id);
                              newCollectionCtrl.clear();
                            });
                            setState(() {});
                            _saveFeedPrefs();
                          }
                        },
                        child: const Text('তৈরি',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLandmarkMapModal(BuildContext context, List<TourPostItem> posts) {
    final byLandmark = <String, List<TourPostItem>>{};
    for (final p in posts) {
      final loc = p.location.trim().isNotEmpty
          ? p.location.trim()
          : (_tourGroup?.destination ?? 'প্রধান পর্যটন কেন্দ্র');
      byLandmark.putIfAbsent(loc, () => []).add(p);
    }

    final sortedLandmarks = byLandmark.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.explore_rounded,
                      color: Color(0xFF00C853), size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'ল্যান্ডমার্ক ও স্পট ম্যাপ (Tour Landmarks)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedLandmarkFilter != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _selectedLandmarkFilter = null);
                        Navigator.pop(ctx);
                      },
                      child: const Text('ফিল্টার মুছুন',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: sortedLandmarks.length,
                itemBuilder: (context, idx) {
                  final entry = sortedLandmarks[idx];
                  final spotName = entry.key;
                  final spotPosts = entry.value;
                  final firstImage = spotPosts.firstWhere(
                    (p) => p.images.isNotEmpty,
                    orElse: () => spotPosts.first,
                  );
                  final isSelected = _selectedLandmarkFilter == spotName;

                  return Card(
                    color: isSelected
                        ? const Color(0xFF00C853).withValues(alpha: 0.15)
                        : const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF00C853)
                            : Colors.white10,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(10),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: firstImage.images.isNotEmpty &&
                                  isRemoteMediaUrl(firstImage.images.first)
                              ? CachedNetworkImage(
                                  imageUrl: firstImage.images.first,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) =>
                                      Container(color: Colors.grey.shade900),
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.location_on,
                                      color: Color(0xFF00C853)),
                                )
                              : const Center(
                                  child: Icon(Icons.location_on,
                                      color: Color(0xFF00C853))),
                        ),
                      ),
                      title: Text(
                        spotName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '${spotPosts.length}টি স্মৃতি ও ছবি সংগৃহীত',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      trailing: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: isSelected
                              ? const Color(0xFF00C853)
                              : Colors.white12,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedLandmarkFilter =
                                isSelected ? null : spotName;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          isSelected ? 'নির্বাচিত' : 'ফিড ফিল্টার',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _loadMorePosts() {
    setState(() {
      _postLimit += _pageSize;
      _postsStream = _repository.watchPosts(widget.tourId, limit: _postLimit);
    });
  }

  /// Owners and admins moderate the feed. The membership role is checked first;
  /// the group's owner email is a fallback for a missing membership row.
  bool get _isAdmin {
    if (_myRole == TourRole.owner || _myRole == TourRole.admin) return true;
    final email = _repository.currentEmail;
    return _tourGroup != null &&
        email.isNotEmpty &&
        _tourGroup!.ownerEmail == email;
  }

  String get _filterKey => [
        _selectedDayFilter,
        _selectedMediaFilter,
        _selectedBookmarkCollection,
        _selectedLandmarkFilter,
        _activeHashtagFilter,
      ].join('|');

  /// Loads the next page while the active filters match nothing on the loaded
  /// page. The budget starts again whenever the filters change.
  void _maybeAutoLoadForFilter({required bool needsMore}) {
    final key = _filterKey;
    if (key != _autoLoadFilterKey) {
      _autoLoadFilterKey = key;
      _emptyAutoLoads = 0;
    }
    if (!needsMore ||
        _autoLoadScheduled ||
        _emptyAutoLoads >= _maxEmptyAutoLoads) {
      return;
    }

    _autoLoadScheduled = true;
    _emptyAutoLoads++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadScheduled = false;
      if (mounted) _loadMorePosts();
    });
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

          // Landmark Map / Location Hub
          IconButton(
            icon: Icon(
              Icons.explore_outlined,
              color: _selectedLandmarkFilter != null
                  ? const Color(0xFF00C853)
                  : Colors.white70,
            ),
            tooltip: 'স্পট ও ল্যান্ডমার্ক ম্যাপ',
            onPressed: () => _showLandmarkMapModal(context, _latestPosts),
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
                      _latestPosts = posts;

                      // Apply filtering
                      var filteredPosts = posts.where((p) {
                        // Archive filter
                        if (_selectedMediaFilter == 'archived') {
                          if (!p.isArchived) return false;
                        } else {
                          if (p.isArchived) return false;
                        }

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
                        if (_selectedMediaFilter == 'saved') {
                          if (_selectedBookmarkCollection != null) {
                            final inColl = _bookmarkCollections[
                                        _selectedBookmarkCollection]
                                    ?.contains(p.id) ??
                                false;
                            if (!inColl) return false;
                          } else {
                            if (!_bookmarkedPostIds.contains(p.id)) {
                              return false;
                            }
                          }
                        }
                        if (_selectedLandmarkFilter != null &&
                            p.location != _selectedLandmarkFilter) {
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
                      _maybeAutoLoadForFilter(
                          needsMore: filteredPosts.isEmpty && hasMore);
                      final reelsList = posts.where((p) => p.isReel).toList();

                      return CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
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

                          // 4b. Landmark Filter Chip (if active)
                          if (_selectedLandmarkFilter != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                child: Row(
                                  children: [
                                    Chip(
                                      backgroundColor: const Color(0xFF00C853)
                                          .withValues(alpha: 0.2),
                                      avatar: const Icon(Icons.location_on,
                                          size: 16, color: Color(0xFF00C853)),
                                      label: Text(
                                        _selectedLandmarkFilter!,
                                        style: const TextStyle(
                                            color: Color(0xFF00C853),
                                            fontWeight: FontWeight.bold),
                                      ),
                                      deleteIcon: const Icon(Icons.close,
                                          size: 16, color: Colors.white70),
                                      onDeleted: () => setState(
                                          () => _selectedLandmarkFilter = null),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 5. Media Filter Tabs (All, Photos, Reels, Saved, Archived)
                          SliverToBoxAdapter(
                            child: _buildMediaFilterTabs(),
                          ),

                          // 5b. Bookmark Collection Chips (When Saved Tab is active)
                          if (_selectedMediaFilter == 'saved')
                            SliverToBoxAdapter(
                              child: Container(
                                height: 40,
                                margin:
                                    const EdgeInsets.only(top: 4, bottom: 4),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: const Text('সব সেভ করা'),
                                        selected:
                                            _selectedBookmarkCollection == null,
                                        selectedColor: Colors.amber,
                                        backgroundColor:
                                            const Color(0xFF1E1E1E),
                                        labelStyle: TextStyle(
                                          color: _selectedBookmarkCollection ==
                                                  null
                                              ? Colors.black
                                              : Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        onSelected: (_) => setState(() =>
                                            _selectedBookmarkCollection = null),
                                      ),
                                    ),
                                    ..._bookmarkCollections.keys.map((name) {
                                      final isSel =
                                          _selectedBookmarkCollection == name;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: ChoiceChip(
                                          label: Text(name),
                                          selected: isSel,
                                          selectedColor: Colors.amber,
                                          backgroundColor:
                                              const Color(0xFF1E1E1E),
                                          labelStyle: TextStyle(
                                            color: isSel
                                                ? Colors.black
                                                : Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          onSelected: (_) => setState(() =>
                                              _selectedBookmarkCollection =
                                                  name),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
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
                                child: posts.isEmpty
                                    ? _buildEmptyFeedState(context)
                                    : _buildFilteredEmptyState(
                                        hasMore: hasMore))
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
                                    InstafeedImageViewerModal.show(
                                      context,
                                      repository: _repository,
                                      tourId: widget.tourId,
                                      post: post,
                                      onOpenComments: (p) =>
                                          _showCommentsModal(context, p),
                                      onShare: (p) =>
                                          _showShareModal(context, p),
                                      onAddToLedger: (p) =>
                                          _showAddToLedgerDialog(p),
                                    );
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
                                    onSaveToCollection:
                                        _showSaveToCollectionSheet,
                                    onOpenComments: (p) =>
                                        _showCommentsModal(context, p),
                                    onShare: (p) => _showShareModal(context, p),
                                    onAddToLedger: (p) =>
                                        _showAddToLedgerDialog(p),
                                    onReelTap: (p) {
                                      final reelIdx = reelsList.indexOf(p);
                                      _openReelsModal(
                                        context,
                                        reelsList,
                                        reelIdx >= 0 ? reelIdx : 0,
                                      );
                                    },
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
                        isAdmin: _isAdmin,
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
      {'id': 'archived', 'label': 'আর্কাইভ (Archive)'},
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

  /// Shown when posts are loaded but the active filters hide all of them.
  Widget _buildFilteredEmptyState({required bool hasMore}) {
    final autoLoading = hasMore && _emptyAutoLoads < _maxEmptyAutoLoads;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: autoLoading
            ? const CircularProgressIndicator(color: AppColors.mintGreen)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_alt_off_outlined,
                      size: 54, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text(
                    'এই ফিল্টারে কোনো পোস্ট নেই',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                  if (hasMore) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _loadMorePosts,
                      child: const Text('আরও পোস্ট দেখুন'),
                    ),
                  ],
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
