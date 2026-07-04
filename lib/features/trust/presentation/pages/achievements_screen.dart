import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/value_objects/trust_tier.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final explorerName = authState is Authenticated
        ? authState.profile.displayName
        : 'Guest Explorer';
    final explorerXP =
        authState is Authenticated ? authState.profile.explorerScore.value : 0;
    final explorerTier = authState is Authenticated
        ? authState.profile.tier
        : TrustTier.unverified;
    final avatarUrl =
        authState is Authenticated ? authState.profile.avatarUrl : null;

    // Calculate XP needed for next tier
    int targetXP = 100;
    double progress = 0.0;
    String nextTierName = 'Community Explorer';

    if (explorerTier == TrustTier.unverified) {
      targetXP = 50;
      progress = (explorerXP / targetXP).clamp(0.0, 1.0);
      nextTierName = 'Community Explorer';
    } else if (explorerTier == TrustTier.community) {
      targetXP = 150;
      progress = ((explorerXP - 50) / (targetXP - 50)).clamp(0.0, 1.0);
      nextTierName = 'Verified Explorer';
    } else if (explorerTier == TrustTier.verified) {
      targetXP = 300;
      progress = ((explorerXP - 150) / (targetXP - 150)).clamp(0.0, 1.0);
      nextTierName = 'Region Expert';
    } else {
      targetXP = 500;
      progress = ((explorerXP - 300) / (targetXP - 300)).clamp(0.0, 1.0);
      nextTierName = 'Pioneer';
    }

    final tierColor = AppColors.forTier(explorerTier);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'EXPLORER PROGRESS',
          style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Explorer card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10)
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: tierColor,
                    backgroundImage:
                        avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person,
                            size: 36, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          explorerName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: tierColor.withValues(alpha: 0.4),
                                width: 0.8),
                          ),
                          child: Text(
                            explorerTier.displayName,
                            style: TextStyle(
                                color: tierColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Progress meter section
            const Text(
              'TIER PROGRESS',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$explorerXP',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Text(
                                'XP',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next Up: $nextTierName',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Earn ${targetXP - explorerXP} more XP to level up. Submit verified logs, vote on routes, or verify checkins.',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Achievements Grid
            const Text(
              'UNLOCKED MILESTONES',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
              children: [
                _buildBadgeCard('Dhaka Voyager', Icons.location_city,
                    explorerXP > 0, AppColors.mintGreen),
                _buildBadgeCard('Safety First', Icons.security,
                    explorerXP >= 25, AppColors.leafGreen),
                _buildBadgeCard('Trek Pioneer', Icons.landscape,
                    explorerXP >= 50, AppColors.midGreen),
                _buildBadgeCard('Route Judge', Icons.verified_user,
                    explorerXP >= 100, AppColors.gold),
                _buildBadgeCard('Elite Leader', Icons.workspace_premium,
                    explorerXP >= 150, Colors.redAccent),
                _buildBadgeCard('Pinnacle', Icons.star, explorerXP >= 250,
                    Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 28),

            // Leaderboard list
            const Text(
              'LEADERBOARD RANKINGS',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  _buildLeaderRow(1, 'Adnan Chowdhury', 'Pioneer', 485, true),
                  _buildLeaderRow(
                      2, 'Sadia Rahman', 'Region Expert', 310, false),
                  _buildLeaderRow(3, explorerName, explorerTier.displayName,
                      explorerXP, false,
                      isCurrentUser: true),
                  _buildLeaderRow(
                      4, 'Farhan Ishraq', 'Verified Explorer', 145, false),
                  _buildLeaderRow(
                      5, 'Tasmia Nuren', 'Community Explorer', 85, false),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeCard(
      String name, IconData icon, bool isUnlocked, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked ? color.withValues(alpha: 0.3) : Colors.white10,
          width: 1,
        ),
      ),
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.3,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor:
                  isUnlocked ? color.withValues(alpha: 0.1) : Colors.white10,
              child: Icon(icon, color: isUnlocked ? color : Colors.white30),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isUnlocked ? Colors.white : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isUnlocked ? 'UNLOCKED' : 'LOCKED',
              style: TextStyle(
                color: isUnlocked ? color : Colors.white24,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderRow(
      int rank, String name, String tier, int xp, bool isFirst,
      {bool isCurrentUser = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppColors.mintGreen.withValues(alpha: 0.08)
            : Colors.transparent,
        border:
            const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: isFirst
                    ? AppColors.gold
                    : (isCurrentUser ? AppColors.mintGreen : Colors.white60),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isCurrentUser ? AppColors.mintGreen : Colors.white,
                    fontWeight:
                        isCurrentUser ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  tier,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            '$xp XP',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
