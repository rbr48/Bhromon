import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/map/presentation/widgets/pin_detail_sheet.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/discovery_score_service.dart';
import '../../../map/domain/usecases/get_nearby_pins_usecase.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../../core/utils/image_sizing.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final CardSwiperController _swiperController = CardSwiperController();
  bool _loading = true;
  bool _isDeckFinished = false;
  List<LocationPin> _pins = [];
  final List<LocationPin> _wishlist = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPins();
    _loadWishlist();
  }

  @override
  void dispose() {
    _swiperController.dispose();
    super.dispose();
  }

  Future<List<LocationPin>> _fetchAllPins() async {
    // Shares the map's pin cache, so opening Discover after the map (or the
    // other way round) costs no extra Firestore reads.
    double lat = 23.6850;
    double lng = 90.3563;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {}

    final result = await getIt<GetNearbyPinsUseCase>()(
        GetNearbyPinsParams(lat: lat, lng: lng, radiusKm: 500));
    return result.getOrElse(() => const []);
  }

  Future<void> _loadPins() async {
    try {
      final fetched = await _fetchAllPins();

      if (fetched.isNotEmpty) {
        // Sort by Discovery Score descending (Hidden Gems first!), scoring
        // each pin once rather than twice per comparison.
        final scored = [
          for (final pin in fetched)
            (pin: pin, score: DiscoveryScoreService.compute(pin)),
        ]..sort((a, b) => b.score.compareTo(a.score));
        final allPins = [for (final entry in scored) entry.pin];

        _pins = allPins;
      } else {
        // Fallback demo pins
        _pins = [
          LocationPin(
            pinId: 'pin_sajek',
            name: 'Sajek Valley',
            geoHash: 'w3',
            lat: 23.3816,
            lng: 92.2938,
            trustTier: TrustTier.verified,
            lastConfirmed: DateTime.now(),
            linkedTripIds: const [],
            linkedTipIds: const [],
            division: 'Chittagong',
            district: 'Rangamati',
            createdByUid: 'system',
            category: 'hill',
            visitCount: 154,
            imageUrl:
                'https://images.unsplash.com/photo-1585123334904-845d60e97b29?w=600',
            description:
                'Sajek Valley is an emerging tourist spot in Bangladesh situated among the hills of the Kasalong range.',
          ),
          LocationPin(
            pinId: 'pin_jaflong',
            name: 'Jaflong',
            geoHash: 'w3',
            lat: 25.1583,
            lng: 92.0150,
            trustTier: TrustTier.verified,
            lastConfirmed: DateTime.now(),
            linkedTripIds: const [],
            linkedTipIds: const [],
            division: 'Sylhet',
            district: 'Sylhet',
            createdByUid: 'system',
            category: 'river',
            visitCount: 92,
            imageUrl:
                'https://images.unsplash.com/photo-1626509657682-17183e8fa9f2?w=600',
            description:
                'Jaflong is a hill station and popular tourist destination in Sylhet Division. It is situated at the border of India.',
          ),
        ];
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _isDeckFinished = false;
          _currentIndex = 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading discover pins: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _isDeckFinished = false;
          _currentIndex = 0;
        });
      }
    }
  }

  Future<void> _loadWishlist() async {
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is! Authenticated) return;
      final uid = auth.profile.uid;

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('wishlist')
          .get();

      // Resolve wishlist ids from the shared pin set; fetch any stragglers
      // in parallel instead of one round trip per pin.
      final byId = {for (final pin in await _fetchAllPins()) pin.pinId: pin};
      final missing =
          query.docs.map((d) => d.id).where((id) => !byId.containsKey(id));
      final fetched = await Future.wait(missing.map((pinId) async {
        final pinDoc = await FirebaseFirestore.instance
            .collection('location_pins')
            .doc(pinId)
            .get();
        if (!pinDoc.exists) return null;
        final data = pinDoc.data()!;
        data['pinId'] = pinDoc.id;
        if (data['lastConfirmed'] is Timestamp) {
          data['lastConfirmed'] =
              (data['lastConfirmed'] as Timestamp).toDate().toIso8601String();
        }
        return LocationPin.fromJson(data);
      }));
      for (final pin in fetched) {
        if (pin != null) byId[pin.pinId] = pin;
      }
      final list = [
        for (final doc in query.docs)
          if (byId[doc.id] != null) byId[doc.id]!,
      ];

      if (mounted) {
        setState(() {
          _wishlist.clear();
          _wishlist.addAll(list);
        });
      }
    } catch (_) {}
  }

  Future<void> _addToWishlist(LocationPin pin) async {
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is Authenticated) {
        final uid = auth.profile.uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('wishlist')
            .doc(pin.pinId)
            .set({
          'addedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      if (!_wishlist.any((p) => p.pinId == pin.pinId)) {
        setState(() {
          _wishlist.add(pin);
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💾 Added ${pin.name} to Wishlist!'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1F2C34),
        ),
      );
    } catch (e) {
      debugPrint('Error adding to wishlist: $e');
    }
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    if (previousIndex >= 0 && previousIndex < _pins.length) {
      final pin = _pins[previousIndex];
      if (direction == CardSwiperDirection.right) {
        _addToWishlist(pin);
      }
    }
    if (currentIndex != null) {
      setState(() {
        _currentIndex = currentIndex;
      });
    } else {
      setState(() {
        _isDeckFinished = true;
      });
    }
    return true;
  }

  void _showWishlistSheet() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF14142B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('My Wishlist',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: _wishlist.isEmpty
                    ? const Center(
                        child: Text(
                          'Your wishlist is empty.\nSwipe right on destinations to save them!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _wishlist.length,
                        itemBuilder: (context, index) {
                          final pin = _wishlist[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(pin.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            subtitle: Text('${pin.category} • ${pin.district}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                            trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white54,
                                size: 14),
                            onTap: () {
                              Navigator.pop(context);
                              PinDetailSheet.show(context, pin);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D14),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
          ),
        ),
      );
    }

    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141421),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('Discover Destinations',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            icon:
                const Icon(Icons.bookmark_outline, color: AppColors.mintGreen),
            onPressed: _showWishlistSheet,
          ),
        ],
      ),
      // SafeArea prevents the Android 3-button navigation bar and iOS home bar
      // from overlapping with the action buttons row.
      body: SafeArea(
        top: false,
        bottom: true,
        child: (_pins.isEmpty || _isDeckFinished)
            ? _buildEmptyState()
            : Column(
                children: [
                  const SizedBox(height: 12),
                  Expanded(
                    child: CardSwiper(
                      controller: _swiperController,
                      cardsCount: _pins.length,
                      onSwipe: _onSwipe,
                      onUndo: (previousIndex, currentIndex, direction) {
                        setState(() {
                          _isDeckFinished = false;
                          _currentIndex = currentIndex;
                        });
                        return true;
                      },
                      onEnd: () {
                        setState(() {
                          _isDeckFinished = true;
                        });
                      },
                      numberOfCardsDisplayed:
                          _pins.length >= 3 ? 3 : _pins.length,
                      // Negative Y offset lets back cards peek from the top without
                      // extending downward into the action navigation buttons row.
                      backCardOffset: const Offset(0, -14),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      cardBuilder: (context, index, percentX, percentY) {
                        return _buildCard(_pins[index]);
                      },
                    ),
                  ),
                  // Safe padding lifts action buttons well above Android system navigation buttons
                  Padding(
                    padding: EdgeInsets.only(
                      top: 4,
                      bottom: math.max(bottomPadding, 16) + 4,
                    ),
                    child: _buildActionRow(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCard(LocationPin pin) {
    final hasImg = pin.imageUrl != null && pin.imageUrl!.isNotEmpty;
    final score = DiscoveryScoreService.compute(pin);
    final scoreLabel = DiscoveryScoreService.label(score);

    return GestureDetector(
      onTap: () => PinDetailSheet.show(context, pin),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F3D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Card image/gradient with disk and memory cache
              if (hasImg)
                CachedNetworkImage(
                  imageUrl: pin.imageUrl!,
                  memCacheWidth: context.decodeWidth(),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _gradientFallback(),
                  errorWidget: (_, __, ___) => _gradientFallback(),
                )
              else
                _gradientFallback(),

              // Gradient overlay ensuring high text readability
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Color(0x33000000),
                      Color(0xCC000000),
                      Colors.black,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.4, 0.75, 1.0],
                  ),
                ),
              ),

              // Card content
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            pin.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.mintGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.mintGreen.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '💎 ${score.toInt()}',
                            style: const TextStyle(
                                color: AppColors.mintGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${pin.category.toUpperCase()} • ${pin.district}',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          scoreLabel,
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (pin.description != null &&
                        pin.description!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        pin.description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Tap for full details',
                          style: TextStyle(
                            color: AppColors.mintGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward,
                            size: 12, color: AppColors.mintGreen),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradientFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3B2F5D), Color(0xFF14142B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.landscape_outlined, size: 80, color: Colors.white10),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rewind / Undo
        _actionButton(
          icon: Icons.undo_rounded,
          color: AppColors.gold,
          size: 48,
          iconSize: 22,
          tooltip: 'Rewind',
          onTap: () => _swiperController.undo(),
        ),
        const SizedBox(width: 18),
        // Left (Skip)
        _actionButton(
          icon: Icons.close_rounded,
          color: Colors.redAccent,
          size: 56,
          iconSize: 26,
          tooltip: 'Skip',
          onTap: () => _swiperController.swipeLeft(),
        ),
        const SizedBox(width: 18),
        // Center (Info)
        _actionButton(
          icon: Icons.info_outline_rounded,
          color: Colors.blueAccent,
          size: 48,
          iconSize: 22,
          tooltip: 'Details',
          onTap: () {
            if (_currentIndex >= 0 && _currentIndex < _pins.length) {
              PinDetailSheet.show(context, _pins[_currentIndex]);
            }
          },
        ),
        const SizedBox(width: 18),
        // Right (Save)
        _actionButton(
          icon: Icons.bookmark_add_outlined,
          color: AppColors.mintGreen,
          size: 56,
          iconSize: 26,
          tooltip: 'Save to Wishlist',
          onTap: () => _swiperController.swipeRight(),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
    double iconSize = 24,
    String? tooltip,
  }) {
    Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.explore_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              "You've explored all destinations!",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17),
            ),
            const SizedBox(height: 8),
            const Text(
              "Check back later for new hidden gems, or restart the deck to review them again.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.mintGreen,
                    side: const BorderSide(color: AppColors.mintGreen),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Restart Deck',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    setState(() {
                      _loading = true;
                    });
                    _loadPins();
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onPressed: () => context.pop(),
                  child: const Text('Back to Home',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
