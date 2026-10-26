import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/utils/shared_latest_stream.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/entities/location_pin.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/services/discovery_score_service.dart';

import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../feed/presentation/widgets/trip_log_detail_sheet.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../../../../core/utils/image_sizing.dart';

class PinDetailSheet extends StatefulWidget {
  final LocationPin pin;
  final Position? currentPosition;

  const PinDetailSheet({
    super.key,
    required this.pin,
    this.currentPosition,
  });

  /// Show pin detail as a full DraggableScrollableSheet (Google Maps style)
  static void show(BuildContext context, LocationPin pin,
      {Position? currentPosition}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.95,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          expand: false,
          snap: true,
          snapSizes: const [0.35, 0.66, 0.95],
          builder: (ctx, scrollController) {
            return PinDetailSheet(
              pin: pin,
              currentPosition: currentPosition,
            );
          },
        );
      },
    );
  }

  @override
  State<PinDetailSheet> createState() => _PinDetailSheetState();
}

class _PinDetailSheetState extends State<PinDetailSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _tipController = TextEditingController();
  int _activeTab = 0; // 0 = info, 1 = travel logs, 2 = tips
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  final ScrollController _scrollController = ScrollController();

  // Cache for author names
  final Map<String, String> _authorCache = {};

  // Firestore listeners keyed by what they watch, created once per sheet.
  // Building them inline re-subscribed every listener on each sheet rebuild.
  final Map<String, Stream<QuerySnapshot>> _queryStreams = {};
  final Map<String, Stream<DocumentSnapshot>> _docStreams = {};

  Stream<QuerySnapshot> _memoQuery(String key, Query Function() query) =>
      _queryStreams.putIfAbsent(key,
          () => SharedLatestStream<QuerySnapshot>(query().snapshots()).stream);

  Stream<DocumentSnapshot> _memoDoc(String key, DocumentReference ref) =>
      _docStreams.putIfAbsent(key,
          () => SharedLatestStream<DocumentSnapshot>(ref.snapshots()).stream);

  WeatherData? _weather;
  bool _loadingWeather = true;
  bool _hasVoted = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadWeather();
    _recordVisit();
  }

  Future<void> _loadWeather() async {
    final data =
        await WeatherService.getCurrentWeather(widget.pin.lat, widget.pin.lng);
    if (mounted) {
      setState(() {
        _weather = data;
        _loadingWeather = false;
      });
    }
  }

  @override
  void dispose() {
    _tipController.dispose();
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _distanceKm() {
    if (widget.currentPosition == null) return -1;
    final d = Geolocator.distanceBetween(
      widget.currentPosition!.latitude,
      widget.currentPosition!.longitude,
      widget.pin.lat,
      widget.pin.lng,
    );
    return d / 1000;
  }

  IconData _categoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'waterfall':
        return Icons.water;
      case 'beach':
        return Icons.beach_access;
      case 'temple':
        return Icons.account_balance;
      case 'mosque':
        return Icons.mosque;
      case 'church':
        return Icons.church;
      case 'forest':
        return Icons.forest;
      case 'market':
        return Icons.storefront;
      case 'heritage':
        return Icons.museum;
      case 'hill':
        return Icons.landscape;
      case 'lake':
        return Icons.water_outlined;
      case 'river':
        return Icons.water_damage;
      case 'restaurant':
        return Icons.restaurant;
      case 'hotel':
        return Icons.hotel;
      case 'park':
        return Icons.park;
      case 'mountain':
        return Icons.terrain;
      default:
        return Icons.place;
    }
  }

  Color _categoryColor(String cat) {
    switch (cat.toLowerCase()) {
      case 'waterfall':
      case 'lake':
      case 'river':
      case 'beach':
        return const Color(0xFF00B4D8);
      case 'forest':
      case 'park':
        return const Color(0xFF52B788);
      case 'temple':
      case 'mosque':
      case 'church':
      case 'heritage':
        return const Color(0xFFF4A261);
      case 'hill':
      case 'mountain':
        return const Color(0xFF6D6875);
      case 'market':
      case 'restaurant':
        return const Color(0xFFE76F51);
      case 'hotel':
        return const Color(0xFF74C69D);
      default:
        return AppColors.mintGreen;
    }
  }

  // Gradient banner colors based on pin name (for when no imageUrl)
  List<Color> _gradientForPin(String name) {
    final h = name.hashCode.abs() % 360;
    return [
      HSLColor.fromAHSL(1.0, h.toDouble(), 0.55, 0.28).toColor(),
      HSLColor.fromAHSL(1.0, ((h + 40) % 360).toDouble(), 0.5, 0.18).toColor(),
    ];
  }

  Future<String> _resolveAuthor(String authorId) async {
    if (_authorCache.containsKey(authorId)) return _authorCache[authorId]!;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authorId)
          .get();
      final name = doc.data()?['displayName'] as String? ??
          doc.data()?['name'] as String? ??
          'Explorer';
      _authorCache[authorId] = name;
      return name;
    } catch (_) {
      return 'Explorer';
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    final color = AppColors.forTier(pin.trustTier);
    final catColor = _categoryColor(pin.category);
    final distKm = _distanceKm();
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Hero Image / Gradient Banner ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background: image or gradient
                      if (pin.imageUrl != null && pin.imageUrl!.isNotEmpty)
                        CachedNetworkImage(
                          memCacheWidth: context.decodeWidth(),
                          imageUrl: pin.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _buildGradientBanner(pin.name),
                        )
                      else
                        _buildGradientBanner(pin.name),

                      // Gradient overlay for text readability
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Category badge
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_categoryIcon(pin.category),
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                pin.category.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Trust tier badge
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            pin.trustTier.displayName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      // Name + location on banner
                      Positioned(
                        bottom: 10,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pin.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black54,
                                    offset: Offset(0, 1),
                                  )
                                ],
                              ),
                            ),
                            Text(
                              '${pin.district}, ${pin.division}',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Quick Stats Row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _quickStat(
                      Icons.star_rounded,
                      AppColors.gold,
                      pin.averageRating > 0
                          ? pin.averageRating.toStringAsFixed(1)
                          : 'N/A'),
                  const SizedBox(width: 8),
                  _quickStat(Icons.people_outline, AppColors.mintGreen,
                      '${pin.visitCount} visits'),
                  const SizedBox(width: 8),
                  if (distKm >= 0)
                    _quickStat(Icons.near_me_outlined, const Color(0xFF00B4D8),
                        '${distKm.toStringAsFixed(1)} km away'),
                  const Spacer(),
                  // Copy coordinates
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(
                          text:
                              '${pin.lat.toStringAsFixed(5)}, ${pin.lng.toStringAsFixed(5)}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Coordinates copied!'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '${pin.lat.toStringAsFixed(4)}, ${pin.lng.toStringAsFixed(4)}',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Tab Pills ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _tabPill('INFO', 0),
                  const SizedBox(width: 8),
                  _tabPill('TRAVEL LOGS', 1),
                  const SizedBox(width: 8),
                  _tabPill('LIVE TIPS', 2),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Tab Content ──────────────────────────────────────────────────
            Expanded(
              child: _buildTabContent(pin, bottomPad),
            ),

            // ── Action Buttons ───────────────────────────────────────────────
            _buildActionRow(pin, bottomPad),
          ],
        ),
      ),
    );
  }

  // ── Sub-builders ─────────────────────────────────────────────────────────

  Widget _buildGradientBanner(String name) {
    final colors = _gradientForPin(name);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          _categoryIcon(widget.pin.category),
          size: 52,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
  }

  Widget _quickStat(IconData icon, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _tabPill(String label, int index) {
    final cs = Theme.of(context).colorScheme;
    final selected = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.mintGreen
              : cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? AppColors.mintGreen
                  : cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.darkGreen : cs.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(LocationPin pin, double bottomPad) {
    switch (_activeTab) {
      case 0:
        return _buildInfoTab(pin);
      case 1:
        return _buildTravelLogsTab(pin);
      case 2:
        return _buildLiveTipsTab(pin);
      default:
        return const SizedBox();
    }
  }

  Widget _buildInfoTab(LocationPin pin) {
    final cs = Theme.of(context).colorScheme;
    final color = AppColors.forTier(pin.trustTier);
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          if (pin.description != null && pin.description!.isNotEmpty) ...[
            Text(
              pin.description!,
              style: TextStyle(
                  color: cs.onSurface, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No description yet. Be the first to add one by creating a trip log!',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Weather Card
          if (_loadingWeather)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              height: 60,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                  child: LinearProgressIndicator(
                      color: AppColors.mintGreen,
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.3))),
            )
          else if (_weather != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _weather!.isSafeToVisit
                      ? [const Color(0xFF1A3A4A), const Color(0xFF0D2030)]
                      : [const Color(0xFF4A1A1A), const Color(0xFF2A0D0D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Text(_weather!.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_weather!.tempC.toStringAsFixed(1)}°C  •  ${_weather!.description}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        Text(
                          '💨 ${_weather!.windKph.toStringAsFixed(0)} km/h  •  🌧️ ${_weather!.precipMm.toStringAsFixed(1)}mm',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _weather!.isSafeToVisit
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _weather!.isSafeToVisit
                          ? '✅ Safe to visit'
                          : '⚠️ Check conditions',
                      style: TextStyle(
                        color: _weather!.isSafeToVisit
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),

          // Trust Meter
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified_outlined, color: color, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Trust Level',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      pin.trustTier.displayName,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pin.trustTier.numericWeight / 1.3,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Last confirmed: ${_formatDate(pin.lastConfirmed)}',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                    ),
                    Text(
                      '${pin.linkedTripIds.length} logs • ${pin.linkedTipIds.length} tips',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          // Discovery Score
          _buildDiscoveryScoreCard(pin),
          const SizedBox(height: 12),
          _buildRecentVisitors(pin),
          const SizedBox(height: 12),
          _buildCommunityVoting(pin),

          // Photos grid (if available)
          if (pin.photos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Photos',
                style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pin.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    memCacheWidth: context.decodeWidth(120),
                    imageUrl: pin.photos[i],
                    width: 120,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTravelLogsTab(LocationPin pin) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid = authState is Authenticated ? authState.profile.uid : '';

    if (currentUid.isEmpty) {
      // Guests can only see community logs
      return StreamBuilder<QuerySnapshot>(
        stream: _memoQuery(
            'logs_community_${pin.pinId}',
            () => FirebaseFirestore.instance
                .collection('trip_logs')
                .where('locationPinId', isEqualTo: pin.pinId)
                .where('visibility', isEqualTo: 'community')
                .orderBy('createdAt', descending: true)
                .limit(20)),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                  color: AppColors.mintGreen, strokeWidth: 2),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(
              Icons.article_outlined,
              'No travel logs yet',
              'Be the first to share your experience at ${pin.name}!',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              data['tripId'] = docs[i].id;
              TripLog log;
              try {
                log = TripLog.fromJson(data);
              } catch (_) {
                return const SizedBox.shrink();
              }
              return _buildTripLogCard(log);
            },
          );
        },
      );
    }

    // Authenticated users:
    final followsStream = FirebaseFirestore.instance
        .collection('follows')
        .where('followerId', isEqualTo: currentUid)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: followsStream,
      builder: (ctx, followsSnapshot) {
        final followedUids = (followsSnapshot.data?.docs ?? [])
            .map((doc) =>
                (doc.data() as Map<String, dynamic>)['followedId']
                    ?.toString() ??
                '')
            .where((uid) => uid.isNotEmpty)
            .toSet();

        return StreamBuilder<QuerySnapshot>(
          stream: _memoQuery(
              'logs_all_${pin.pinId}',
              () => FirebaseFirestore.instance
                  .collection('trip_logs')
                  .where('locationPinId', isEqualTo: pin.pinId)
                  .orderBy('createdAt', descending: true)
                  .limit(20)),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                    color: AppColors.mintGreen, strokeWidth: 2),
              );
            }
            final rawDocs = snapshot.data?.docs ?? [];
            final docs = rawDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final visibility = data['visibility']?.toString() ?? 'community';
              final authorId = data['authorId']?.toString() ?? '';

              if (authorId == currentUid) return true;
              if (visibility == 'private') return false;
              if (visibility == 'friends') {
                return followedUids.contains(authorId);
              }
              return true;
            }).toList();

            if (docs.isEmpty) {
              return _emptyState(
                Icons.article_outlined,
                'No travel logs yet',
                'Be the first to share your experience at ${pin.name}!',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                data['tripId'] = docs[i].id;
                TripLog log;
                try {
                  log = TripLog.fromJson(data);
                } catch (_) {
                  return const SizedBox.shrink();
                }
                return _buildTripLogCard(log);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTripLogCard(TripLog log) {
    final tierColor = AppColors.forTier(log.tier);
    // Try to get first image from blocks using sealed class pattern matching
    String? thumbUrl;
    for (final block in log.blocks) {
      if (block is ImageBlock) {
        final url = block.storageUrl;
        if (url.isNotEmpty &&
            (url.startsWith('http') || url.startsWith('https'))) {
          thumbUrl = url;
          break;
        }
      }
    }

    return GestureDetector(
      onTap: () => TripLogDetailSheet.show(context, log),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(14)),
              child: Container(
                width: 80,
                height: 80,
                color: Colors.white.withValues(alpha: 0.05),
                child: thumbUrl != null
                    ? CachedNetworkImage(
                        memCacheWidth: context.decodeWidth(80),
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _thumbnailFallback(tierColor),
                      )
                    : _thumbnailFallback(tierColor),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<String>(
                      future: _resolveAuthor(log.authorId),
                      builder: (ctx, snap) => Text(
                        'By ${snap.data ?? '...'}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.gold, size: 12),
                        const SizedBox(width: 3),
                        Text('${log.trustScore}',
                            style: TextStyle(
                                color: tierColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        const Icon(Icons.thumb_up_outlined,
                            color: Colors.white54, size: 12),
                        const SizedBox(width: 3),
                        Text('${log.helpfulVotes}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        const Spacer(),
                        Text(
                          _formatDate(log.publishedAt ?? log.lastConfirmed),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryScoreCard(LocationPin pin) {
    final score = DiscoveryScoreService.compute(pin);
    final isGem = DiscoveryScoreService.isHiddenGem(pin);
    final label = DiscoveryScoreService.label(score);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGem
              ? const Color(0xFF52B788).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Text(DiscoveryScoreService.emoji(score),
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      score >= 60 ? const Color(0xFF52B788) : Colors.white38,
                    ),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${score.toInt()}',
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _thumbnailFallback(Color color) {
    return Container(
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Icon(Icons.image_outlined,
            color: color.withValues(alpha: 0.5), size: 28),
      ),
    );
  }

  Widget _buildLiveTipsTab(LocationPin pin) {
    final authState = context.read<AuthCubit>().state;
    final uid = authState is Authenticated ? authState.profile.uid : 'guest';
    final name = authState is Authenticated
        ? authState.profile.displayName
        : 'Guest Explorer';
    final tierName =
        authState is Authenticated ? authState.profile.tier.name : 'unverified';

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _memoQuery(
                'live_tips_${pin.pinId}',
                () => FirebaseFirestore.instance
                    .collection('location_pins')
                    .doc(pin.pinId)
                    .collection('live_tips')
                    .orderBy('timestamp', descending: true)
                    .limit(50)),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.mintGreen, strokeWidth: 2),
                );
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return _emptyState(
                  Icons.lightbulb_outline,
                  'No tips yet',
                  'Share a quick tip with other explorers!',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final String text = (data['text'] as String?) ?? '';
                  final authorName =
                      data['authorName'] as String? ?? 'Explorer';
                  final tierStr = data['tier'] as String? ?? 'unverified';
                  final tier = TrustTier.values.firstWhere(
                    (t) => t.name == tierStr,
                    orElse: () => TrustTier.unverified,
                  );
                  final tipColor = AppColors.forTier(tier);
                  final ts = data['timestamp'] as Timestamp?;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: tipColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  authorName,
                                  style: TextStyle(
                                      color: tipColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: tipColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tier.displayName.toUpperCase(),
                                    style: TextStyle(
                                        color: tipColor,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            if (ts != null)
                              Text(
                                _formatDate(ts.toDate()),
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 9),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          text,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface, fontSize: 12.5, height: 1.5),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Tip input row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _tipController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                    maxLength: 140,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    decoration: InputDecoration(
                      hintText: 'Share a tip (max 140 chars)...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: AppColors.mintGreen,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    final text = _tipController.text.trim();
                    if (text.isEmpty || text.length > 140) return;
                    await FirebaseFirestore.instance
                        .collection('location_pins')
                        .doc(pin.pinId)
                        .collection('live_tips')
                        .add({
                      'text': text,
                      'authorId': uid,
                      'authorName': name,
                      'tier': tierName,
                      'timestamp': FieldValue.serverTimestamp(),
                    });
                    _tipController.clear();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child:
                        Icon(Icons.send_rounded, color: Colors.black, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(LocationPin pin, double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomPad),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          // Directions → Google Maps
          Expanded(
            child: _actionBtn(
              icon: Icons.directions_outlined,
              label: 'Directions',
              color: AppColors.mintGreen,
              onTap: () async {
                final url = Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=${pin.lat},${pin.lng}');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // Verify Fresh
          Expanded(
            child: _actionBtn(
              icon: Icons.check_circle_outline,
              label: 'Verify',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              filled: false,
              onTap: () {
                context.read<MapBloc>().add(ConfirmPinEvent(pin.pinId));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('✅ Pin verified fresh!'),
                      duration: Duration(seconds: 2)),
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          // Create Log
          Expanded(
            child: _actionBtn(
              icon: Icons.edit_note,
              label: 'Log Trip',
              color: AppColors.midGreen,
              onTap: () {
                Navigator.pop(context);
                context.push('/editor', extra: {'pinId': pin.pinId});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return Material(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: filled
              ? null
              : BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: filled ? Colors.white : color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 40),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _recordVisit() async {
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is! Authenticated) return;
      await FirebaseFirestore.instance.collection('pin_visits').add({
        'pinId': widget.pin.pinId,
        'userId': auth.profile.uid,
        'userName': auth.profile.displayName,
        'tier': auth.profile.tier.name,
        'visitedAt': FieldValue.serverTimestamp(),
      });
      // Increment visitCount on the pin
      await FirebaseFirestore.instance
          .collection('location_pins')
          .doc(widget.pin.pinId)
          .update({'visitCount': FieldValue.increment(1)});
    } catch (_) {}
  }

  Widget _buildRecentVisitors(LocationPin pin) {
    return StreamBuilder<QuerySnapshot>(
      stream: _memoQuery(
          'visits_${pin.pinId}',
          () => FirebaseFirestore.instance
              .collection('pin_visits')
              .where('pinId', isEqualTo: pin.pinId)
              .orderBy('visitedAt', descending: true)
              .limit(8)),
      builder: (ctx, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_outline,
                      color: AppColors.mintGreen, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    "Who's Been Here (${docs.length})",
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ...docs.take(5).map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name =
                        (data['userName'] as String? ?? '?')[0].toUpperCase();
                    final tierStr = data['tier'] as String? ?? 'unverified';
                    final tier = TrustTier.values.firstWhere(
                        (t) => t.name == tierStr,
                        orElse: () => TrustTier.unverified);
                    return Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.forTier(tier),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Center(
                        child: Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ),
                    );
                  }),
                  if (docs.length > 5)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white12,
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Center(
                        child: Text('+${docs.length - 5}',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${docs.length} explorer${docs.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommunityVoting(LocationPin pin) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _memoDoc(
          'pin_${pin.pinId}',
          FirebaseFirestore.instance
              .collection('location_pins')
              .doc(pin.pinId)),
      builder: (ctx, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final upvotes = (data?['upvotes'] as int?) ?? 0;
        final downvotes = (data?['downvotes'] as int?) ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Is this info still accurate?',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _voteBtn(
                      icon: Icons.thumb_up_outlined,
                      label: 'Accurate ($upvotes)',
                      color: Colors.greenAccent,
                      onTap: () => _vote(pin.pinId, true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _voteBtn(
                      icon: Icons.thumb_down_outlined,
                      label: 'Outdated ($downvotes)',
                      color: Colors.redAccent,
                      onTap: () => _vote(pin.pinId, false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _voteBtn(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: _hasVoted ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _vote(String pinId, bool isAccurate) async {
    if (_hasVoted) return;
    setState(() => _hasVoted = true);
    try {
      final field = isAccurate ? 'upvotes' : 'downvotes';
      await FirebaseFirestore.instance
          .collection('location_pins')
          .doc(pinId)
          .update({field: FieldValue.increment(1)});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isAccurate
                  ? '👍 Thanks for confirming!'
                  : '👎 Thanks for the feedback!'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (_) {
      setState(() => _hasVoted = false);
    }
  }
}
