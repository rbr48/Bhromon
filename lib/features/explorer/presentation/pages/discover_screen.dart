import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/core/entities/location_pin.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/map/presentation/widgets/pin_detail_sheet.dart';
import '../../../../core/services/discovery_score_service.dart';
import '../../../../core/value_objects/trust_tier.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final CardSwiperController _swiperController = CardSwiperController();
  bool _loading = true;
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

  Future<void> _loadPins() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('location_pins')
          .get();

      if (query.docs.isNotEmpty) {
        final allPins = query.docs.map((doc) {
          final data = doc.data();
          data['pinId'] = doc.id;
          return LocationPin.fromJson(data);
        }).toList();

        // Sort by computed Discovery Score descending (Hidden Gems first!)
        allPins.sort((a, b) {
          final scoreA = DiscoveryScoreService.compute(a);
          final scoreB = DiscoveryScoreService.compute(b);
          return scoreB.compareTo(scoreA);
        });

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
            imageUrl: 'https://images.unsplash.com/photo-1585123334904-845d60e97b29?w=600',
            description: 'Sajek Valley is an emerging tourist spot in Bangladesh situated among the hills of the Kasalong range.',
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
            imageUrl: 'https://images.unsplash.com/photo-1626509657682-17183e8fa9f2?w=600',
            description: 'Jaflong is a hill station and popular tourist destination in Sylhet Division. It is situated at the border of India.',
          ),
        ];
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading discover pins: $e');
      if (mounted) {
        setState(() {
          _loading = false;
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

      final list = <LocationPin>[];
      for (final doc in query.docs) {
        final pinId = doc.id;
        final pinDoc = await FirebaseFirestore.instance.collection('location_pins').doc(pinId).get();
        if (pinDoc.exists) {
          final data = pinDoc.data()!;
          data['pinId'] = pinDoc.id;
          list.add(LocationPin.fromJson(data));
        }
      }

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
      if (auth is! Authenticated) return;
      final uid = auth.profile.uid;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('wishlist')
          .doc(pin.pinId)
          .set({
        'addedAt': FieldValue.serverTimestamp(),
      });

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
    final pin = _pins[previousIndex];
    if (direction == CardSwiperDirection.right) {
      _addToWishlist(pin);
    }
    setState(() {
      _currentIndex = currentIndex ?? 0;
    });
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('My Wishlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: _wishlist.isEmpty
                    ? const Center(
                        child: Text(
                          'Your wishlist is empty.\nSwipe right on destinations to save them!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _wishlist.length,
                        itemBuilder: (context, index) {
                          final pin = _wishlist[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(pin.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text('${pin.category} • ${pin.district}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141421),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('Discover Destinations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_outline, color: AppColors.mintGreen),
            onPressed: _showWishlistSheet,
          ),
        ],
      ),
      body: _pins.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                const SizedBox(height: 16),
                Expanded(
                  child: CardSwiper(
                    controller: _swiperController,
                    cardsCount: _pins.length,
                    onSwipe: _onSwipe,
                    numberOfCardsDisplayed: 3,
                    backCardOffset: const Offset(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    cardBuilder: (context, index, percentX, percentY) {
                      return _buildCard(_pins[index]);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _buildActionRow(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildCard(LocationPin pin) {
    final hasImg = pin.imageUrl != null && pin.imageUrl!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F3D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Card image/gradient
            if (hasImg)
              Image.network(
                pin.imageUrl!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _gradientFallback(),
              )
            else
              _gradientFallback(),

            // Gradient overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.5, 0.95],
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
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.mintGreen.withOpacity(0.4)),
                        ),
                        child: Text(
                          '💎 ${DiscoveryScoreService.compute(pin).toInt()}',
                          style: const TextStyle(color: AppColors.mintGreen, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${pin.category.toUpperCase()} • ${pin.district}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  if (pin.description != null && pin.description!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      pin.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
        // Left (Skip)
        _actionButton(
          icon: Icons.close_rounded,
          color: Colors.redAccent,
          onTap: () => _swiperController.swipeLeft(),
        ),
        const SizedBox(width: 24),
        // Center (Info)
        _actionButton(
          icon: Icons.info_outline_rounded,
          color: Colors.blueAccent,
          onTap: () {
            if (_currentIndex >= 0 && _currentIndex < _pins.length) {
              PinDetailSheet.show(context, _pins[_currentIndex]);
            }
          },
        ),
        const SizedBox(width: 24),
        // Right (Save)
        _actionButton(
          icon: Icons.bookmark_add_outlined,
          color: Colors.greenAccent,
          onTap: () => _swiperController.swipeRight(),
        ),
      ],
    );
  }

  Widget _actionButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.explore_outlined, size: 64, color: Colors.white30),
          const SizedBox(height: 16),
          const Text(
            "You've explored all destinations!",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            "Check back later for new hidden gems.",
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () => context.pop(),
            child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
