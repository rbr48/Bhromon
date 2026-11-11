import 'dart:async';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:bhromon/core/media/media_access.dart';
import 'package:flutter/material.dart';
import '../widgets/group_back_button.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/utils/logger.dart';
import '../../data/paged_post_feed.dart';
import '../../data/tour_group_repository.dart';
import '../../data/tour_media_journal.dart';
import '../../data/tour_media_uploader.dart';
import '../../domain/models/date_codec.dart';
import '../../domain/models/logistics_models.dart';
import '../../domain/models/safety_alert_models.dart';
import '../../domain/models/tour_activity_models.dart';
import '../../domain/models/tour_group.dart';
import '../../domain/models/tour_post_models.dart';
import '../../domain/services/fund_analytics.dart';
import '../../domain/services/post_view_queue.dart';
import '../../domain/services/trip_ledger_engine.dart';
import '../widgets/fund/expense_editor.dart';
import '../widgets/instafeed/feed_resume.dart';
import '../widgets/instafeed/instafeed_create_studio.dart';
import '../widgets/instafeed/instafeed_comments_sheet.dart';
import '../widgets/instafeed/instafeed_day_filter_bar.dart';
import '../widgets/instafeed/instafeed_explore_grid.dart';
import '../widgets/instafeed/instafeed_filter_sheet.dart';
import '../widgets/instafeed/instafeed_image_viewer_modal.dart';
import '../widgets/instafeed/instafeed_post_card.dart';
import '../widgets/instafeed/reel_thumbnail_preview.dart';
import '../widgets/instafeed/instafeed_reels_modal.dart';
import '../widgets/instafeed/instafeed_share_sheet.dart';
import '../widgets/instafeed/instafeed_story_viewer.dart';
import '../widgets/instafeed/instafeed_travel_banners.dart';
import '../widgets/instafeed/tour_safe_network_image.dart';
import '../../../../core/localization/app_localizations.dart';

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

  /// Bookmarked posts that are older than the loaded page. Fetched when the
  /// Saved view opens, so a bookmark from months ago still shows there.
  List<TourPostItem> _savedOutsidePage = const [];

  // Feed video: one card holds a player, the one nearest the middle of the
  // screen once scrolling has stopped. A scroll releases it.
  final Map<String, GlobalKey> _videoCardKeys = {};
  // The video that plays. A notifier, so a change rebuilds only the card that
  // starts or stops, not the whole feed.
  final ValueNotifier<String?> _playingVideoNotifier =
      ValueNotifier<String?>(null);
  bool _isScrolling = false;
  // Views of the posts the feed has built, sent in a few writes once scrolling
  // settles, rather than one write per post during a fling.
  final PostViewQueue _viewQueue = PostViewQueue();
  Timer? _viewFlushTimer;
  bool _settleScheduled = false;
  TourGroup? _tourGroup;
  StreamSubscription<TourGroup?>? _groupSub;
  StreamSubscription<List<BusSeat>>? _seatSub;
  StreamSubscription<List<HotelRoom>>? _roomSub;

  // Where the feed was left, per tour: its view and the post at the top. The
  // screen is rebuilt when you leave it, so the map lives on the class.
  static final Map<String, FeedResume> _resumeByTour = {};
  // Enough frames to reach a post that is far down, or on a page not loaded yet.
  static const int _restoreAttempts = 240;
  final ScrollController _feedScroll = ScrollController();
  // Each post's row, and each post's place in the list shown, so the feed can
  // find the post at the top of the screen.
  final Map<String, GlobalKey> _rowKeys = {};
  Map<String, int> _visibleIndex = {};
  bool _feedRestoreScheduled = false;
  bool _feedRestored = false;
  bool _feedCaptureScheduled = false;
  double? _restoredTo;
  int? _resumeLoadRequestedFor;

  // Logistics cache (Seat & Room mappings: email -> seat/room)
  final Map<String, String> _seatMap = {};
  final Map<String, String> _roomMap = {};

  late PagedPostFeed _feed;

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
    _feed = PagedPostFeed(
      repository: _repository,
      tourId: widget.tourId,
      pageSize: _pageSize,
    );
    _postsStream = _feed.stream;
    _highlightsStream = _repository.watchHighlights(widget.tourId);
    _alertsStream = _repository.watchSafetyAlerts(widget.tourId);

    _restoreFeedView();
    _feedScroll.addListener(_rememberFeedOffset);
    _watchGroup();
    _loadMyRole();
    _loadFeedPrefs();
    _loadLogistics();
    unawaited(TourMediaJournal.instance.sweep(
      isReferenced: _repository.isMediaReferenced,
      deleteRemote: TourMediaUploader.deleteMedia,
    ));
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _seatSub?.cancel();
    _roomSub?.cancel();
    _saveFeedView();
    // Views noted so far are sent now, so leaving the feed does not lose them.
    unawaited(_sendPendingViews());
    _feedScroll.removeListener(_rememberFeedOffset);
    _feedScroll.dispose();
    unawaited(_feed.close());
    _playingVideoNotifier.dispose();
    super.dispose();
  }

  /// Notes where the feed is as the user scrolls, so it outlives a rebuild.
  void _rememberFeedOffset() => _scheduleFeedCapture();

  FeedResume _resumeFor(String tourId) =>
      _resumeByTour.putIfAbsent(tourId, () => FeedResume());

  GlobalKey _rowKeyFor(String postId) =>
      _rowKeys.putIfAbsent(postId, () => GlobalKey());

  /// Puts the filters, sort and layout back to how the feed was left.
  void _restoreFeedView() {
    final resume = _resumeByTour[widget.tourId];
    if (resume == null) return;
    _selectedDayFilter = resume.day;
    _selectedMediaFilter = resume.media;
    _activeHashtagFilter = resume.hashtag;
    _selectedLandmarkFilter = resume.landmark;
    _selectedBookmarkCollection = resume.bookmarkCollection;
    _sortByPopular = resume.popular;
    _isGridView = resume.grid;
  }

  /// Writes the current filters, sort and layout into the tour's record.
  void _saveFeedView() {
    final resume = _resumeFor(widget.tourId);
    resume
      ..day = _selectedDayFilter
      ..media = _selectedMediaFilter
      ..hashtag = _activeHashtagFilter
      ..landmark = _selectedLandmarkFilter
      ..bookmarkCollection = _selectedBookmarkCollection
      ..popular = _sortByPopular
      ..grid = _isGridView;
  }

  /// Notes the post at the top of the screen once the frame has laid out. It is
  /// taken again after each change, so it is current when the user leaves, even
  /// after new posts have pushed the content down.
  void _scheduleFeedCapture() {
    if (_feedCaptureScheduled) return;
    _feedCaptureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feedCaptureScheduled = false;
      if (mounted) _captureFeedResume();
    });
  }

  void _captureFeedResume() {
    // Nothing is noted while the feed is still moving to its saved place.
    if (!_feedRestored) return;
    _saveFeedView();
    if (_isGridView || !_feedScroll.hasClients) return;
    final resume = _resumeFor(widget.tourId);
    final pixels = _feedScroll.position.pixels;
    final rows = layoutFeedRows(_rowKeys, _visibleIndex);
    final anchor = pickFeedAnchor(rows, pixels);
    resume
      ..pixels = pixels
      ..anchorPostId = anchor?.postId
      ..anchorDy = anchor?.dy ?? 0;
    final average = averageFeedRowHeight(rows);
    if (average > 0) resume.averageHeight = average;
  }

  /// Returns the feed to the offset it was left at, once the posts have laid
  /// out far enough. Gives up after a while, and leaves the feed where it is if
  /// the user has already scrolled.
  void _restoreFeedOffset(int attemptsLeft) {
    _feedRestoreScheduled = false;
    if (_feedRestored || !mounted) return;
    final resume = _resumeByTour[widget.tourId];
    if (resume == null || resume.grid) {
      _feedRestored = true;
      return;
    }
    if (!_feedScroll.hasClients) {
      if (attemptsLeft > 0) {
        _scheduleFeedRestore(attemptsLeft - 1);
      } else {
        _feedRestored = true;
      }
      return;
    }
    final position = _feedScroll.position;
    final anchorId = resume.anchorPostId;
    final index = anchorId == null ? null : _visibleIndex[anchorId];
    final anchorKey = anchorId == null ? null : _rowKeys[anchorId];
    final anchorBox = anchorKey == null ? null : laidOutRow(anchorKey);
    final rows = layoutFeedRows(_rowKeys, _visibleIndex);
    final restoredTo = _restoredTo;
    final plan = planFeedRestore(
      resume: resume,
      userScrolled: feedMovedByUser(
        pixels: position.pixels,
        restoredTo: restoredTo,
        maxExtent: position.maxScrollExtent,
      ),
      anchorListed: index != null,
      hasMore: _feed.hasMore,
      loadRequested: _resumeLoadRequestedFor == _latestPosts.length,
      anchorTop: anchorBox == null ? null : feedRowTop(anchorBox),
      estimate: index == null
          ? null
          : estimateFeedOffset(
              rows: rows,
              index: index,
              averageHeight: resume.averageHeight > 0
                  ? resume.averageHeight
                  : averageFeedRowHeight(rows),
            ),
      outOfTime: attemptsLeft <= 0,
      maxExtent: position.maxScrollExtent,
    );
    if (plan.loadMore) {
      _resumeLoadRequestedFor = _latestPosts.length;
      _loadMorePosts();
    }
    final target = plan.jumpTo;
    if (target != null) {
      _restoredTo = target;
      position.jumpTo(target);
    }
    if (plan.finished) {
      _feedRestored = true;
      // The video to play is chosen where the feed is, so choose it again here.
      _scheduleSettle();
      return;
    }
    _scheduleFeedRestore(attemptsLeft - 1);
  }

  void _scheduleFeedRestore(int attemptsLeft) {
    if (_feedRestoreScheduled) return;
    _feedRestoreScheduled = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _restoreFeedOffset(attemptsLeft));
    // The restore may wait on a frame that nothing else asks for.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Keeps the tour's details live, so a trip change by an admin shows at once
  /// (days, destination, live status) without reopening the feed.
  void _watchGroup() {
    _groupSub = _repository.watchGroup(widget.tourId).listen(
      (g) {
        if (mounted) setState(() => _tourGroup = g);
      },
      onError: (Object e) => logWarning('[TourInstaFeed] group watch: $e'),
    );
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
      // A collection deleted since the view was left is not restored.
      if (_selectedBookmarkCollection != null &&
          !_bookmarkCollections.containsKey(_selectedBookmarkCollection)) {
        _selectedBookmarkCollection = null;
      }
    });
    // A restored Saved view reads its posts from these bookmarks.
    if (_selectedMediaFilter == 'saved') unawaited(_refreshSavedPosts());
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
    _seatSub = _repository.watchBusSeats(widget.tourId).listen((seats) {
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

    _roomSub = _repository.watchHotelRooms(widget.tourId).listen((rooms) {
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
      backgroundColor: context.forest.feedSurface,
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
                        color: context.forest.text24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.translate('ig_collections_title'),
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.translate('ig_collections_hint'),
                    style:
                        TextStyle(color: context.forest.text54, fontSize: 12),
                  ),
                  Divider(color: context.forest.divider12, height: 20),

                  // Existing Collections
                  if (_bookmarkCollections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        context.l10n.translate('ig_no_folders'),
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 13),
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
                                style: TextStyle(color: context.forest.text)),
                            subtitle: Text(
                                context.l10n.translate('ig_saved_count',
                                    args: {'count': list.length}),
                                style: TextStyle(
                                    color: context.forest.text54,
                                    fontSize: 12)),
                            value: isIncluded,
                            activeColor: AppColors.mintGreen,
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
                          style: TextStyle(color: context.forest.text),
                          decoration: InputDecoration(
                            hintText:
                                context.l10n.translate('ig_folder_name_hint'),
                            hintStyle: TextStyle(
                                color: context.forest.text54, fontSize: 13),
                            filled: true,
                            fillColor: context.forest.feedField,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.mintGreen,
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
                        child: Text(context.l10n.translate('ig_create'),
                            style: const TextStyle(
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
          : (_tourGroup?.destination ??
              context.l10n.translate('ig_main_tourist_centre'));
      byLandmark.putIfAbsent(loc, () => []).add(p);
    }

    final sortedLandmarks = byLandmark.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.forest.feedDeep,
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
                color: context.forest.text24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.explore_rounded,
                      color: context.forest.accentText, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.translate('ig_landmark_map'),
                    style: TextStyle(
                      color: context.forest.text,
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
                      child: Text(context.l10n.translate('ig_clear_filter'),
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
            Divider(color: context.forest.divider12, height: 1),
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
                        ? AppColors.mintGreen.withValues(alpha: 0.15)
                        : context.forest.feedSurface,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.mintGreen
                            : context.forest.divider10,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(10),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: firstImage.images.isNotEmpty &&
                                  isRemoteMediaUrl(firstImage.images.first)
                              ? TourSafeNetworkImage(
                                  imageUrl: firstImage.images.first,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      Container(color: Colors.grey.shade900),
                                  errorWidget: Icon(Icons.location_on,
                                      color: context.forest.accentText),
                                )
                              : Center(
                                  child: Icon(Icons.location_on,
                                      color: context.forest.accentText)),
                        ),
                      ),
                      title: Text(
                        spotName,
                        style: TextStyle(
                          color: context.forest.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.translate('ig_memories_count',
                            args: {'count': spotPosts.length}),
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 12),
                      ),
                      trailing: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: isSelected
                              ? AppColors.mintGreen
                              : context.forest.divider12,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedLandmarkFilter =
                                isSelected ? null : spotName;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Text(
                          isSelected
                              ? context.l10n.translate('ig_selected')
                              : context.l10n.translate('ig_feed_filter'),
                          style: TextStyle(
                            color:
                                isSelected ? Colors.black : context.forest.text,
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

  void _loadMorePosts() => unawaited(_feed.loadMore());

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

  /// Notes a post the feed has built. Its view is recorded later, in a few
  /// writes, rather than one write each time a card is built.
  void _noteViewed(TourPostItem post) {
    final email = _repository.currentEmail;
    if (email.isEmpty) return;
    _viewQueue.note(post.id, alreadyViewed: post.isViewedBy(email));
    if (!_viewQueue.isEmpty) {
      _viewFlushTimer ??= Timer(const Duration(seconds: 1), _onViewFlushTimer);
    }
  }

  /// Sends the waiting views once the feed has been still for a moment. While it
  /// is moving, they wait for the scroll to end.
  void _onViewFlushTimer() {
    _viewFlushTimer = null;
    if (!_isScrolling) unawaited(_sendPendingViews());
  }

  /// Records the waiting views, in as few writes as the list allows.
  Future<void> _sendPendingViews() async {
    _viewFlushTimer?.cancel();
    _viewFlushTimer = null;
    final ids = _viewQueue.take();
    if (ids.isEmpty) return;
    await _repository.recordPostViews(tourId: widget.tourId, postIds: ids);
  }

  /// Handles the feed's own scrolling. A scroll releases the playing video, and
  /// the one nearest the middle is picked when it stops. Nested scrollers, such
  /// as the stories tray, are ignored.
  bool _onFeedScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _isScrolling = true;
      _playingVideoNotifier.value = null;
    } else if (n is ScrollEndNotification) {
      _isScrolling = false;
      _scheduleSettle();
      if (!_viewQueue.isEmpty) unawaited(_sendPendingViews());
    }
    return false;
  }

  /// Picks the video once the frame has laid out, so the cards have positions.
  void _scheduleSettle() {
    if (_settleScheduled) return;
    _settleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settleScheduled = false;
      if (mounted) _settleVideos();
    });
  }

  /// Chooses the built video card nearest the middle of the screen. Does
  /// nothing while the feed is scrolling.
  void _settleVideos() {
    if (_isScrolling) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final middle = screenHeight / 2;

    String? nearest;
    var nearestGap = double.infinity;
    for (final entry in _videoCardKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom <= 0 || top >= screenHeight) continue;
      final gap = ((top + bottom) / 2 - middle).abs();
      if (gap < nearestGap) {
        nearestGap = gap;
        nearest = entry.key;
      }
    }
    _playingVideoNotifier.value = nearest;
  }

  /// The posts the feed filters: the loaded page, plus bookmarks from outside
  /// it while the Saved view is open.
  List<TourPostItem> _feedSource(List<TourPostItem> posts) {
    if (_selectedMediaFilter != 'saved' || _savedOutsidePage.isEmpty) {
      return posts;
    }
    final loaded = posts.map((p) => p.id).toSet();
    return [
      ...posts,
      ..._savedOutsidePage.where((p) => !loaded.contains(p.id)),
    ];
  }

  /// Fetches the bookmarks that are not on the loaded page.
  Future<void> _refreshSavedPosts() async {
    final loaded = _latestPosts.map((p) => p.id).toSet();
    final missing = _bookmarkedPostIds.where((id) => !loaded.contains(id));
    try {
      final fetched = await _repository.getPostsByIds(widget.tourId, missing);
      if (mounted) setState(() => _savedOutsidePage = fetched);
    } catch (e) {
      logWarning('[TourInstaFeed] Could not load saved posts: $e');
    }
  }

  /// Drops bookmarks and collection entries for posts that no longer exist,
  /// such as a post deleted by its author. Called only with the whole feed
  /// loaded, so an id that is missing really is gone.
  void _pruneMissingBookmarks(List<TourPostItem> posts) {
    int entryCount() =>
        _bookmarkedPostIds.length +
        _bookmarkCollections.values.fold(0, (n, list) => n + list.length);

    final before = entryCount();
    final live = posts.map((p) => p.id).toSet();
    _bookmarkedPostIds.removeWhere((id) => !live.contains(id));
    for (final name in _bookmarkCollections.keys.toList()) {
      _bookmarkCollections[name] =
          _bookmarkCollections[name]!.where(live.contains).toList();
    }
    if (entryCount() != before) _saveFeedPrefs();
  }

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

  void _showCreatePostModal(BuildContext context, {bool isStory = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InstafeedCreateStudio(
        repository: _repository,
        tourId: widget.tourId,
        group: _tourGroup,
        picker: _picker,
        isStory: isStory,
        onPostCreated: () => setState(() {}),
      ),
    );
  }

  void _showCommentsModal(BuildContext context, TourPostItem post,
      {int? targetMediaIndex}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InstafeedCommentsSheet(
        repository: _repository,
        tourId: widget.tourId,
        post: post,
        isAdmin: _isAdmin,
        targetMediaIndex: targetMediaIndex,
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
        group: _tourGroup,
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
          : context.l10n
              .translate('ig_trip_expense', args: {'name': post.authorName}),
    );
    // The same categories the ledger offers, so the budget lines pick it up.
    final offered = expenseCategoriesForGroup(_tourGroup);
    String selectedCategory = post.expenseCategory ?? offered.first;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.forest.feedSurface,
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: context.forest.accentText),
            const SizedBox(width: 8),
            Text(context.l10n.translate('ig_add_to_ledger'),
                style: TextStyle(color: context.forest.text)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              style: TextStyle(color: context.forest.text),
              decoration: InputDecoration(
                labelText: context.l10n.translate('ig_expense_details'),
                labelStyle: TextStyle(color: context.forest.text70),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: context.forest.text),
              decoration: InputDecoration(
                labelText: context.l10n.translate('ig_amount_bdt'),
                labelStyle: TextStyle(color: context.forest.text70),
                prefixText: '৳ ',
                prefixStyle: TextStyle(color: context.forest.accentText),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              dropdownColor: context.forest.feedRaised,
              style: TextStyle(color: context.forest.text),
              decoration: InputDecoration(
                labelText: context.l10n.translate('ig_category'),
                labelStyle: TextStyle(color: context.forest.text70),
              ),
              items: [
                // An older post's category stays selectable even if it is not
                // on the list now.
                for (final c in [
                  ...offered,
                  if (!offered.contains(selectedCategory)) selectedCategory,
                ])
                  DropdownMenuItem(
                      value: c,
                      child: Text(fundCategoryLabel(context.l10n, c))),
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
            child: Text(context.l10n.translate('ig_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.translate('ig_add')),
          ),
        ],
      ),
    );

    if (result == true) {
      final paisa = TripLedgerEngine.parseTakaInput(amountCtrl.text.trim());
      if (paisa == null || paisa <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.l10n.translate('ig_enter_valid_amount'))),
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
            SnackBar(
              content: Text(context.l10n.translate('ig_expense_added')),
              backgroundColor: AppColors.mintGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.l10n
                    .translate('ig_ledger_add_failed', args: {'error': e}))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLive = _tourGroup?.isLiveAt(DateTime.now()) ?? false;

    return GroupPopScope(
      tourId: widget.tourId,
      child: Scaffold(
        backgroundColor: context.forest.feedPage,
        appBar: AppBar(
          leading: GroupBackButton(tourId: widget.tourId),
          backgroundColor: context.forest.feedPage,
          elevation: 0,
          title: Row(
            children: [
              Text(
                context.l10n.translate('hub_nav_moments'),
                style: TextStyle(
                  color: context.forest.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                  letterSpacing: 0.5,
                ),
              ),
              if (isLive) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
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
                _isGridView
                    ? Icons.view_agenda_outlined
                    : Icons.grid_on_outlined,
                color: context.forest.text70,
              ),
              tooltip: _isGridView
                  ? context.l10n.translate('ig_feed_view')
                  : context.l10n.translate('ig_grid_view'),
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),

            // Landmark Map / Location Hub
            IconButton(
              icon: Icon(
                Icons.explore_outlined,
                color: _selectedLandmarkFilter != null
                    ? context.forest.accentText
                    : context.forest.text70,
              ),
              tooltip: context.l10n.translate('ig_spot_map'),
              onPressed: () => _showLandmarkMapModal(context, _latestPosts),
            ),

            // Sort Toggle (Newest vs Popular)
            IconButton(
              icon: Icon(
                _sortByPopular ? Icons.trending_up : Icons.access_time_rounded,
                color: _sortByPopular
                    ? context.forest.accentText
                    : context.forest.text70,
              ),
              tooltip: _sortByPopular
                  ? context.l10n.translate('ig_popular_posts')
                  : context.l10n.translate('ig_recent_posts'),
              onPressed: () => setState(() => _sortByPopular = !_sortByPopular),
            ),

            IconButton(
              icon: Icon(Icons.add_photo_alternate_rounded,
                  color: context.forest.accentText),
              tooltip: context.l10n.translate('ig_share_new_post'),
              onPressed: () => _showCreatePostModal(context),
            ),
          ],
        ),
        floatingActionButton: !(_tourGroup?.momentsOpen ?? true)
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom > 0
                      ? MediaQuery.of(context).padding.bottom
                      : 8,
                ),
                child: FloatingActionButton(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: Colors.black,
                  elevation: 6,
                  tooltip: context.l10n.translate('ig_add_camera_photo'),
                  onPressed: () => _showCreatePostModal(context),
                  child: const Icon(Icons.camera_alt_rounded, size: 28),
                ),
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
                if (storiesSnap.hasError) {
                  logError(
                      '[Instafeed] Error in stories stream: ${storiesSnap.error}',
                      storiesSnap.error,
                      storiesSnap.stackTrace);
                }
                final now = DateTime.now();
                final stories = (storiesSnap.data ?? const <TourStoryItem>[])
                    .where((s) => s.isActiveAt(now,
                        tolerance: const Duration(minutes: 15)))
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
                        if (postsSnap.hasData) _scheduleSettle();

                        // Apply filtering
                        var filteredPosts = _feedSource(posts).where((p) {
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
                          filteredPosts.sort((a, b) =>
                              b.likes.length.compareTo(a.likes.length));
                        } else {
                          // Keep pinned posts at top, then chronological
                          filteredPosts.sort((a, b) {
                            if (a.isPinned && !b.isPinned) return -1;
                            if (!a.isPinned && b.isPinned) return 1;
                            return b.createdAt.compareTo(a.createdAt);
                          });
                        }

                        final hasMore = _feed.hasMore;
                        // Only with the whole feed loaded is a missing id known to be gone.
                        if (postsSnap.hasData && !hasMore) {
                          _pruneMissingBookmarks(posts);
                        }
                        _maybeAutoLoadForFilter(
                            needsMore: filteredPosts.isEmpty && hasMore);
                        final reelsList = posts.where((p) => p.isReel).toList();

                        _visibleIndex = {
                          for (var i = 0; i < filteredPosts.length; i++)
                            filteredPosts[i].id: i,
                        };
                        _rowKeys.removeWhere(
                            (id, _) => !_visibleIndex.containsKey(id));
                        if (!_feedRestored && filteredPosts.isNotEmpty) {
                          _scheduleFeedRestore(_restoreAttempts);
                        }
                        _scheduleFeedCapture();
                        return NotificationListener<ScrollNotification>(
                          onNotification: _onFeedScroll,
                          child: CustomScrollView(
                            controller: _feedScroll,
                            // ignore: deprecated_member_use
                            cacheExtent: 1600.0,
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

                              // 2. Stories & Story Highlights Tray (Facebook card style)
                              SliverToBoxAdapter(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 720),
                                    child: _buildStoriesAndHighlightsBar(
                                      context,
                                      authorGroups,
                                      highlights,
                                    ),
                                  ),
                                ),
                              ),

                              // 4. Hashtag Filter Chip (if active)
                              if (_activeHashtagFilter != null)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 580),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 4),
                                        child: Row(
                                          children: [
                                            Chip(
                                              backgroundColor: AppColors
                                                  .mintGreen
                                                  .withValues(alpha: 0.2),
                                              avatar: Icon(Icons.tag,
                                                  size: 16,
                                                  color: context
                                                      .forest.accentText),
                                              label: Text(
                                                _activeHashtagFilter!,
                                                style: TextStyle(
                                                    color: context
                                                        .forest.accentText,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              deleteIcon: Icon(Icons.close,
                                                  size: 16,
                                                  color: context.forest.text70),
                                              onDeleted: () => setState(() =>
                                                  _activeHashtagFilter = null),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // 4b. Landmark Filter Chip (if active)
                              if (_selectedLandmarkFilter != null)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 580),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 4),
                                        child: Row(
                                          children: [
                                            Chip(
                                              backgroundColor: AppColors
                                                  .mintGreen
                                                  .withValues(alpha: 0.2),
                                              avatar: Icon(Icons.location_on,
                                                  size: 16,
                                                  color: context
                                                      .forest.accentText),
                                              label: Text(
                                                _selectedLandmarkFilter!,
                                                style: TextStyle(
                                                    color: context
                                                        .forest.accentText,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              deleteIcon: Icon(Icons.close,
                                                  size: 16,
                                                  color: context.forest.text70),
                                              onDeleted: () => setState(() =>
                                                  _selectedLandmarkFilter =
                                                      null),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // 5. Day filter circles and sub-header toolbar
                              SliverToBoxAdapter(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 580),
                                    child: InstafeedDayFilterBar(
                                      days: _tourDays,
                                      selectedDay: _selectedDayFilter,
                                      onDaySelected: (dayId) => setState(
                                          () => _selectedDayFilter = dayId),
                                      allPosts: _latestPosts,
                                      filteredCount: filteredPosts.length,
                                      isGridView: _isGridView,
                                      onViewModeChanged: (grid) =>
                                          setState(() => _isGridView = grid),
                                      onOpenFilterSheet: () =>
                                          unawaited(_showFilterSheet()),
                                      activeFilterSummary: _filterSummary(),
                                    ),
                                  ),
                                ),
                              ),

                              // 5b. Bookmark Collection Chips (When Saved Tab is active)
                              if (_selectedMediaFilter == 'saved')
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 580),
                                      child: Container(
                                        height: 40,
                                        margin: const EdgeInsets.only(
                                            top: 4, bottom: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                        child: ListView(
                                          scrollDirection: Axis.horizontal,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 6),
                                              child: ChoiceChip(
                                                label: Text(context.l10n
                                                    .translate('ig_all_saved')),
                                                selected:
                                                    _selectedBookmarkCollection ==
                                                        null,
                                                selectedColor: Colors.amber,
                                                backgroundColor:
                                                    context.forest.feedSurface,
                                                labelStyle: TextStyle(
                                                  color:
                                                      _selectedBookmarkCollection ==
                                                              null
                                                          ? Colors.black
                                                          : context
                                                              .forest.text70,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                onSelected: (_) => setState(() =>
                                                    _selectedBookmarkCollection =
                                                        null),
                                              ),
                                            ),
                                            ..._bookmarkCollections.keys
                                                .map((name) {
                                              final isSel =
                                                  _selectedBookmarkCollection ==
                                                      name;
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 6),
                                                child: ChoiceChip(
                                                  label: Text(name),
                                                  selected: isSel,
                                                  selectedColor: Colors.amber,
                                                  backgroundColor: context
                                                      .forest.feedSurface,
                                                  labelStyle: TextStyle(
                                                    color: isSel
                                                        ? Colors.black
                                                        : context.forest.text70,
                                                    fontSize: 12,
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
                                  ),
                                ),

                              // 7. Posts: Grid View vs Feed List View
                              if (postsSnap.hasError && !postsSnap.hasData)
                                SliverFillRemaining(
                                    child: _buildFeedError(context))
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
                                          onOpenComments: (p,
                                                  {targetMediaIndex}) =>
                                              _showCommentsModal(context, p,
                                                  targetMediaIndex:
                                                      targetMediaIndex),
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
                                            child: Text(context.l10n
                                                .translate('ig_more_posts')),
                                          ),
                                        );
                                      }
                                      final post = filteredPosts[index];
                                      _noteViewed(post);
                                      final isVideo = post.videoUrl != null;
                                      // Only a video card listens for the video that plays, so a
                                      // change rebuilds one card, not the whole feed.
                                      Widget cardFor(String? playingId) {
                                        return RepaintBoundary(
                                          key: _rowKeyFor(post.id),
                                          child: Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 580,
                                              ),
                                              child: InstafeedPostCard(
                                                // Video cards keep a GlobalKey, so the feed can
                                                // find their position when it picks one to play.
                                                key: isVideo
                                                    ? _videoCardKeys
                                                        .putIfAbsent(post.id,
                                                            () => GlobalKey())
                                                    : ValueKey(post.id),
                                                post: post,
                                                tourDays: _tourDays,
                                                videoPlaying:
                                                    post.id == playingId,
                                                onVideoTap: isVideo
                                                    ? () {
                                                        _playingVideoNotifier
                                                            .value = post.id;
                                                      }
                                                    : null,
                                                tourId: widget.tourId,
                                                repository: _repository,
                                                isAdmin: _isAdmin,
                                                seatNumber:
                                                    _seatMap[post.authorEmail],
                                                roomNumber:
                                                    _roomMap[post.authorEmail],
                                                isBookmarked: _bookmarkedPostIds
                                                    .contains(post.id),
                                                onBookmarkToggle: () =>
                                                    _toggleBookmark(post.id),
                                                onSaveToCollection:
                                                    _showSaveToCollectionSheet,
                                                onOpenComments: (p,
                                                        {targetMediaIndex}) =>
                                                    _showCommentsModal(
                                                        context, p,
                                                        targetMediaIndex:
                                                            targetMediaIndex),
                                                onShare: (p) =>
                                                    _showShareModal(context, p),
                                                onAddToLedger: (p) =>
                                                    _showAddToLedgerDialog(p),
                                                onReelTap: (p) {
                                                  final reelIdx =
                                                      reelsList.indexOf(p);
                                                  _openReelsModal(
                                                    context,
                                                    reelsList,
                                                    reelIdx >= 0 ? reelIdx : 0,
                                                  );
                                                },
                                                onHashtagTap: (tag) => setState(
                                                    () => _activeHashtagFilter =
                                                        tag),
                                                onPostChanged: () =>
                                                    setState(() {}),
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      if (!isVideo) return cardFor(null);
                                      return ValueListenableBuilder<String?>(
                                        valueListenable: _playingVideoNotifier,
                                        builder: (context, playingId, _) =>
                                            cardFor(playingId),
                                      );
                                    },
                                    childCount: filteredPosts.length +
                                        (hasMore ? 1 : 0),
                                  ),
                                ),

                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 80)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Opens the story viewer at one author's group, and marks its stories seen.
  void _openStoryViewer(
    BuildContext context,
    List<List<TourStoryItem>> authorGroups,
    int idx,
  ) {
    for (final s in authorGroups[idx]) {
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
  }

  Widget _buildStoriesAndHighlightsBar(
    BuildContext context,
    List<List<TourStoryItem>> authorGroups,
    List<TourStoryHighlight> highlights,
  ) {
    // Your own stories open from the Your Story card, so they are not listed twice.
    final me = normalizeEmail(_repository.currentEmail);
    final ownIndex = me.isEmpty
        ? -1
        : authorGroups
            .indexWhere((g) => normalizeEmail(g.first.authorEmail) == me);

    return Container(
      height: 195,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // 1. Facebook "Create Story" or "Your Story" Card
          _buildFacebookCreateStoryCard(context, authorGroups, ownIndex),

          // 2. Member Story Cards (Facebook style)
          ...List.generate(authorGroups.length, (idx) {
            if (idx == ownIndex) return const SizedBox.shrink();
            final group = authorGroups[idx];
            final latest = group.last;
            final isUnseen = group.any((s) => !_seenStoryIds.contains(s.id));

            return _buildFacebookStoryCard(
              context: context,
              story: latest,
              storyCount: group.length,
              isUnseen: isUnseen,
              onTap: () => _openStoryViewer(context, authorGroups, idx),
            );
          }),

          // 3. Tour Story Highlights
          if (highlights.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              width: 1,
              color: context.forest.divider12,
            ),
            ...highlights.map((h) => _buildFacebookHighlightCard(h)),
          ],
        ],
      ),
    );
  }

  Widget _buildFacebookCreateStoryCard(
    BuildContext context,
    List<List<TourStoryItem>> authorGroups,
    int ownIndex,
  ) {
    const cardWidth = 112.0;
    const cardHeight = 178.0;

    // If the current user already has active stories posted:
    if (ownIndex >= 0) {
      final myGroup = authorGroups[ownIndex];
      final latestStory = myGroup.last;
      final isVideo = latestStory.isVideo ||
          latestStory.mediaUrl.endsWith('.mp4') ||
          latestStory.mediaUrl.endsWith('.mov') ||
          latestStory.mediaUrl.endsWith('.webm') ||
          (latestStory.videoUrl != null && latestStory.videoUrl!.isNotEmpty);

      return Container(
        width: cardWidth,
        height: cardHeight,
        margin: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openStoryViewer(context, authorGroups, ownIndex),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isVideo)
                  ReelThumbnailPreview(
                    videoUrl: latestStory.videoUrl ?? latestStory.mediaUrl,
                    fit: BoxFit.cover,
                  )
                else
                  TourSafeNetworkImage(
                    imageUrl: latestStory.mediaUrl,
                    fit: BoxFit.cover,
                    placeholder: Container(color: context.forest.feedSurface),
                    errorWidget: Container(
                      color: context.forest.feedSurface,
                      child: Icon(Icons.person, color: context.forest.text38),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: context.forest.divider12, width: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black,
                      child: Text(
                        latestStory.authorName.isNotEmpty
                            ? latestStory.authorName[0].toUpperCase()
                            : 'M',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _showCreatePostModal(context, isStory: true),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.mintGreen,
                      ),
                      child: const Icon(Icons.add,
                          size: 14, color: AppColors.darkGreen),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    context.l10n.translate('ig_your_story'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                            color: Colors.black87,
                            blurRadius: 4,
                            offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Classic Facebook "Create Story" Card
    return Container(
      width: cardWidth,
      height: cardHeight,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCreatePostModal(context, isStory: true),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: context.forest.feedBubble,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.forest.divider12, width: 0.5),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      flex: 65,
                      child: Container(
                        width: double.infinity,
                        color: context.forest.feedPlaceholder,
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: context.forest.text.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 35,
                      child: Container(
                        width: double.infinity,
                        color: context.forest.feedBubble,
                        padding:
                            const EdgeInsets.only(top: 18, left: 4, right: 4),
                        child: Text(
                          context.l10n.translate('ig_create_story'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            color: context.forest.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: cardHeight * 0.65 - 18,
                  left: (cardWidth - 36) / 2,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.mintGreen,
                      border: Border.all(
                          color: context.forest.feedBubble, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      color: AppColors.darkGreen,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFacebookStoryCard({
    required BuildContext context,
    required TourStoryItem story,
    required int storyCount,
    required bool isUnseen,
    required VoidCallback onTap,
  }) {
    const cardWidth = 112.0;
    const cardHeight = 178.0;
    final isVideo = story.isVideo ||
        story.mediaUrl.endsWith('.mp4') ||
        story.mediaUrl.endsWith('.mov') ||
        story.mediaUrl.endsWith('.webm') ||
        (story.videoUrl != null && story.videoUrl!.isNotEmpty);

    return Container(
      width: cardWidth,
      height: cardHeight,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isVideo)
                ReelThumbnailPreview(
                  videoUrl: story.videoUrl ?? story.mediaUrl,
                  fit: BoxFit.cover,
                )
              else
                TourSafeNetworkImage(
                  imageUrl: story.mediaUrl,
                  fit: BoxFit.cover,
                  placeholder: Container(color: context.forest.feedSurface),
                ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: context.forest.divider12, width: 0.5),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isUnseen
                        ? const LinearGradient(
                            colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              Colors.grey.shade600,
                              Colors.grey.shade700
                            ],
                          ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black,
                    backgroundImage: story.authorPhoto != null
                        ? NetworkImage(signedMediaUrl(story.authorPhoto!))
                        : null,
                    child: story.authorPhoto == null
                        ? Text(
                            story.authorName.isNotEmpty
                                ? story.authorName[0].toUpperCase()
                                : 'M',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              if (storyCount > 1 || story.isVideo)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (story.isVideo)
                          const Icon(Icons.play_arrow_rounded,
                              size: 12, color: Colors.white),
                        if (storyCount > 1)
                          Text(
                            '$storyCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Text(
                  story.authorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 4,
                          offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFacebookHighlightCard(TourStoryHighlight highlight) {
    const cardWidth = 100.0;
    const cardHeight = 178.0;

    return Container(
      width: cardWidth,
      height: cardHeight,
      margin: const EdgeInsets.only(right: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (highlight.coverUrl.isNotEmpty)
              TourSafeNetworkImage(
                imageUrl: highlight.coverUrl,
                fit: BoxFit.cover,
                placeholder: Container(color: context.forest.feedSurface),
                errorWidget: Container(
                  color: context.forest.feedSurface,
                  child: const Icon(Icons.star, color: Colors.amber),
                ),
              )
            else
              Container(
                color: context.forest.feedSurface,
                child: const Icon(Icons.star, color: Colors.amber, size: 32),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.forest.divider12, width: 0.5),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            const Positioned(
              top: 8,
              left: 8,
              child: Icon(Icons.star, color: Colors.amber, size: 18),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Text(
                highlight.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The header pill's text: the media filter, then the day when the tour has
  /// days.
  String _filterSummary() {
    final media = instafeedMediaFilters(context)
        .firstWhere((option) => option.id == _selectedMediaFilter)
        .label;
    if (_tourDays.isEmpty) return media;
    var day = context.l10n.translate('ig_all_days');
    for (final d in _tourDays) {
      if (d.id == _selectedDayFilter) day = d.label;
    }
    return '$media · $day';
  }

  /// Opens the filter choices. Each choice updates the feed and the sheet at
  /// once, so the sheet can stay open while the user tries more than one.
  Future<void> _showFilterSheet() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.forest.feedSurface,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => InstafeedFilterSheet(
          selectedMedia: _selectedMediaFilter,
          onMediaSelected: (id) {
            setState(() => _selectedMediaFilter = id);
            setSheetState(() {});
            if (id == 'saved') unawaited(_refreshSavedPosts());
          },
          days: _tourDays,
          selectedDay: _selectedDayFilter,
          onDaySelected: (id) {
            setState(() => _selectedDayFilter = id);
            setSheetState(() {});
          },
        ),
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
            Icon(Icons.cloud_off_rounded,
                size: 48, color: context.forest.text54),
            const SizedBox(height: 12),
            Text(
              context.l10n.translate('ig_posts_load_failed'),
              style: TextStyle(color: context.forest.text70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => setState(() {
                unawaited(_feed.close());
                _feed = PagedPostFeed(
                  repository: _repository,
                  tourId: widget.tourId,
                  pageSize: _pageSize,
                );
                _postsStream = _feed.stream;
              }),
              child: Text(context.l10n.translate('ig_retry')),
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
                  Icon(Icons.filter_alt_off_outlined,
                      size: 54, color: context.forest.text54),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.translate('ig_no_posts_filter'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: context.forest.text,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                  if (hasMore) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _loadMorePosts,
                      child: Text(context.l10n.translate('ig_more_posts')),
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
            Icon(Icons.photo_library_outlined,
                size: 54, color: context.forest.text54),
            const SizedBox(height: 16),
            Text(
              context.l10n.translate('ig_no_posts'),
              style: TextStyle(
                  color: context.forest.text,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.translate('ig_share_first_photo'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.forest.text54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.mintGreen),
              icon: const Icon(Icons.add_a_photo, color: Colors.black),
              label: Text(context.l10n.translate('ig_create_post'),
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: () => _showCreatePostModal(context),
            ),
          ],
        ),
      ),
    );
  }
}
