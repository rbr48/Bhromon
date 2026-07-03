import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:bhromon/core/theme/colors.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';

class ChallengeItem {
  final String title;
  final String description;
  final String category;
  final int requiredCount;
  final int currentCount;
  final String rewardBadge;
  final int rewardPoints;

  const ChallengeItem({
    required this.title,
    required this.description,
    required this.category,
    required this.requiredCount,
    required this.currentCount,
    required this.rewardBadge,
    required this.rewardPoints,
  });
}

class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<ChallengeItem> _challenges = [];
  List<Map<String, dynamic>> _myBadges = [];

  // Static fallback challenges
  static const List<ChallengeItem> _defaultChallenges = [
    ChallengeItem(
      title: 'Waterfall Hunter',
      description: 'Visit 5 waterfalls across the country',
      category: 'waterfall',
      requiredCount: 5,
      currentCount: 2,
      rewardBadge: '🌊',
      rewardPoints: 50,
    ),
    ChallengeItem(
      title: 'Hill Trekker',
      description: 'Log 3 trip logs in hilly regions',
      category: 'hill',
      requiredCount: 3,
      currentCount: 1,
      rewardBadge: '⛰️',
      rewardPoints: 40,
    ),
    ChallengeItem(
      title: 'City Explorer',
      description: 'Visit 3 different divisions of Bangladesh',
      category: 'division',
      requiredCount: 3,
      currentCount: 2,
      rewardBadge: '🏙️',
      rewardPoints: 30,
    ),
    ChallengeItem(
      title: 'Budget Traveler',
      description: 'Add detailed cost breakdown to 5 logs',
      category: 'budget',
      requiredCount: 5,
      currentCount: 3,
      rewardBadge: '💰',
      rewardPoints: 25,
    ),
    ChallengeItem(
      title: 'Photographer',
      description: 'Add 20+ photos across your trip logs',
      category: 'photos',
      requiredCount: 20,
      currentCount: 12,
      rewardBadge: '📸',
      rewardPoints: 35,
    ),
    ChallengeItem(
      title: 'Safety Champion',
      description: 'Add safety notes to 5 trip logs',
      category: 'safety',
      requiredCount: 5,
      currentCount: 2,
      rewardBadge: '🛡️',
      rewardPoints: 20,
    ),
    ChallengeItem(
      title: 'Pioneer Spirit',
      description: 'Be the first explorer to log a pin',
      category: 'pioneer',
      requiredCount: 1,
      currentCount: 0,
      rewardBadge: '🚀',
      rewardPoints: 100,
    ),
    ChallengeItem(
      title: 'Guide Creator',
      description: 'Reach 200 trust score to unlock Premium Guides',
      category: 'guide',
      requiredCount: 200,
      currentCount: 45,
      rewardBadge: '🏅',
      rewardPoints: 60,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadChallengesAndBadges();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChallengesAndBadges() async {
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is! Authenticated) return;
      final uid = authState.profile.uid;

      // 1. Load active challenges from Firestore (if empty, load defaults)
      final challQuery = await FirebaseFirestore.instance.collection('challenges').get();
      if (challQuery.docs.isNotEmpty) {
        _challenges = challQuery.docs.map((doc) {
          final data = doc.data();
          return ChallengeItem(
            title: (data['title'] as String?) ?? '',
            description: (data['description'] as String?) ?? '',
            category: (data['category'] as String?) ?? '',
            requiredCount: data['requiredCount'] as int? ?? 1,
            currentCount: data['currentCount'] as int? ?? 0,
            rewardBadge: (data['rewardBadge'] as String?) ?? '🏅',
            rewardPoints: data['rewardPoints'] as int? ?? 10,
          );
        }).toList();
      } else {
        _challenges = _defaultChallenges;
      }

      // 2. Load my badges
      final badgeQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('badges')
          .get();

      _myBadges = badgeQuery.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Badge',
          'icon': data['icon'] ?? '🏆',
          'date': (data['earnedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        };
      }).toList();

      if (_myBadges.isEmpty) {
        _myBadges = [
          {'name': 'First Pin Visit', 'icon': '🧭', 'date': DateTime.now()},
          {'name': 'Explorer Starter', 'icon': '⛺', 'date': DateTime.now().subtract(const Duration(days: 2))},
        ];
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading challenges: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F1A),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141426),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Explorer Challenges',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.mintGreen,
          labelColor: AppColors.mintGreen,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'ACTIVE CHALLENGES'),
            Tab(text: 'MY BADGES'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChallengesTab(),
          _buildBadgesTab(),
        ],
      ),
    );
  }

  Widget _buildChallengesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _challenges.length,
      itemBuilder: (context, index) {
        final challenge = _challenges[index];
        final double progress = (challenge.currentCount / challenge.requiredCount).clamp(0.0, 1.0);
        return Card(
          color: Colors.white.withOpacity(0.04),
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: progress >= 1.0 ? Colors.amber.withOpacity(0.4) : Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(challenge.rewardBadge, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            challenge.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            challenge.description,
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress: ${challenge.currentCount}/${challenge.requiredCount}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      '🏆 +${challenge.rewardPoints} pts',
                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(progress >= 1.0 ? Colors.amber : AppColors.mintGreen),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgesTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.1,
      ),
      itemCount: _myBadges.length,
      itemBuilder: (context, index) {
        final badge = _myBadges[index];
        final DateTime date = badge['date'] as DateTime;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B36),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4AF37).withOpacity(0.08),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(badge['icon'] as String? ?? '🏆', style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text(
                badge['name'] as String? ?? 'Badge',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Earned ${date.day}/${date.month}/${date.year}',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        );
      },
    );
  }
}
