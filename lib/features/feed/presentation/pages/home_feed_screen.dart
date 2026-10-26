import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/blurhash_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../widgets/in_app_youtube_player.dart';
import '../widgets/trip_log_detail_sheet.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../../../../core/theme/colors.dart';
import '../../../../app/di/injection.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../bloc/feed_cubit.dart';
import '../bloc/feed_state.dart';
import '../../../map/presentation/bloc/map_bloc.dart';
import '../../../map/presentation/bloc/map_event.dart';
import '../../../map/presentation/bloc/map_state.dart';
import '../../../../core/entities/location_pin.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../../../core/value_objects/explorer_score.dart';
import '../../../../core/entities/pro_tip.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/security/hive_encryption_service.dart';
import '../../../notifications/data/fcm_service.dart';
import '../../../../core/widgets/entry_reactions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/widgets/brand_logo_text.dart';
import '../../../../core/theme/theme_context.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/utils/shared_latest_stream.dart';
import '../../../../core/utils/image_sizing.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with SingleTickerProviderStateMixin {
  late final FeedCubit _feedCubit;
  String _selectedTab = 'Discover';
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  DateTime? _appStartTime;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else if (hour < 21) {
      return 'Good evening';
    } else {
      return 'Good night';
    }
  }

  String _getDayOfWeek() {
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return weekdays[DateTime.now().weekday - 1];
  }

  int _getTemp() {
    final hour = DateTime.now().hour;
    if (hour >= 11 && hour <= 16) return 33;
    if (hour >= 6 && hour <= 10) return 29;
    if (hour >= 17 && hour <= 20) return 30;
    return 26;
  }

  String _getWeatherCondition() {
    final hour = DateTime.now().hour;
    if (hour >= 19 || hour <= 5) return 'Clear';
    final min = DateTime.now().minute;
    if (min % 3 == 0) return 'Partly Cloudy';
    if (min % 5 == 0) return 'Cloudy';
    return 'Sunny';
  }

  IconData _getWeatherIcon() {
    final condition = _getWeatherCondition();
    final hour = DateTime.now().hour;
    final isNight = hour >= 19 || hour <= 5;
    if (isNight) {
      return Icons.nights_stay_rounded;
    }
    if (condition == 'Sunny') {
      return Icons.wb_sunny_rounded;
    }
    if (condition == 'Partly Cloudy') {
      return Icons.cloud_queue_rounded;
    }
    return Icons.cloud_rounded;
  }

  Color _getWeatherIconColor() {
    final hour = DateTime.now().hour;
    final isNight = hour >= 19 || hour <= 5;
    if (isNight) {
      return const Color(0xFF9B5DE5); // Night purple
    }
    final condition = _getWeatherCondition();
    if (condition == 'Sunny') {
      return const Color(0xFFFFD166); // Sun yellow
    }
    return const Color(0xFFAEC6CF); // Soft cloud blue
  }

  // Search State
  bool _isSearching = false;
  String _searchQuery = '';
  late final TextEditingController _searchController;

  // Local Interaction State
  final Set<String> _savedLogs = {};

  // Author profile cache: uid -> {displayName, avatarUrl}
  static final Map<String, Map<String, String>> _profileCache = {};

  // Cache user's own reactions: tripId -> reactionKey
  final Map<String, String?> _myReactionsCache = {};

  // In-flight/completed lookups, so FutureBuilders get the same future on
  // every rebuild and a page of posts by one author fires one read, not N.
  static final Map<String, Future<Map<String, String>>> _profileFutures = {};
  final Map<String, Future<String?>> _myReactionFutures = {};

  // Firestore listeners per card, created once per doc instead of on every
  // card rebuild.
  // Shared so a trip shown twice (carousel + list) still gets the current
  // value immediately.
  final Map<String, Stream<DocumentSnapshot>> _likeStreams = {};
  final Map<String, Stream<DocumentSnapshot>> _logDocStreams = {};

  static Stream<DocumentSnapshot> _shared(DocumentReference ref) =>
      SharedLatestStream<DocumentSnapshot>(ref.snapshots()).stream;

  // Lower-cased searchable text per trip log, built once per load.
  final Map<String, String> _searchTextCache = {};
  Timer? _searchDebounce;

  final ScrollController _scrollController = ScrollController();

  // Opened once: a future created in build() restarts its FutureBuilder.
  late final Future<Box<dynamic>> _syncOutboxBox =
      getIt<HiveEncryptionService>().openEncryptedBox<dynamic>('sync_outbox');

  // Animation controller for grid movement and orb pulsation
  late final AnimationController _animationController;
  late final Animation<double> _orbOpacity;

  @override
  void initState() {
    super.initState();
    _feedCubit = getIt<FeedCubit>();
    // Loads once auth has settled; the BlocListener in build() picks up later
    // sign-in/sign-out changes.
    _loadFeedFor(context.read<AuthCubit>().state);
    _searchController = TextEditingController();
    _loadSavedLogs();

    // Load nearby pins (centered around Dhaka default) from Firestore
    context
        .read<MapBloc>()
        .add(const LoadPinsEvent(lat: 23.6850, lng: 90.3563));

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _orbOpacity = _animationController.drive(Tween(begin: 0.7, end: 1.0));

    // Setup active notifications listener based on AuthCubit state
    _authSubscription = context.read<AuthCubit>().stream.listen((state) {
      if (!mounted) return;
      if (state is Authenticated) {
        _setupNotificationsListener(state.profile.uid);
        getIt<FcmService>().init(state.profile.uid, context);
      } else {
        _cancelNotificationsListener();
      }
    });

    // Check initial state
    final initialState = context.read<AuthCubit>().state;
    if (initialState is Authenticated) {
      _setupNotificationsListener(initialState.profile.uid);
      getIt<FcmService>().init(initialState.profile.uid, context);
    }
  }

  Future<void> _loadSavedLogs() async {
    try {
      final encryptionService = getIt<HiveEncryptionService>();
      final box =
          await encryptionService.openEncryptedBox<dynamic>('saved_logs');
      setState(() {
        _savedLogs.addAll(box.values.cast<String>());
      });

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .doc(currentUid)
            .collection('saved_diaries')
            .get();
        final firestoreIds = snap.docs.map((doc) => doc.id).toList();
        if (!mounted) return;
        setState(() {
          _savedLogs.addAll(firestoreIds);
        });
        if (_selectedTab == 'Saved') {
          _feedCubit.loadSaved(_savedLogs.toList().reversed.toList());
        }
        for (final id in firestoreIds) {
          if (!box.containsKey(id)) {
            box.put(id, id);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleSaveLog(String tripId) async {
    try {
      final encryptionService = getIt<HiveEncryptionService>();
      final box =
          await encryptionService.openEncryptedBox<dynamic>('saved_logs');
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      setState(() {
        if (_savedLogs.contains(tripId)) {
          _savedLogs.remove(tripId);
          box.delete(tripId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Removed from Saved!'),
                duration: Duration(seconds: 1)),
          );
          if (currentUid != null) {
            FirebaseFirestore.instance
                .collection('explorer_profiles')
                .doc(currentUid)
                .collection('saved_diaries')
                .doc(tripId)
                .delete();
            FirebaseFirestore.instance
                .collection('explorer_profiles')
                .doc(currentUid)
                .update({
              'savedTripLogIds': FieldValue.arrayRemove([tripId])
            });
          }
        } else {
          _savedLogs.add(tripId);
          box.put(tripId, tripId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Saved to your vault!'),
                duration: Duration(seconds: 1)),
          );
          if (currentUid != null) {
            FirebaseFirestore.instance
                .collection('explorer_profiles')
                .doc(currentUid)
                .collection('saved_diaries')
                .doc(tripId)
                .set({
              'savedAt': FieldValue.serverTimestamp(),
            });
            FirebaseFirestore.instance
                .collection('explorer_profiles')
                .doc(currentUid)
                .update({
              'savedTripLogIds': FieldValue.arrayUnion([tripId])
            });
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _handleReaction(TripLog log, String key) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final docId = currentUid;
    final userReactionRef = FirebaseFirestore.instance
        .collection('trip_logs')
        .doc(log.tripId)
        .collection('reactions')
        .doc(docId);

    final parentLogRef =
        FirebaseFirestore.instance.collection('trip_logs').doc(log.tripId);

    // Save previous reaction for rollback if needed
    final String? rollbackReaction = _myReactionsCache[log.tripId];

    // Optimistically update local cache and rebuild UI
    setState(() {
      if (rollbackReaction == key) {
        _myReactionsCache[log.tripId] = null;
      } else {
        _myReactionsCache[log.tripId] = key;
      }
    });

    try {
      final reactionDoc = await userReactionRef.get();
      String? previousReaction;
      if (reactionDoc.exists) {
        final data = reactionDoc.data();
        if (data != null) {
          previousReaction = data['reactionKey'] as String?;
        }
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshParentDoc = await transaction.get(parentLogRef);
        if (!freshParentDoc.exists) return;

        final Map<String, dynamic> data =
            freshParentDoc.data() as Map<String, dynamic>;
        final Map<String, int> reactionsMap = Map<String, int>.from(
            (data['reactions'] as Map<dynamic, dynamic>?)?.map(
                    (k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
                {});

        if (previousReaction == key) {
          // Un-react: remove reaction
          transaction.delete(userReactionRef);
          reactionsMap[key] = (reactionsMap[key] ?? 1) - 1;
          if (reactionsMap[key]! <= 0) {
            reactionsMap.remove(key);
          }
        } else {
          // Change or add reaction
          transaction.set(userReactionRef, {
            'reactionKey': key,
            'timestamp': FieldValue.serverTimestamp(),
          });

          if (previousReaction != null) {
            reactionsMap[previousReaction] =
                (reactionsMap[previousReaction] ?? 1) - 1;
            if (reactionsMap[previousReaction]! <= 0) {
              reactionsMap.remove(previousReaction);
            }
          }
          reactionsMap[key] = (reactionsMap[key] ?? 0) + 1;
        }

        transaction.update(parentLogRef, {'reactions': reactionsMap});
      });
    } catch (e) {
      debugPrint('Error handling reaction: $e');
      // Rollback on error
      setState(() {
        _myReactionsCache[log.tripId] = rollbackReaction;
      });
    }
  }

  Future<void> _saveSearchToHistory(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final encryptionService = getIt<HiveEncryptionService>();
      final box = await encryptionService
          .openEncryptedBox<dynamic>('user_search_history');
      final List<String> history = List<String>.from(box.values);
      history.remove(query);
      history.insert(0, query);
      if (history.length > 10) {
        history.removeLast();
      }
      await box.clear();
      for (int i = 0; i < history.length; i++) {
        await box.put(i, history[i]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _animationController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _feedCubit.close();
    super.dispose();
  }

  void _setupNotificationsListener(String uid) {
    _notificationsSubscription?.cancel();
    _appStartTime = DateTime.now();
    _notificationsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final timestamp = data['timestamp'] as Timestamp?;
          if (timestamp != null && _appStartTime != null) {
            // Check if this notification is new (added after app started)
            if (timestamp.toDate().isAfter(_appStartTime!)) {
              final String title = (data['title'] as String?) ?? 'New Alert';
              final String body = (data['body'] as String?) ?? '';
              final String action = (data['action'] as String?) ?? '';
              final String? notifUid = data['uid'] as String?;

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: AppColors.cardDark.withValues(alpha: 0.95),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.mintGreen,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  action: SnackBarAction(
                    label: 'View',
                    textColor: AppColors.mintGreen,
                    onPressed: () {
                      _handleNotificationAction(context, action, notifUid);
                    },
                  ),
                ),
              );
            }
          }
        }
      }
    });
  }

  void _cancelNotificationsListener() {
    _notificationsSubscription?.cancel();
    _notificationsSubscription = null;
  }

  static final ExplorerProfile _guestProfile = ExplorerProfile(
    uid: 'explorer_user',
    displayName: 'Guest Explorer',
    explorerScore: const ExplorerScore(value: 0, tier: TrustTier.unverified),
    tier: TrustTier.unverified,
    badges: const [],
    division: 'Dhaka',
    createdAt: DateTime(2024),
  );

  /// The feed viewer for [state], or null while auth is still resolving
  /// (initial, loading, waiting for an OTP).
  static ExplorerProfile? _viewerFor(AuthState state) => switch (state) {
        Authenticated(:final profile) => profile,
        Unauthenticated() || AuthError() => _guestProfile,
        _ => null,
      };

  /// Who the currently loaded feed is for; avoids reloading for the same one.
  String? _loadedViewerUid;

  void _loadFeedFor(AuthState state, {bool force = false}) {
    final viewer = _viewerFor(state);
    if (viewer == null) return;
    if (!force && viewer.uid == _loadedViewerUid) return;
    _loadedViewerUid = viewer.uid;
    _searchTextCache.clear();
    _feedCubit.loadFeed(viewer);
  }

  Future<void> _refreshFeed() async {
    final viewer = _viewerFor(context.read<AuthCubit>().state) ??
        _feedCubit.viewer ??
        _guestProfile;
    _loadedViewerUid = viewer.uid;
    _searchTextCache.clear();
    await _feedCubit.loadFeed(viewer);
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final uid = authState is Authenticated ? authState.profile.uid : '';
    final displayName =
        authState is Authenticated ? authState.profile.displayName : 'Guest';
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double bottomSpacerHeight = 96.0 + bottomPadding;

    // Specific colors from the ultra mockup
    const Color mockBackground = Color(0xFFF6F5F1);

    return Scaffold(
      backgroundColor: mockBackground,
      body: BlocListener<AuthCubit, AuthState>(
        // React only when the viewer actually changes, not to every
        // intermediate auth state (loading, OTP sent, ...).
        listenWhen: (previous, current) =>
            _viewerFor(current) != null &&
            _viewerFor(current)?.uid != _viewerFor(previous)?.uid,
        listener: (context, state) => _loadFeedFor(state),
        child: Stack(
          children: [
            // Scrollable Body
            Positioned.fill(
              child: RefreshIndicator(
                onRefresh: _refreshFeed,
                color: const Color(0xFF52B788), // Mint-green spinner
                backgroundColor:
                    const Color(0xFF0D1A12), // Dark card background
                // A CustomScrollView builds only the cards on screen; the
                // old Column-in-SingleChildScrollView laid out every card.
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onFeedScroll,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      // 1. HERO HEADER AREA
                      SliverToBoxAdapter(
                          child: _buildAnimatedHeroHeader(context)),

                      // 2. TABS & SCROLLABLE BODY SECTIONS
                      SliverToBoxAdapter(child: _buildSubNavigation()),

                      if (_selectedTab == 'Discover') ...[
                        SliverToBoxAdapter(child: _buildSyncBar()),
                        SliverToBoxAdapter(
                            child: _buildCreatePostComposer(displayName, uid)),
                        SliverToBoxAdapter(
                            child: _buildFeaturedTripLogsSection()),
                        SliverToBoxAdapter(
                            child: _buildProTipsHorizontalFeed()),
                        SliverToBoxAdapter(
                            child: _buildExplorerSpotlightSection()),
                        _buildFacebookFeedSliver(),
                      ] else if (_selectedTab == 'Near me') ...[
                        SliverToBoxAdapter(child: _buildNearMeTabContent()),
                      ] else if (_selectedTab == 'Saved') ...[
                        _buildSavedTabSliver(),
                      ] else if (_selectedTab == 'Divisions') ...[
                        SliverToBoxAdapter(child: _buildDivisionsTabContent()),
                      ] else if (_selectedTab == 'Trending') ...[
                        SliverToBoxAdapter(child: _buildTrendingTabContent()),
                      ] else if (_selectedTab == 'Archive') ...[
                        _buildArchiveTabSliver(),
                      ],
                      SliverToBoxAdapter(
                          child: SizedBox(height: bottomSpacerHeight)),
                    ],
                  ),
                ),
              ),
            ),

            // 3. CUSTOM BOTTOM GLASSMORPHIC NAV BAR
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildCustomBottomNavigationBar(uid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedHeroHeader(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final uid = authState is Authenticated ? authState.profile.uid : '';
    final displayName =
        authState is Authenticated ? authState.profile.displayName : 'Guest';

    // Only the orb's opacity animates, so it's the only thing the animation
    // drives: FadeTransition repaints that one layer without rebuilding the
    // hero (search field, greeting, stats) on every frame.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B2117), // Deep forest/pine green
            Color(0xFF1B4332), // Nature green
          ],
        ),
      ),
      child: Stack(
        children: [
          // Pulsing Orbs Background
          Positioned(
            top: -80,
            right: -60,
            child: FadeTransition(
              opacity: _orbOpacity,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF74C69D).withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF52B788).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Hero content layout
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand top bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isSearching) ...[
                        // Search Mode Row
                        _buildIconButton(
                          icon: Icons.arrow_back,
                          onTap: () {
                            _searchDebounce?.cancel();
                            setState(() {
                              _isSearching = false;
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        ),
                        Expanded(
                          child: Container(
                            height: 36,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.5),
                              decoration: InputDecoration(
                                hintText: 'Search travel logs...',
                                hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 12.5),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              onChanged: (val) {
                                // Filter once typing pauses, not on
                                // every keystroke.
                                _searchDebounce?.cancel();
                                _searchDebounce = Timer(
                                    const Duration(milliseconds: 300), () {
                                  if (mounted) {
                                    setState(() => _searchQuery = val);
                                  }
                                });
                              },
                              onSubmitted: (val) {
                                _saveSearchToHistory(val);
                              },
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          _buildIconButton(
                            icon: Icons.close,
                            onTap: () {
                              _searchDebounce?.cancel();
                              setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          )
                        else
                          const SizedBox(width: 36),
                      ] else ...[
                        // Default Mode Row
                        // Brand top bar (Left: Logo and Title)
                        const BhromonBrandLogo(height: 38),

                        // Brand top bar (Right: Search, Bell notification, Profile)
                        Row(
                          children: [
                            _buildIconButton(
                              icon: Icons.search,
                              onTap: () {
                                setState(() {
                                  _isSearching = true;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildIconButtonWithDot(
                              icon: Icons.notifications_none_outlined,
                              hasNotification: true,
                              onTap: () => _showNotificationCenter(context),
                            ),
                            const SizedBox(width: 8),
                            _buildIconButton(
                              icon: Icons.tune_rounded,
                              onTap: () =>
                                  _showPersonalizeFeedBottomSheet(context),
                            ),
                            const SizedBox(width: 8),
                            _buildIconButton(
                              icon: Icons.account_circle_outlined,
                              onTap: () {
                                final targetUid =
                                    uid.isNotEmpty ? uid : 'explorer_user';
                                _showProfileNavigationMenu(context, targetUid);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Greeting Info
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18.0, vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_getWeatherIcon(),
                              color: _getWeatherIconColor(), size: 13),
                          const SizedBox(width: 6),
                          Text(
                            '${_getGreeting()} · ${_getDayOfWeek()} · ${_getTemp()}° ${_getWeatherCondition()}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1.15,
                          ),
                          children: [
                            const TextSpan(text: 'Where to next, '),
                            TextSpan(
                              text: '$displayName?',
                              style: const TextStyle(
                                color: Color(0xFFE9C46A),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Rounded curves connecting to the body
                const SizedBox(height: 14),
                Container(
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6F5F1), // mockBackground
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet(BuildContext context, TripLog log) {
    final TextEditingController commentController = TextEditingController();
    final authState = context.read<AuthCubit>().state;
    final String currentUserId =
        authState is Authenticated ? authState.profile.uid : '';
    final String currentUserName = authState is Authenticated
        ? authState.profile.displayName
        : 'Guest User';
    // Created once per sheet, not on every sheet rebuild.
    final commentsStream = FirebaseFirestore.instance
        .collection(log.isArchived ? 'archived_trip_logs' : 'trip_logs')
        .doc(log.tripId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots();

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
            child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.92,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Divider(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: commentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                              'Error loading comments: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red)),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.midGreen));
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No comments yet. Be the first to comment!',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final String commentId = doc.id;
                          final String authorId =
                              (data['authorId'] as String?) ?? '';
                          final String authorName =
                              (data['authorName'] as String?) ?? 'Anonymous';
                          final String content =
                              (data['content'] as String?) ?? '';
                          final Timestamp? timestamp =
                              data['createdAt'] as Timestamp?;
                          final DateTime time =
                              timestamp?.toDate() ?? DateTime.now();

                          final isCommentOwner = currentUserId.isNotEmpty &&
                              authorId == currentUserId;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.mintGreen
                                      .withValues(alpha: 0.2),
                                  child: Text(
                                    authorName.isNotEmpty
                                        ? authorName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: AppColors.midGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            authorName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatCommentTime(time),
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        content,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCommentOwner)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 16, color: Colors.redAccent),
                                    padding: EdgeInsets.zero,
                                    onPressed: () async {
                                      await FirebaseFirestore.instance
                                          .collection(log.isArchived
                                              ? 'archived_trip_logs'
                                              : 'trip_logs')
                                          .doc(log.tripId)
                                          .collection('comments')
                                          .doc(commentId)
                                          .delete();
                                    },
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextField(
                          controller: commentController,
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 13.5),
                          decoration: const InputDecoration(
                            hintText: 'Write a comment...',
                            hintStyle:
                                TextStyle(color: Colors.grey, fontSize: 12.5),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.midGreen),
                      onPressed: () async {
                        final commentText = commentController.text.trim();
                        if (commentText.isEmpty) return;

                        if (currentUserId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Please log in to post comments.')),
                          );
                          return;
                        }

                        commentController.clear();
                        await FirebaseFirestore.instance
                            .collection(log.isArchived
                                ? 'archived_trip_logs'
                                : 'trip_logs')
                            .doc(log.tripId)
                            .collection('comments')
                            .add({
                          'authorId': currentUserId,
                          'authorName': currentUserName,
                          'content': commentText,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ));
      },
    );
  }

  String _formatCommentTime(DateTime dateTime) {
    final duration = DateTime.now().difference(dateTime);
    if (duration.inMinutes < 1) {
      return 'just now';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ago';
    } else if (duration.inHours < 24) {
      return '${duration.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Future<void> _navigateToEditor() async {
    await context.push('/editor');
    if (!mounted) return;
    final authState = context.read<AuthCubit>().state;
    if (authState is Authenticated) {
      _feedCubit.loadFeed(authState.profile);
    } else {
      _feedCubit.loadFeed(ExplorerProfile(
        uid: 'explorer_user',
        displayName: 'Guest Explorer',
        explorerScore:
            const ExplorerScore(value: 0, tier: TrustTier.unverified),
        tier: TrustTier.unverified,
        badges: const [],
        division: 'Dhaka',
        createdAt: DateTime.now(),
      ));
    }
  }

  // Helper buttons in hero bar
  Widget _buildIconButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildIconButtonWithDot(
      {required IconData icon,
      required bool hasNotification,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          if (hasNotification)
            Positioned(
              top: -1,
              right: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4A261),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.transparent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF4A261).withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- 2. SUB NAVIGATION PILL TABS ---
  Widget _buildSubNavigation() {
    final tabs = [
      {'label': '🧭 Discover', 'key': 'Discover'},
      {'label': '📍 Near me', 'key': 'Near me'},
      {'label': 'Saved', 'key': 'Saved'},
      {'label': '🗺 Divisions', 'key': 'Divisions'},
      {'label': '🔥 Trending', 'key': 'Trending'},
      {'label': '📦 Archive', 'key': 'Archive'}
    ];
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isSelected = _selectedTab == tab['key'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: GestureDetector(
              onTap: () => _selectTab(tab['key']!),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1B4332) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1B4332)
                        : const Color(0xFFECEAE4),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF1B4332).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [
                          const BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          )
                        ],
                ),
                child: Center(
                  child: Text(
                    tab['label']!,
                    style: TextStyle(
                      color:
                          isSelected ? Colors.white : const Color(0xFF5A5A5A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- FACEBOOK-STYLE COMPOSER & FEED ---

  Widget _buildCreatePostComposer(String displayName, String uid) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECEAE4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF1B4332),
                child: Text(
                  displayName.isNotEmpty
                      ? displayName.substring(0, 1).toUpperCase()
                      : 'G',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _navigateToEditor,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F2F5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Share your travel experience, $displayName...",
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 2),
            child: Divider(height: 1, color: Color(0xFFECEAE4)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TextButton.icon(
                onPressed: _navigateToEditor,
                icon: const Icon(Icons.edit_note,
                    color: Color(0xFFE76F51), size: 18),
                label: const Text('Write Log',
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: _navigateToEditor,
                icon: const Icon(Icons.add_photo_alternate,
                    color: Color(0xFF40916C), size: 18),
                label: const Text('Photo/Video',
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: () => context.push('/map'),
                icon: const Icon(Icons.location_on,
                    color: Color(0xFFFFD166), size: 18),
                label: const Text('Check-in',
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Loads the next page when the main scroll view nears its end.
  bool _onFeedScroll(ScrollNotification notification) {
    // Horizontal carousels inside the feed report with depth > 0.
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification.metrics.extentAfter > 900) {
      return false;
    }
    if (_selectedTab == 'Discover') {
      _feedCubit.loadMore();
    } else if (_selectedTab == 'Archive') {
      _feedCubit.loadArchived(more: true);
    }
    return false;
  }

  void _selectTab(String tab) {
    setState(() => _selectedTab = tab);
    if (tab == 'Saved') {
      _feedCubit.loadSaved(_savedLogs.toList().reversed.toList());
    } else if (tab == 'Archive') {
      _feedCubit.loadArchived();
    }
  }

  /// Every searchable string of [log], lower-cased once and reused.
  String _searchTextFor(TripLog log) {
    return _searchTextCache.putIfAbsent(log.tripId, () {
      final parts = <String>[log.title, log.district, log.division];
      for (final block in log.blocks) {
        final text = block.when(
          text: (_, content, __) => content,
          image: (_, __, caption, ___) => caption,
          video: (_, __, caption, ___) => caption,
          costEntry: (_, __, ___) => null,
          route: (_, __, desc) => desc,
          safetyNote: (_, text, __) => text,
          voiceNote: (_, __, ___, ____, transcript) => transcript,
        );
        if (text != null && text.isNotEmpty) parts.add(text);
      }
      // Newline-separated so a query can't match across two fields.
      return parts.join('\n').toLowerCase();
    });
  }

  Widget _buildTripLogSliverList(List<TripLog> logs) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) =>
            _buildFacebookStyleTripLogCard(logs[index]),
      ),
    );
  }

  Widget _buildPagingFooter({
    required bool isLoading,
    required bool hasMore,
    required VoidCallback onLoadMore,
    String label = 'Load more',
  }) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: Color(0xFF52B788)),
          ),
        ),
      );
    }
    if (!hasMore) return const SizedBox.shrink();
    return Center(
      child: TextButton(
        onPressed: onLoadMore,
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF40916C), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFacebookFeedSliver() {
    return BlocBuilder<FeedCubit, FeedState>(
      bloc: _feedCubit,
      builder: (context, state) {
        if (state is FeedLoading || state is FeedInitial) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FeedListSkeleton(count: 3),
            ),
          );
        }

        if (state is FeedError) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load feed: ${state.message}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (state is FeedLoaded) {
          final query = _searchQuery.trim().toLowerCase();
          final filteredLogs = state.logs
              .where((log) =>
                  !log.isArchived &&
                  (query.isEmpty || _searchTextFor(log).contains(query)))
              .toList();

          final footer = SliverToBoxAdapter(
            child: _buildPagingFooter(
              isLoading: state.isLoadingMore,
              hasMore: state.hasMore,
              onLoadMore: _feedCubit.loadMore,
              label: query.isEmpty ? 'Load more' : 'Search older posts',
            ),
          );

          if (filteredLogs.isEmpty) {
            return SliverMainAxisGroup(slivers: [
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text(
                      'No matching trip logs found.',
                      style: TextStyle(color: Color(0xFFAEABA4), fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              footer,
            ]);
          }

          return SliverMainAxisGroup(slivers: [
            _buildTripLogSliverList(filteredLogs),
            footer,
          ]);
        }

        return const SliverToBoxAdapter(child: SizedBox.shrink());
      },
    );
  }

  // Fetch author profile with in-memory caching to avoid repeated Firestore calls
  /// One shared future per author: repeated builds and many posts by the
  /// same author all wait on a single Firestore read.
  Future<Map<String, String>> _fetchAuthorProfile(String authorId) =>
      _profileFutures.putIfAbsent(authorId, () => _loadAuthorProfile(authorId));

  Future<Map<String, String>> _loadAuthorProfile(String authorId) async {
    if (_profileCache.containsKey(authorId)) {
      return _profileCache[authorId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(authorId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final profile = {
          'displayName':
              (data['displayName'] as String?)?.trim().isNotEmpty == true
                  ? data['displayName'] as String
                  : 'Explorer',
          'avatarUrl': (data['avatarUrl'] as String?) ?? '',
        };
        _profileCache[authorId] = profile;
        return profile;
      }
    } catch (_) {}
    final fallback = {'displayName': 'Explorer', 'avatarUrl': ''};
    _profileCache[authorId] = fallback;
    return fallback;
  }

  Widget _buildAvatarWidget(
      String authorId, String avatarUrl, String name, String initials) {
    final displayInitials = name.isNotEmpty
        ? name
            .split(' ')
            .map((e) => e.isNotEmpty ? e[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : initials;
    return GestureDetector(
      onTap: () {
        if (authorId.isNotEmpty) {
          context.push('/profile/$authorId');
        }
      },
      child: CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFF40916C),
        backgroundImage: avatarUrl.isNotEmpty
            ? sizedImage(
                CachedNetworkImageProvider(
                  avatarUrl,
                  errorListener: (dynamic error) {},
                ),
                context.decodeWidth(36))
            : null,
        child: avatarUrl.isEmpty
            ? Text(
                displayInitials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              )
            : null,
      ),
    );
  }

  Widget _buildAuthorNameWidget(
      String authorId, String name, bool isPremiumGuide) {
    return GestureDetector(
      onTap: () {
        if (authorId.isNotEmpty) {
          context.push('/profile/$authorId');
        }
      },
      child: Row(
        children: [
          Text(
            name,
            style: const TextStyle(
              color: Color(0xFF181818),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          if (isPremiumGuide) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Colors.blue, size: 14),
          ],
        ],
      ),
    );
  }

  Future<String?> _fetchMyReaction(String tripId) =>
      _myReactionFutures.putIfAbsent(tripId, () => _loadMyReaction(tripId));

  Future<String?> _loadMyReaction(String tripId) async {
    if (_myReactionsCache.containsKey(tripId)) {
      return _myReactionsCache[tripId];
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('trip_logs')
          .doc(tripId)
          .collection('reactions')
          .doc(currentUid)
          .get();
      if (doc.exists && doc.data() != null) {
        final reaction = doc.data()!['reactionKey'] as String?;
        _myReactionsCache[tripId] = reaction;
        return reaction;
      }
    } catch (_) {}
    _myReactionsCache[tripId] = null;
    return null;
  }

  Widget _buildFacebookStyleTripLogCard(TripLog log) {
    final totalCost =
        log.costItems.fold<int>(0, (acc, item) => acc + item.amountBDT);
    final hasSaved = _savedLogs.contains(log.tripId);
    final initials = log.authorId.isNotEmpty
        ? log.authorId.substring(0, 2).toUpperCase()
        : 'EX';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return GestureDetector(
      onTap: () => _showTripLogDetailSheet(context, log),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFECEAE4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Post Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  // Author avatar → tap to open profile
                  _profileCache.containsKey(log.authorId)
                      ? _buildAvatarWidget(
                          log.authorId,
                          _profileCache[log.authorId]!['avatarUrl'] ?? '',
                          _profileCache[log.authorId]!['displayName'] ?? '',
                          initials,
                        )
                      : FutureBuilder<Map<String, String>>(
                          future: _fetchAuthorProfile(log.authorId),
                          builder: (context, snapshot) {
                            final avatarUrl = snapshot.data?['avatarUrl'] ?? '';
                            final name = snapshot.data?['displayName'] ?? '';
                            return _buildAvatarWidget(
                                log.authorId, avatarUrl, name, initials);
                          },
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Author name — fetched dynamically, tappable to open profile
                        _profileCache.containsKey(log.authorId)
                            ? _buildAuthorNameWidget(
                                log.authorId,
                                _profileCache[log.authorId]!['displayName'] ??
                                    'Explorer',
                                log.isPremiumGuide,
                              )
                            : FutureBuilder<Map<String, String>>(
                                future: _fetchAuthorProfile(log.authorId),
                                builder: (context, snapshot) {
                                  final name = snapshot.data?['displayName'] ??
                                      'Explorer';
                                  return _buildAuthorNameWidget(
                                      log.authorId, name, log.isPremiumGuide);
                                },
                              ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _timeAgo(log.publishedAt ?? log.lastConfirmed),
                              style: const TextStyle(
                                  color: Colors.black38, fontSize: 10.5),
                            ),
                            const Text(' · ',
                                style: TextStyle(
                                    color: Colors.black38, fontSize: 10.5)),
                            const Icon(Icons.public,
                                color: Colors.black38, size: 10.5),
                            if (log.district.isNotEmpty ||
                                log.division.isNotEmpty) ...[
                              const Text(' · ',
                                  style: TextStyle(
                                      color: Colors.black38, fontSize: 10.5)),
                              Text(
                                log.district.isNotEmpty
                                    ? log.district
                                    : log.division,
                                style: const TextStyle(
                                    color: Color(0xFF40916C),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Trust/XP Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text('🧭', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                        Text(
                          '${log.trustScore} XP',
                          style: const TextStyle(
                              color: Color(0xFF1B4332),
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                log.title,
                style: const TextStyle(
                  color: Color(0xFF181818),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),

            // Post Body — video thumbnail hero + short text preview
            _buildFeedCardBody(log),

            // Cost Summary if available
            if (totalCost > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9F4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD8EFE2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money_rounded,
                          color: Color(0xFF2D6A4F), size: 16),
                      const SizedBox(width: 4),
                      const Text('Total Budget:',
                          style: TextStyle(
                              color: Color(0xFF1B4332),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('BDT $totalCost',
                          style: const TextStyle(
                              color: Color(0xFF1B4332),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),

            // Travel-specific Reactions Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: currentUid == null
                  ? EntryReactionsWidget(
                      reactions: log.reactions,
                      myReaction: null,
                      onReact: (_) {},
                    )
                  : _myReactionsCache.containsKey(log.tripId)
                      ? EntryReactionsWidget(
                          reactions: log.reactions,
                          myReaction: _myReactionsCache[log.tripId],
                          onReact: (key) => _handleReaction(log, key),
                        )
                      : FutureBuilder<String?>(
                          future: _fetchMyReaction(log.tripId),
                          builder: (context, snapshot) {
                            final myReaction = snapshot.data;
                            return EntryReactionsWidget(
                              reactions: log.reactions,
                              myReaction: myReaction,
                              onReact: (key) => _handleReaction(log, key),
                            );
                          },
                        ),
            ),

            const Divider(height: 1, color: Color(0xFFECEAE4)),

            // Footer Action Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _showCommentsBottomSheet(context, log),
                    icon: const Icon(Icons.mode_comment_outlined,
                        color: Colors.black54, size: 16),
                    label: const Text(
                      'Comment',
                      style: TextStyle(
                          color: Colors.black87,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Container(height: 16, width: 1, color: const Color(0xFFECEAE4)),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _toggleSaveLog(log.tripId),
                    icon: Icon(
                      hasSaved ? Icons.bookmark : Icons.bookmark_border,
                      color:
                          hasSaved ? const Color(0xFFE76F51) : Colors.black54,
                      size: 16,
                    ),
                    label: Text(
                      hasSaved ? 'Saved' : 'Save',
                      style: TextStyle(
                        color:
                            hasSaved ? const Color(0xFFE76F51) : Colors.black87,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Feed card body: thumbnail + 3-line text preview ───────────────────
  Widget _buildFeedCardBody(TripLog log) {
    // Find first video or image block to use as hero thumbnail
    VideoBlock? firstVideo;
    ImageBlock? firstImage;
    String? shortText;

    for (final block in log.blocks) {
      if (block is VideoBlock && firstVideo == null) firstVideo = block;
      if (block is ImageBlock && firstImage == null) firstImage = block;
      if (block is TextBlock &&
          shortText == null &&
          block.content.trim().isNotEmpty) {
        shortText = block.content.trim();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero: YouTube thumbnail or image ──
        if (firstVideo != null) ...[
          _buildFeedVideoHero(firstVideo)
        ] else if (firstImage != null) ...[
          Builder(builder: (context) {
            final img = firstImage!;
            final String heroTag = 'feed_${log.tripId}_${img.storageUrl}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => FullScreenImageViewer(
                        imageUrl: img.storageUrl,
                        heroTag: heroTag,
                        localPath: img.localPath,
                        caption: img.caption,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.zero,
                    topRight: Radius.zero,
                    bottomLeft: Radius.circular(0),
                    bottomRight: Radius.circular(0),
                  ),
                  child: Hero(
                    tag: heroTag,
                    child: BlurHashImage(
                      imageUrl: img.storageUrl,
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],

        // ── Short text preview ──
        if (shortText != null && shortText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortText,
                  style: const TextStyle(
                      fontSize: 13.5, color: Colors.black87, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showTripLogDetailSheet(context, log),
                  child: const Text(
                    'Read more…',
                    style: TextStyle(
                      color: Color(0xFF40916C),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Feed video hero — shows YouTube thumbnail, tap to play inline
  Widget _buildFeedVideoHero(VideoBlock block) {
    final videoId = _getYouTubeId(block.storageUrl) ?? '';
    if (videoId.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RepaintBoundary(
        child: InAppYoutubePlayer(
          videoUrl: block.storageUrl,
          caption: block.caption,
          previewMode: true,
        ),
      ),
    );
  }

  // --- 5. SYNC BAR (dynamic – displays actual pending outbox sync count) ---
  Widget _buildSyncBar() {
    return FutureBuilder<Box<dynamic>>(
      future: _syncOutboxBox,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final box = snapshot.data!;
        return ValueListenableBuilder<Box<dynamic>>(
          valueListenable: box.listenable(),
          builder: (context, listenableBox, child) {
            final count = listenableBox.length;
            if (count == 0) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B4332), Color(0xFF2D6A4F)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF74C69D).withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1B4332).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  const BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const _SyncPulseOrb(),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$count pending updates syncing',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Operations enqueued in offline mode · Uploading automatically',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- 6. FEATURED TRIPLOGS SECTION (fully dynamic from FeedCubit) ---
  Widget _buildFeaturedTripLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  CircleAvatar(radius: 3.5, backgroundColor: Color(0xFF1B4332)),
                  SizedBox(width: 7),
                  Text(
                    'Featured TripLogs',
                    style: TextStyle(
                      color: Color(0xFF181818),
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              BlocBuilder<FeedCubit, FeedState>(
                bloc: _feedCubit,
                builder: (context, state) {
                  final logs = state is FeedLoaded
                      ? state.logs.where((l) => !l.isArchived).toList()
                      : <TripLog>[];
                  return GestureDetector(
                    onTap: () {
                      if (logs.isNotEmpty) {
                        _showAllFeaturedTripLogsSheet(context, logs);
                      }
                    },
                    child: const Row(
                      children: [
                        Text(
                          'See all ',
                          style: TextStyle(
                            color: Color(0xFF40916C),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Color(0xFF40916C), size: 12),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        SizedBox(
          height: 265,
          child: BlocBuilder<FeedCubit, FeedState>(
            bloc: _feedCubit,
            builder: (context, state) {
              if (state is FeedLoading || state is FeedInitial) {
                return const HorizontalCardsSkeleton(
                    cardWidth: 240, cardHeight: 200);
              }

              if (state is FeedError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load feed: ${state.message}',
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (state is FeedLoaded) {
                final activeLogs =
                    state.logs.where((l) => !l.isArchived).toList();
                if (activeLogs.isNotEmpty) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    itemCount: activeLogs.length,
                    itemBuilder: (context, index) {
                      final log = activeLogs[index];
                      return _buildDynamicTripLogCard(log);
                    },
                  );
                }
              }

              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No trip logs yet — be the first explorer!',
                    style: TextStyle(color: Color(0xFFAEABA4), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Dynamic TripLog card builder (no static data)
  Widget _buildDynamicTripLogCard(TripLog log) {
    final totalCost =
        log.costItems.fold<int>(0, (acc, item) => acc + item.amountBDT);
    // Derive tier based on trustScore or isPremiumGuide flag
    final isPremium = log.trustScore > 70;
    final tier = isPremium ? '★ Pioneer' : '✓ Community';
    final tierClass = isPremium ? 'pioneer' : 'community';
    final gradientColors = isPremium
        ? [const Color(0xFFE76F51), const Color(0xFFA83B24)]
        : [const Color(0xFF163020), const Color(0xFF2B5535)];

    String? thumbnailUrl;
    for (final block in log.blocks) {
      if (block is ImageBlock) {
        thumbnailUrl = block.storageUrl;
        break;
      } else if (block is VideoBlock) {
        final vId = _getYouTubeId(block.storageUrl) ?? '';
        if (vId.isNotEmpty) {
          thumbnailUrl = 'https://img.youtube.com/vi/$vId/hqdefault.jpg';
        }
        break;
      }
    }

    return GestureDetector(
      onTap: () => _showTripLogDetailSheet(context, log),
      child: _buildFeaturedTripLogCard(
        tripId: log.tripId,
        authorId: log.authorId,
        tripTitle: log.title,
        emoji: isPremium ? '⭐' : '🗺',
        gradientColors: gradientColors,
        tier: tier,
        tierClass: tierClass,
        timeAgo: _timeAgo(log.lastConfirmed),
        location: log.district.isNotEmpty ? log.district : log.division,
        rating: '4.8',
        title: log.title,
        cost: totalCost > 0 ? 'BDT $totalCost total' : 'Cost not listed',
        authorInitials: log.authorId.isNotEmpty
            ? log.authorId.substring(0, 2).toUpperCase()
            : 'EX',
        authorColor:
            isPremium ? const Color(0xFFE76F51) : const Color(0xFF40916C),
        authorName: 'Explorer',
        likes: log.helpfulVotes.toString(),
        pins: log.trustScore.toString(),
        isArchived: log.isArchived,
        thumbnailUrl: thumbnailUrl,
      ),
    );
  }

  // Delegates to the shared extractor from in_app_youtube_player.dart
  String? _getYouTubeId(String url) => extractYouTubeId(url);

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  Widget _buildAuthorWidget(
      String authorId, Color fallbackColor, String fallbackInitials) {
    return FutureBuilder<Map<String, String>>(
      future:
          _fetchAuthorProfile(authorId.isEmpty ? 'explorer_user' : authorId),
      builder: (context, snapshot) {
        final name = snapshot.data?['displayName'] ?? 'Explorer';
        final avatarUrl = snapshot.data?['avatarUrl'] ?? '';
        final initials = name.isNotEmpty
            ? name
                .split(' ')
                .map((e) => e.isNotEmpty ? e[0] : '')
                .take(2)
                .join()
                .toUpperCase()
            : fallbackInitials;
        return GestureDetector(
          onTap: () {
            if (authorId.isNotEmpty && authorId != 'explorer_user') {
              context.push('/profile/$authorId');
            }
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: fallbackColor,
                backgroundImage: avatarUrl.isNotEmpty
                    ? sizedImage(
                        CachedNetworkImageProvider(
                          avatarUrl,
                          errorListener: (dynamic error) {},
                        ),
                        context.decodeWidth(22))
                    : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: const TextStyle(
                  color: Color(0xFFAEABA4),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeaturedTripLogCard({
    required String tripId,
    required String authorId,
    required String tripTitle,
    required String emoji,
    required List<Color> gradientColors,
    required String tier,
    required String tierClass,
    required String timeAgo,
    required String location,
    required String rating,
    required String title,
    required String cost,
    required String authorInitials,
    required Color authorColor,
    required String authorName,
    required String likes,
    required String pins,
    required bool isArchived,
    String? thumbnailUrl,
  }) {
    Color tierBg;
    Color tierText;
    if (tierClass == 'pioneer') {
      tierBg = const Color(0xFFE76F51).withValues(alpha: 0.92);
      tierText = Colors.white;
    } else if (tierClass == 'verified') {
      tierBg = const Color(0xFFFFD166).withValues(alpha: 0.92);
      tierText = const Color(0xFF4A1B0C);
    } else {
      tierBg = const Color(0xFF1D9E75).withValues(alpha: 0.92);
      tierText = Colors.white;
    }

    final authState = context.read<AuthCubit>().state;
    final currentUid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    final currentName = authState is Authenticated
        ? authState.profile.displayName
        : 'An explorer';
    final docId = '${currentUid}_$tripId';

    return Container(
      width: 214,
      margin: const EdgeInsets.only(right: 14, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 36,
            offset: Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top image block
          SizedBox(
            height: 148,
            child: Stack(
              children: [
                // Background Image or Gradient
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(22)),
                    child: (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                        ? BlurHashImage(
                            imageUrl: thumbnailUrl,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                  ),
                ),
                // Vignette at bottom
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(22)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),

                // Central Emoji (only if no thumbnail)
                if (thumbnailUrl == null || thumbnailUrl.isEmpty)
                  Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(
                        fontSize: 60,
                        shadows: [
                          Shadow(
                              color: Colors.black38,
                              blurRadius: 10,
                              offset: Offset(0, 4)),
                        ],
                      ),
                    ),
                  ),

                // Top-Left Badge (Tier)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tierBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tier,
                      style: TextStyle(
                        color: tierText,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Top-Right Badge (Age)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeAgo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                // Bottom-Left (Location)
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white, size: 11),
                      const SizedBox(width: 3),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom-Right (Rating)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD166).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Text('★',
                            style: TextStyle(
                                color: Color(0xFF3A1000), fontSize: 10)),
                        const SizedBox(width: 2),
                        Text(
                          rating,
                          style: const TextStyle(
                            color: Color(0xFF3A1000),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF181818),
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 6),

                // Cost Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF5EE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_money_rounded,
                          size: 11, color: Color(0xFF1B4332)),
                      const SizedBox(width: 2),
                      Text(
                        cost,
                        style: const TextStyle(
                          color: Color(0xFF1B4332),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),

                // Footer Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Author Avatar & Name (dynamically fetched from profile)
                    _buildAuthorWidget(authorId, authorColor, authorInitials),

                    // Likes & Pins
                    Row(
                      children: [
                        StreamBuilder<DocumentSnapshot>(
                          stream: _likeStreams.putIfAbsent(
                              docId,
                              () => _shared(FirebaseFirestore.instance
                                  .collection('likes')
                                  .doc(docId))),
                          builder: (context, snapshot) {
                            final isLiked = snapshot.data?.exists ?? false;
                            return GestureDetector(
                              onTap: () async {
                                final ref = FirebaseFirestore.instance
                                    .collection('likes')
                                    .doc(docId);
                                final logRef = FirebaseFirestore.instance
                                    .collection(isArchived
                                        ? 'archived_trip_logs'
                                        : 'trip_logs')
                                    .doc(tripId);

                                if (isLiked) {
                                  await ref.delete();
                                  await FirebaseFirestore.instance
                                      .runTransaction((transaction) async {
                                    final sfDoc = await transaction.get(logRef);
                                    if (sfDoc.exists) {
                                      final currentVotes =
                                          sfDoc.data()?['helpfulVotes']
                                                  as int? ??
                                              0;
                                      transaction.update(logRef, {
                                        'helpfulVotes': currentVotes > 0
                                            ? currentVotes - 1
                                            : 0
                                      });
                                    }
                                  });
                                } else {
                                  await ref.set({
                                    'userId': currentUid,
                                    'tripId': tripId,
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });
                                  await FirebaseFirestore.instance
                                      .runTransaction((transaction) async {
                                    final sfDoc = await transaction.get(logRef);
                                    if (sfDoc.exists) {
                                      final currentVotes =
                                          sfDoc.data()?['helpfulVotes']
                                                  as int? ??
                                              0;
                                      transaction.update(logRef,
                                          {'helpfulVotes': currentVotes + 1});
                                    }
                                  });

                                  if (currentUid != authorId &&
                                      authorId.isNotEmpty) {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(authorId)
                                        .collection('notifications')
                                        .add({
                                      'title': 'New Like!',
                                      'body':
                                          '$currentName liked your TripLog: "$tripTitle".',
                                      'action': 'helpful_vote',
                                      'itemId': tripId,
                                      'uid': currentUid,
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });
                                  }
                                }
                              },
                              child: Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isLiked
                                    ? Colors.redAccent
                                    : const Color(0xFF74C69D),
                                size: 13,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 3),
                        Text(
                          likes,
                          style: const TextStyle(
                              color: Color(0xFFAEABA4), fontSize: 10.5),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on_outlined,
                            color: Color(0xFF74C69D), size: 12),
                        const SizedBox(width: 3),
                        Text(
                          pins,
                          style: const TextStyle(
                              color: Color(0xFFAEABA4), fontSize: 10.5),
                        ),
                        const SizedBox(width: 8),
                        StreamBuilder<DocumentSnapshot>(
                          stream: _logDocStreams.putIfAbsent(
                              tripId,
                              () => _shared(FirebaseFirestore.instance
                                  .collection('trip_logs')
                                  .doc(tripId))),
                          builder: (context, snapshot) {
                            final data =
                                snapshot.data?.data() as Map<String, dynamic>?;
                            final viewsCount = data?['views'] as int? ?? 0;
                            return Row(
                              children: [
                                const Icon(Icons.visibility_outlined,
                                    color: Color(0xFF74C69D), size: 11),
                                const SizedBox(width: 3),
                                Text(
                                  viewsCount.toString(),
                                  style: const TextStyle(
                                      color: Color(0xFFAEABA4), fontSize: 10.5),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recordInteraction(TripLog log) async {
    try {
      final encryptionService = getIt<HiveEncryptionService>();
      final box =
          await encryptionService.openEncryptedBox<dynamic>('user_preferences');

      // Update implicit division interest
      final divisionKey = 'interest_div_${log.division.toLowerCase()}';
      final currentDivInterest = box.get(divisionKey, defaultValue: 0) as int;
      await box.put(divisionKey, currentDivInterest + 1);

      // Update implicit author interest
      final authorKey = 'interest_author_${log.authorId}';
      final currentAuthorInterest = box.get(authorKey, defaultValue: 0) as int;
      await box.put(authorKey, currentAuthorInterest + 1);
    } catch (_) {}
  }

  void _showPersonalizeFeedBottomSheet(BuildContext context) {
    // Opened once per sheet; setModalState rebuilds would otherwise restart
    // the FutureBuilder (and flash its loading state) on every tap.
    final prefsBoxFuture = getIt<HiveEncryptionService>()
        .openEncryptedBox<dynamic>('user_preferences');
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<Box<dynamic>>(
              future: prefsBoxFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(
                    height: 200,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D1A12),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF74C69D)),
                    ),
                  );
                }

                final box = snapshot.data!;
                final currentDivs = List<String>.from(
                    box.get('preferred_divisions', defaultValue: <String>[])
                        as List);
                final currentCats = List<String>.from(
                    box.get('preferred_categories', defaultValue: <String>[])
                        as List);

                final divisions = [
                  'Dhaka',
                  'Chittagong',
                  'Sylhet',
                  'Khulna',
                  'Barisal',
                  'Rajshahi',
                  'Rangpur',
                  'Mymensingh'
                ];

                final categories = {
                  'text': 'Text Stories',
                  'image': 'Photos & Visuals',
                  'costEntry': 'Cost Breakdowns',
                  'route': 'Maps & Routes',
                  'safetyNote': 'Safety Guides',
                };

                return Container(
                  padding: EdgeInsets.only(
                    top: 20,
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom +
                        MediaQuery.of(context).padding.bottom +
                        24,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1A12),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(
                        color: const Color(0xFF74C69D).withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4.5,
                            margin: const EdgeInsets.only(bottom: 22),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded,
                                color: Color(0xFF74C69D), size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Personalize Your Feed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Select your interests to tailor Bhromon feed to your preferences (like Facebook News Feed).',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'PREFERRED DIVISIONS',
                          style: TextStyle(
                            color: Color(0xFFF4A261),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: divisions.map((div) {
                            final isSelected = currentDivs.contains(div);
                            return FilterChip(
                              label: Text(div),
                              selected: isSelected,
                              checkmarkColor: Colors.black,
                              selectedColor: const Color(0xFF74C69D),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              labelStyle: TextStyle(
                                color:
                                    isSelected ? Colors.black : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSelected
                                      ? Colors.transparent
                                      : Colors.white12,
                                ),
                              ),
                              onSelected: (selected) async {
                                setModalState(() {
                                  if (selected) {
                                    currentDivs.add(div);
                                  } else {
                                    currentDivs.remove(div);
                                  }
                                });
                                await box.put(
                                    'preferred_divisions', currentDivs);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'PREFERRED POST CONTENT TYPE',
                          style: TextStyle(
                            color: Color(0xFFF4A261),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: categories.entries.map((entry) {
                            final key = entry.key;
                            final label = entry.value;
                            final isSelected = currentCats.contains(key);
                            return FilterChip(
                              label: Text(label),
                              selected: isSelected,
                              checkmarkColor: Colors.black,
                              selectedColor: const Color(0xFF74C69D),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              labelStyle: TextStyle(
                                color:
                                    isSelected ? Colors.black : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSelected
                                      ? Colors.transparent
                                      : Colors.white12,
                                ),
                              ),
                              onSelected: (selected) async {
                                setModalState(() {
                                  if (selected) {
                                    currentCats.add(key);
                                  } else {
                                    currentCats.remove(key);
                                  }
                                });
                                await box.put(
                                    'preferred_categories', currentCats);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF40916C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 8,
                            shadowColor:
                                const Color(0xFF40916C).withValues(alpha: 0.4),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            final authState = context.read<AuthCubit>().state;
                            final profile = authState is Authenticated
                                ? authState.profile
                                : ExplorerProfile(
                                    uid: 'explorer_user',
                                    displayName: 'Guest Explorer',
                                    explorerScore: const ExplorerScore(
                                        value: 0, tier: TrustTier.unverified),
                                    tier: TrustTier.unverified,
                                    badges: const [],
                                    division: 'Dhaka',
                                    createdAt: DateTime.now(),
                                  );
                            _feedCubit.loadFeed(profile);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        color: Color(0xFF74C69D), size: 18),
                                    SizedBox(width: 8),
                                    Text('Feed personalized successfully!'),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF1B4332),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Apply Personalization',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- TRIP LOG DETAIL SHEET ---
  void _showTripLogDetailSheet(BuildContext context, TripLog log) {
    _recordInteraction(log);
    TripLogDetailSheet.show(context, log);
  }

  void _showAllFeaturedTripLogsSheet(BuildContext context, List<TripLog> logs) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          expand: false,
          builder: (ctx, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF6F5F1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Featured TripLogs',
                          style: TextStyle(
                            color: Color(0xFF181818),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                          16, 8, 16, 32 + MediaQuery.of(ctx).padding.bottom),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final totalCost = log.costItems
                            .fold<int>(0, (acc, item) => acc + item.amountBDT);
                        final isPremium = log.trustScore > 70;
                        final tier = isPremium ? '★ Pioneer' : '✓ Community';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFECEAE4)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showTripLogDetailSheet(context, log);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isPremium
                                              ? const Color(0xFFE76F51)
                                                  .withValues(alpha: 0.1)
                                              : const Color(0xFF1D9E75)
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          tier,
                                          style: TextStyle(
                                            color: isPremium
                                                ? const Color(0xFFE76F51)
                                                : const Color(0xFF1D9E75),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _timeAgo(log.publishedAt ??
                                            log.lastConfirmed),
                                        style: const TextStyle(
                                            color: Colors.black38,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    log.title,
                                    style: const TextStyle(
                                      color: Color(0xFF181818),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined,
                                          color: Colors.grey, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        log.district.isNotEmpty
                                            ? log.district
                                            : log.division,
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12),
                                      ),
                                      const Spacer(),
                                      const Icon(Icons.wallet_outlined,
                                          color: Colors.grey, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        totalCost > 0
                                            ? 'BDT $totalCost'
                                            : 'Free',
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(
                                      height: 1, color: Color(0xFFECEAE4)),
                                  const SizedBox(height: 10),
                                  _buildAuthorWidget(
                                    log.authorId,
                                    isPremium
                                        ? const Color(0xFFE76F51)
                                        : const Color(0xFF40916C),
                                    log.authorId.isNotEmpty
                                        ? log.authorId
                                            .substring(0, 2)
                                            .toUpperCase()
                                        : 'EX',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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

  Widget _detailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // --- 7. NEARBY SPOTS (dynamic from MapBloc) ---
  Widget _buildNearbySpotsSection() {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        List<LocationPin> pins = [];
        if (state is MapPinsLoaded) {
          pins = state.pins;
        }

        if (pins.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: Text('No nearby spots found',
                    style: TextStyle(color: Color(0xFFAEABA4), fontSize: 13))),
          );
        }

        final spots = pins.map((pin) {
          String emoji = '📍';
          final nameLower = pin.name.toLowerCase();
          if (nameLower.contains('valley') ||
              nameLower.contains('hill') ||
              nameLower.contains('peak') ||
              nameLower.contains('pahar') ||
              nameLower.contains('sajek')) {
            emoji = '🏔';
          } else if (nameLower.contains('beach') ||
              nameLower.contains('sea') ||
              nameLower.contains('ocean') ||
              nameLower.contains('island')) {
            emoji = '🏖';
          } else if (nameLower.contains('swamp') ||
              nameLower.contains('forest') ||
              nameLower.contains('sundarban') ||
              nameLower.contains('garden')) {
            emoji = '🌿';
          } else if (nameLower.contains('fort') ||
              nameLower.contains('manzil') ||
              nameLower.contains('palace') ||
              nameLower.contains('heritage')) {
            emoji = '🏛';
          } else if (nameLower.contains('mosque') ||
              nameLower.contains('temple') ||
              nameLower.contains('church')) {
            emoji = '🕌';
          }

          String badge = 'C';
          Color badgeBg = const Color(0xFF40916C);
          Color tierColor = const Color(0xFF0A5E35);
          Color tierBg = const Color(0xFFE4F5EC);
          List<Color> gradient = [
            const Color(0xFF1D9E75),
            const Color(0xFF0A5C3A)
          ];

          if (pin.trustTier == TrustTier.pioneer) {
            badge = 'P';
            badgeBg = const Color(0xFFE76F51);
            tierColor = const Color(0xFFA33018);
            tierBg = const Color(0xFFFCEAE6);
            gradient = [const Color(0xFFE76F51), const Color(0xFFA83B24)];
          } else if (pin.trustTier == TrustTier.verified) {
            badge = 'V';
            badgeBg = const Color(0xFFF4A261);
            tierColor = const Color(0xFFB84D00);
            tierBg = const Color(0xFFFFF0E8);
            gradient = [const Color(0xFF4361EE), const Color(0xFF1E2FA5)];
          } else if (pin.trustTier == TrustTier.community) {
            badge = 'C';
            badgeBg = const Color(0xFF40916C);
            tierColor = const Color(0xFF0A5E35);
            tierBg = const Color(0xFFE4F5EC);
            gradient = [const Color(0xFF1D9E75), const Color(0xFF0A5C3A)];
          } else {
            badge = 'U';
            badgeBg = const Color(0xFFAEABA4);
            tierColor = const Color(0xFF555555);
            tierBg = const Color(0xFFEEEEEE);
            gradient = [const Color(0xFFAEABA4), const Color(0xFF777777)];
          }

          return {
            'emoji': emoji,
            'badge': badge,
            'badgeBg': badgeBg,
            'gradient': gradient,
            'name': pin.name,
            'dist': pin.district,
            'tier':
                '★ ${pin.trustTier.name[0].toUpperCase()}${pin.trustTier.name.substring(1)}',
            'tierColor': tierColor,
            'tierBg': tierBg,
          };
        }).toList();

        return _buildSpotsListWidget(spots);
      },
    );
  }

  Widget _buildSpotsListWidget(List<Map<String, dynamic>> spots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  CircleAvatar(radius: 3.5, backgroundColor: Color(0xFFF4A261)),
                  SizedBox(width: 7),
                  Text(
                    'Nearby Spots',
                    style: TextStyle(
                      color: Color(0xFF181818),
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => context.push('/map'),
                child: const Row(
                  children: [
                    Text(
                      'Map view ',
                      style: TextStyle(
                        color: Color(0xFF40916C),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.map_outlined,
                        color: Color(0xFF40916C), size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 16, right: 8),
            itemCount: spots.length,
            itemBuilder: (context, index) {
              final spot = spots[index];
              return GestureDetector(
                onTap: () => context.push('/map'),
                child: Container(
                  width: 108,
                  margin: const EdgeInsets.only(right: 11, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFECEAE4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Spot icon area
                      Container(
                        height: 68,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(18)),
                          gradient: LinearGradient(
                            colors: spot['gradient'] as List<Color>,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Center(
                              child: Text(
                                spot['emoji'] as String,
                                style: const TextStyle(fontSize: 30),
                              ),
                            ),
                            Positioned(
                              bottom: 5,
                              right: 5,
                              child: Container(
                                width: 19,
                                height: 19,
                                decoration: BoxDecoration(
                                  color: spot['badgeBg'] as Color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    spot['badge'] as String,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Info area
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              spot['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF181818),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 10, color: Color(0xFFAEABA4)),
                                const SizedBox(width: 2),
                                Text(
                                  spot['dist'] as String,
                                  style: const TextStyle(
                                    color: Color(0xFFAEABA4),
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: spot['tierBg'] as Color? ??
                                    const Color(0xFFE4F5EC),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                spot['tier'] as String,
                                style: TextStyle(
                                  color: spot['tierColor'] as Color? ??
                                      const Color(0xFF0A5E35),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 8. EXPLORER SPOTLIGHT (dynamic from FeedCubit) ---
  Widget _buildExplorerSpotlightSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                      radius: 3.5, backgroundColor: Color(0xFFF4A261)),
                  const SizedBox(width: 7),
                  Text(
                    'Top Explorers',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.85),
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  // Try leaderboard route; fall back to Discover tab
                  try {
                    context.push('/leaderboard');
                  } catch (_) {
                    setState(() => _selectedTab = 'Discover');
                  }
                },
                child: const Row(
                  children: [
                    Text(
                      'Leaderboard ',
                      style: TextStyle(
                        color: Color(0xFF40916C),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF40916C), size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECEAE4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: BlocBuilder<FeedCubit, FeedState>(
            bloc: _feedCubit,
            builder: (context, state) {
              if (state is FeedLoading) {
                return const HorizontalCardsSkeleton(
                    cardWidth: 150, cardHeight: 170);
              }

              List<ExplorerProfile> explorersList = [];
              if (state is FeedLoaded) {
                explorersList = state.explorers;
              }

              if (explorersList.isEmpty) {
                return const Center(
                  child: Text('No explorers yet',
                      style: TextStyle(color: Color(0xFFAEABA4), fontSize: 12)),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: explorersList.map((exp) {
                    final initials = exp.displayName
                        .split(' ')
                        .map((s) => s.isNotEmpty ? s[0] : '')
                        .take(2)
                        .join()
                        .toUpperCase();

                    List<Color> avatarColors = [
                      const Color(0xFF40916C),
                      const Color(0xFF1B4332)
                    ];
                    String pip = 'C';
                    Color pipBg = const Color(0xFF40916C);

                    if (exp.tier == TrustTier.pioneer) {
                      avatarColors = [
                        const Color(0xFFE76F51),
                        const Color(0xFFC94F34)
                      ];
                      pip = '★';
                      pipBg = const Color(0xFFE76F51);
                    } else if (exp.tier == TrustTier.verified) {
                      avatarColors = [
                        const Color(0xFFFFD166),
                        const Color(0xFFF4A261)
                      ];
                      pip = 'V';
                      pipBg = const Color(0xFFFFD166);
                    } else if (exp.tier == TrustTier.regionExpert) {
                      avatarColors = [
                        const Color(0xFF4361EE),
                        const Color(0xFF2D46B5)
                      ];
                      pip = 'E';
                      pipBg = const Color(0xFF4361EE);
                    }

                    // Each explorer card is tappable — opens their profile
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: GestureDetector(
                        onTap: () {
                          if (exp.uid.isNotEmpty) {
                            context.push('/profile/${exp.uid}');
                          }
                        },
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2.0),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: avatarColors[0], width: 2),
                                  ),
                                  child: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.transparent,
                                    backgroundImage: (exp.avatarUrl != null &&
                                            exp.avatarUrl!.isNotEmpty)
                                        ? sizedImage(
                                            CachedNetworkImageProvider(
                                              exp.avatarUrl!,
                                              errorListener: (dynamic error) {},
                                            ),
                                            context.decodeWidth(40))
                                        : null,
                                    child: (exp.avatarUrl == null ||
                                            exp.avatarUrl!.isEmpty)
                                        ? Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: avatarColors,
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                initials,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                Positioned(
                                  bottom: -1,
                                  right: -1,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: pipBg,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        pip,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              width: 64,
                              child: Text(
                                exp.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF181818),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              'Score ${exp.explorerScore.value}',
                              style: const TextStyle(
                                color: Color(0xFFAEABA4),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 11. LIVE PRO-TIPS HORIZONTAL SLIDER (dynamic from FeedCubit) ---
  Widget _buildProTipsHorizontalFeed() {
    return SizedBox(
      height: 172,
      child: BlocBuilder<FeedCubit, FeedState>(
        bloc: _feedCubit,
        builder: (context, state) {
          if (state is FeedLoading) {
            return const HorizontalCardsSkeleton(
                cardWidth: 220, cardHeight: 150);
          }

          List<ProTip> tipsList = [];
          if (state is FeedLoaded) {
            tipsList = state.tips;
          }

          if (tipsList.isEmpty) {
            return const Center(
              child: Text(
                'No live pro-tips available.',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
            );
          }

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 16, right: 8),
            itemCount: tipsList.length,
            itemBuilder: (context, index) {
              final tip = tipsList[index];

              // Map dynamic category to tag properties
              String tag = 'General';
              Color tagBg = const Color(0xFFEEEEEE);
              Color tagText = const Color(0xFF555555);
              IconData tagIcon = Icons.tips_and_updates_outlined;

              final cat = tip.category.toLowerCase();
              if (cat == 'transport') {
                tag = 'Transport';
                tagBg = const Color(0xFFE1F5EE);
                tagText = const Color(0xFF0A5040);
                tagIcon = Icons.directions_bus_outlined;
              } else if (cat == 'food') {
                tag = 'Food';
                tagBg = const Color(0xFFFDF3E3);
                tagText = const Color(0xFF7A3E00);
                tagIcon = Icons.restaurant_menu_rounded;
              } else if (cat == 'safety') {
                tag = 'Safety';
                tagBg = const Color(0xFFFEECEC);
                tagText = const Color(0xFF9E1414);
                tagIcon = Icons.warning_amber_rounded;
              } else if (cat == 'route') {
                tag = 'Route';
                tagBg = const Color(0xFFEEF0FF);
                tagText = const Color(0xFF323CB8);
                tagIcon = Icons.alt_route_rounded;
              } else if (cat == 'accommodation' || cat == 'stay') {
                tag = 'Stay';
                tagBg = const Color(0xFFFEF6E7);
                tagText = const Color(0xFF8A4200);
                tagIcon = Icons.hotel_outlined;
              } else if (cat == 'heritage') {
                tag = 'Heritage';
                tagBg = const Color(0xFFF4F0FF);
                tagText = const Color(0xFF5B3CB8);
                tagIcon = Icons.museum_outlined;
              }

              // Determine decay status and freshness styling
              Color decayColor = const Color(0xFF1D9E75); // fresh = green
              bool isStale = false;

              final ageDays =
                  DateTime.now().difference(tip.lastConfirmed).inDays;
              if (ageDays > 60 || tip.outdatedVotes > 5) {
                decayColor = const Color(0xFFE24B4A); // stale = red
                isStale = true;
              } else if (ageDays > 14 || tip.outdatedVotes > 1) {
                decayColor = const Color(0xFFF4A261); // aging = amber
              }

              final timeAgoStr = ageDays == 0
                  ? 'Today'
                  : (ageDays == 1 ? 'Yesterday' : '$ageDays days ago');

              return GestureDetector(
                onTap: () => _showProTipDetailSheet(context, tip),
                child: Container(
                  width: 166,
                  margin: const EdgeInsets.only(right: 11, bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFECEAE4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Category Chip
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: tagBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(tagIcon, size: 10, color: tagText),
                                const SizedBox(width: 4),
                                Text(
                                  tag,
                                  style: TextStyle(
                                    color: tagText,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Mini Decay Circle
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: decayColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Stale warning if needed
                      if (isStale)
                        Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFE24B4A).withValues(alpha: 0.07),
                            border: Border.all(
                                color: const Color(0xFFE24B4A)
                                    .withValues(alpha: 0.2)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  size: 11, color: Color(0xFFE24B4A)),
                              SizedBox(width: 5),
                              Text(
                                'Tap to re-confirm',
                                style: TextStyle(
                                  color: Color(0xFFE24B4A),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Tip body text
                      Expanded(
                        child: Text(
                          tip.text,
                          maxLines: isStale ? 2 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2B2B2B),
                            fontSize: 10.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Metadata footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            timeAgoStr,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.4),
                              fontSize: 8,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(Icons.thumb_up_alt_outlined,
                                  size: 9,
                                  color: Colors.black.withValues(alpha: 0.4)),
                              const SizedBox(width: 3),
                              Text(
                                '${tip.helpfulVotes}',
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Pro-Tip full detail bottom sheet
  void _showProTipDetailSheet(BuildContext context, ProTip tip) {
    final ageDays = DateTime.now().difference(tip.lastConfirmed).inDays;
    final timeAgoStr = ageDays == 0
        ? 'Today'
        : (ageDays == 1 ? 'Yesterday' : '$ageDays days ago');
    Color decayColor = const Color(0xFF1D9E75);
    String freshnessLabel = 'Fresh';
    if (ageDays > 60 || tip.outdatedVotes > 5) {
      decayColor = const Color(0xFFE24B4A);
      freshnessLabel = 'Possibly outdated';
    } else if (ageDays > 14 || tip.outdatedVotes > 1) {
      decayColor = const Color(0xFFF4A261);
      freshnessLabel = 'Aging';
    }

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF6F5F1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                          16, 8, 16, 32 + MediaQuery.of(ctx).padding.bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Category + freshness row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF5EE),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  tip.category.isNotEmpty
                                      ? tip.category
                                      : 'General',
                                  style: const TextStyle(
                                      color: Color(0xFF1B4332),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: decayColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Text(freshnessLabel,
                                  style: TextStyle(
                                      color: decayColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Text(timeAgoStr,
                                  style: const TextStyle(
                                      color: Colors.black38, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Tip body
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFECEAE4)),
                            ),
                            child: Text(
                              tip.text,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Color(0xFF2B2B2B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Location + helpful votes
                          Row(
                            children: [
                              _detailChip(
                                  Icons.location_on,
                                  tip.locationPinId.isNotEmpty
                                      ? tip.locationPinId
                                      : 'General',
                                  const Color(0xFF40916C)),
                              const SizedBox(width: 8),
                              _detailChip(
                                  Icons.thumb_up,
                                  '${tip.helpfulVotes} helpful',
                                  const Color(0xFF4361EE)),
                              const SizedBox(width: 8),
                              _detailChip(
                                  Icons.warning_amber_rounded,
                                  '${tip.outdatedVotes} outdated',
                                  const Color(0xFFE76F51)),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Author info
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFECEAE4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline,
                                    color: Color(0xFF40916C), size: 18),
                                const SizedBox(width: 10),
                                FutureBuilder<Map<String, String>>(
                                  future: _fetchAuthorProfile(tip.authorId),
                                  builder: (context, snapshot) {
                                    final name =
                                        snapshot.data?['displayName'] ??
                                            'Explorer';
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        if (tip.authorId.isNotEmpty) {
                                          context
                                              .push('/profile/${tip.authorId}');
                                        }
                                      },
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          color: Color(0xFF1B4332),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
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
      },
    );
  }

  // --- 12. GLASSMORPHIC BOTTOM NAV BAR & FAB ---
  Widget _buildCustomBottomNavigationBar(String uid) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double navHeight = 68.0 + bottomPadding;

    return Container(
      height: navHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 40,
            offset: const Offset(0, -16),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // 1. Discover Icon (active when Discover tab is selected)
            _buildBottomNavItem(
              icon: Icons.explore,
              label: 'Discover',
              isActive: _selectedTab == 'Discover',
              onTap: () {
                if (_selectedTab != 'Discover') {
                  _selectTab('Discover');
                } else if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  );
                }
              },
            ),

            // 2. Map Icon
            _buildBottomNavItem(
              icon: Icons.map_outlined,
              label: 'Map',
              isActive: false,
              onTap: () => context.push('/map'),
            ),

            // 3. Post Icon (unified with other nav items)
            _buildBottomNavItem(
              icon: Icons.add_circle_outline,
              label: 'Post',
              isActive: false,
              onTap: () => _showCreateDialog(context),
            ),

            // 4. Inbox Icon (no static badge)
            _buildBottomNavItem(
              icon: Icons.chat_bubble_outline,
              label: 'Inbox',
              isActive: false,
              onTap: () => context.push('/chats'),
            ),

            // 5. Profile Icon
            _buildBottomNavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              isActive: false,
              onTap: () {
                final targetUid = uid.isNotEmpty ? uid : 'explorer_user';
                _showProfileNavigationMenu(context, targetUid);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileNavigationMenu(BuildContext context, String uid) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.95,
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: 24 + MediaQuery.of(ctx).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1A12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
                color: const Color(0xFF74C69D).withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 22),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const Text(
                  'Explorer Navigation',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _buildNavMenuItem(
                      icon: Icons.person_outline,
                      title: 'My Profile',
                      subtitle: 'Score & badges',
                      color: const Color(0xFF52B788),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/profile/$uid');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.dashboard_outlined,
                      title: 'Dashboard',
                      subtitle: 'Trust & stats',
                      color: const Color(0xFF6366F1),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/dashboard');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.emoji_events_outlined,
                      title: 'Challenges',
                      subtitle: 'Active quests',
                      color: const Color(0xFFFFD166),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/challenges');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.style_outlined,
                      title: 'Discover Cards',
                      subtitle: 'Swipe hidden gems',
                      color: const Color(0xFFEC4899),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/discover');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.leaderboard_outlined,
                      title: 'Leaderboard',
                      subtitle: 'Top explorers',
                      color: const Color(0xFFF59E0B),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/leaderboard');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.cloud_download_outlined,
                      title: 'Offline Vault',
                      subtitle: 'Saved regions',
                      color: const Color(0xFF10B981),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/vault');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.groups_outlined,
                      title: 'Tour Groups',
                      subtitle: 'Tours & Ledger',
                      color: const Color(0xFF2DD4BF),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/group-hub');
                      },
                    ),
                    _buildNavMenuItem(
                      icon: Icons.sports_esports_outlined,
                      title: 'GameZone',
                      subtitle: '29, Chess & Ludo',
                      color: const Color(0xFFA855F7),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/game-zone');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    const Color activeColor = Color(0xFF1B4332);
    const Color inactiveColor = Color(0xFFAEABA4);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 60,
        width: 70, // Explicitly wider and taller tap area
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive)
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              )
            else
              const SizedBox(height: 5),
            Icon(
              icon,
              color: isActive ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : inactiveColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                'CREATE NEW TRAVEL CONTENT',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading:
                    const Icon(Icons.edit_note, color: AppColors.mintGreen),
                title: const Text('New TripLog',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Log a fresh trip route, expenses & pictures',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(context);
                  await _navigateToEditor();
                },
              ),
              ListTile(
                leading: const Icon(Icons.tips_and_updates_outlined,
                    color: AppColors.gold),
                title: const Text('New Pro-Tip',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Post situational fare tips, warnings or advice',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(context);
                  await _navigateToEditor();
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined,
                    color: Colors.white70),
                title: const Text('New Location Pin',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Recommend a spot not currently on the map',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/map');
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // --- TAB CONTENT METHODS (remain the same, but they also use dynamic data) ---

  String? _selectedDivisionFilter;

  Widget _buildNearMeTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'SPOTS NEAR YOUR LOCATION',
            style: TextStyle(
              color: Color(0xFF0D2018),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        _buildNearbySpotsSection(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.map_outlined,
                    color: Color(0xFF74C69D), size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Explore Interactive Travel Map',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF0D2018)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Switch to the Map tab below to view all explorer pins, routes, and division boundaries.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF40916C),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => context.push('/map'),
                  child: const Text('Open Map Tab',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedTabSliver() {
    return BlocBuilder<FeedCubit, FeedState>(
      bloc: _feedCubit,
      builder: (context, state) {
        final byId = <String, TripLog>{
          if (state is FeedLoaded)
            for (final log in [
              ...state.savedLogs,
              ...state.archivedLogs,
              ...state.logs,
            ])
              log.tripId: log,
        };
        // Most recently saved first.
        final savedLogsList = [
          for (final id in _savedLogs.toList().reversed)
            if (byId[id] != null) byId[id]!,
        ];

        return SliverMainAxisGroup(slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'SAVED EXPLORATION DATA',
                style: TextStyle(
                  color: Color(0xFF0D2018),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          if (savedLogsList.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10),
                    ],
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.bookmark_outline,
                          color: Color(0xFF74C69D), size: 40),
                      SizedBox(height: 12),
                      Text(
                        'No Saved Posts Yet',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0D2018)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tap the Save/Bookmark button on any trip log to keep it here for quick access.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            _buildTripLogSliverList(savedLogsList),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_download_outlined,
                        color: Color(0xFF40916C)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Need offline access? Get entire district data packages in the Vault.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF40916C),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => context.push('/vault'),
                      child: const Text('Go to Vault',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildArchiveTabSliver() {
    return BlocBuilder<FeedCubit, FeedState>(
      bloc: _feedCubit,
      builder: (context, state) {
        final loaded = state is FeedLoaded ? state : null;
        // Old logs still in the live collection, then the archive collection.
        final seen = <String>{};
        final archivedLogs = [
          if (loaded != null)
            for (final log in [
              ...loaded.logs.where((log) => log.isArchived),
              ...loaded.archivedLogs,
            ])
              if (seen.add(log.tripId)) log,
        ];
        final isLoading = loaded?.isLoadingArchived ?? false;

        return SliverMainAxisGroup(slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'ARCHIVED TRIP LOGS',
                style: TextStyle(
                  color: Color(0xFF0D2018),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          if (archivedLogs.isEmpty && !isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10),
                    ],
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.archive_outlined,
                          color: Color(0xFF74C69D), size: 40),
                      SizedBox(height: 12),
                      Text(
                        'No Archived Logs',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0D2018)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Logs that have been archived will be kept here for historical reference.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            _buildTripLogSliverList(archivedLogs),
          SliverToBoxAdapter(
            child: _buildPagingFooter(
              isLoading: isLoading,
              hasMore: loaded?.archivedHasMore ?? false,
              onLoadMore: () => _feedCubit.loadArchived(more: true),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildDivisionsTabContent() {
    final divisions = [
      'Dhaka',
      'Sylhet',
      'Chittagong',
      'Khulna',
      'Barishal',
      'Rajshahi',
      'Rangpur',
      'Mymensingh'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EXPLORE BY DIVISION',
                style: TextStyle(
                  color: Color(0xFF0D2018),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              if (_selectedDivisionFilter != null)
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedDivisionFilter = null),
                  child: const Text('Clear Filter',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: divisions.length,
            itemBuilder: (context, index) {
              final div = divisions[index];
              final isSelected = _selectedDivisionFilter == div;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDivisionFilter = isSelected ? null : div;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          isSelected ? const Color(0xFF40916C) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6),
                      ],
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : const Color(0xFFECEAE4),
                      ),
                    ),
                    child: Text(
                      div,
                      style: TextStyle(
                        color:
                            isSelected ? Colors.white : const Color(0xFF0D2018),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildFilteredTripLogsSection(),
      ],
    );
  }

  Widget _buildFilteredTripLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Text(
            _selectedDivisionFilter == null
                ? 'Select a division above to filter'
                : 'Trip Logs in $_selectedDivisionFilter Division',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF0D2018)),
          ),
        ),
        SizedBox(
          height: 255,
          child: BlocBuilder<FeedCubit, FeedState>(
            bloc: _feedCubit,
            builder: (context, state) {
              if (state is FeedLoading || state is FeedInitial) {
                return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: FeedListSkeleton(count: 2));
              }
              if (state is FeedLoaded) {
                final activeLogs =
                    state.logs.where((l) => !l.isArchived).toList();
                final filtered = _selectedDivisionFilter == null
                    ? activeLogs
                    : activeLogs
                        .where((l) =>
                            l.division.toLowerCase() ==
                            _selectedDivisionFilter!.toLowerCase())
                        .toList();

                if (filtered.isNotEmpty) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final log = filtered[index];
                      return _buildDynamicTripLogCard(log);
                    },
                  );
                }
              }
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No trip logs found in this division yet.',
                    style: TextStyle(color: Color(0xFFAEABA4), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'POPULAR & TRENDING LOGS',
            style: TextStyle(
              color: Color(0xFF0D2018),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 255,
          child: BlocBuilder<FeedCubit, FeedState>(
            bloc: _feedCubit,
            builder: (context, state) {
              if (state is FeedLoading || state is FeedInitial) {
                return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: FeedListSkeleton(count: 2));
              }
              if (state is FeedLoaded) {
                final activeLogs =
                    state.logs.where((l) => !l.isArchived).toList();
                final sorted = List<TripLog>.from(activeLogs);
                sorted.sort((a, b) => b.helpfulVotes.compareTo(a.helpfulVotes));

                if (sorted.isNotEmpty) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final log = sorted[index];
                      return _buildDynamicTripLogCard(log);
                    },
                  );
                }
              }
              return const Center(
                child: Text('No trending logs available.',
                    style: TextStyle(color: Color(0xFFAEABA4))),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showNotificationCenter(BuildContext context) {
    final authState = context.read<AuthCubit>().state;
    final uid =
        authState is Authenticated ? authState.profile.uid : 'explorer_user';
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    // Newest 50 only, created once for the sheet's lifetime.
    final notificationsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          height: 450 + bottomPadding,
          padding: EdgeInsets.fromLTRB(24, 24, 24, 16 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'NOTIFICATIONS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Notifications cleared')),
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('Clear all',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: notificationsStream,
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined,
                                size: 48, color: Colors.white54),
                            SizedBox(height: 12),
                            Text(
                              'No notifications yet',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final String title =
                            (data['title'] as String?) ?? 'Bhromon Alert';
                        final String body = (data['body'] as String?) ?? '';
                        final String action = (data['action'] as String?) ?? '';
                        final String notifUid = (data['uid'] as String?) ?? uid;
                        final timestamp = data['timestamp'] as Timestamp?;
                        final timeStr = timestamp != null
                            ? _formatTimestamp(timestamp)
                            : 'Just now';

                        IconData iconData = Icons.notifications;
                        Color iconColor = AppColors.mintGreen;
                        if (action == 'helpful_vote') {
                          iconData = Icons.thumb_up;
                          iconColor = AppColors.leafGreen;
                        } else if (action == 'tier_upgrade') {
                          iconData = Icons.verified_user;
                          iconColor = AppColors.mintGreen;
                        } else if (action == 'conflict') {
                          iconData = Icons.warning_amber_rounded;
                          iconColor = Colors.redAccent;
                        } else if (action == 're_confirm_tips') {
                          iconData = Icons.sync;
                          iconColor = AppColors.amber;
                        } else if (action == 'chat') {
                          iconData = Icons.chat_bubble_outline;
                          iconColor = AppColors.mintGreen;
                        }

                        return _buildNotificationItem(
                          context: context,
                          title: title,
                          body: body,
                          time: timeStr,
                          icon: iconData,
                          iconColor: iconColor,
                          onTap: () {
                            Navigator.pop(context);
                            _handleNotificationAction(
                                context, action, notifUid);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationItem({
    required BuildContext context,
    required String title,
    required String body,
    required String time,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.15),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            Text(
              time,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            body,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  void _handleNotificationAction(
      BuildContext context, String action, String? targetUid) {
    switch (action) {
      case 're_confirm_tips':
        context.push('/vault');
        break;
      case 'conflict':
        context.push('/vault');
        break;
      case 'tier_upgrade':
        final uid = targetUid ?? 'explorer_user';
        context.push('/profile/$uid');
        break;
      case 'chat':
        if (targetUid != null && targetUid.isNotEmpty) {
          final authState = context.read<AuthCubit>().state;
          if (authState is Authenticated) {
            final myUid = authState.profile.uid;
            final uids = [myUid, targetUid]..sort();
            final chatId = uids.join('_');
            context.push('/chat/$chatId', extra: {'otherUid': targetUid});
          }
        }
        break;
      default:
        break;
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

// --- SYNC PULSE ORB ---
class _SyncPulseOrb extends StatefulWidget {
  const _SyncPulseOrb();

  @override
  State<_SyncPulseOrb> createState() => _SyncPulseOrbState();
}

class _SyncPulseOrbState extends State<_SyncPulseOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF74C69D).withValues(alpha: 0.15),
            border: Border.all(
                color: const Color(0xFF74C69D).withValues(alpha: 0.35),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF74C69D)
                    .withValues(alpha: 0.35 * (1.0 - _controller.value)),
                blurRadius: 10 * _controller.value,
                spreadRadius: 6 * _controller.value,
              )
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.cloud_upload_outlined,
              color: Color(0xFF74C69D),
              size: 16,
            ),
          ),
        );
      },
    );
  }
}
