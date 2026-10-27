import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../data/game_analytics_service.dart';
import '../../domain/models/game_analytics_models.dart';

/// Screen view showcasing Game Zone player analytics, match win rates,
/// streaks, and achievement rank badges.
class GameAnalyticsView extends StatefulWidget {
  final GameAnalyticsService? analyticsService;
  final PlayerGameAnalytics? analytics;

  const GameAnalyticsView({
    super.key,
    this.analyticsService,
    this.analytics,
  });

  @override
  State<GameAnalyticsView> createState() => _GameAnalyticsViewState();
}

class _GameAnalyticsViewState extends State<GameAnalyticsView> {
  late final GameAnalyticsService _service =
      widget.analyticsService ?? GameAnalyticsService();

  @override
  void initState() {
    super.initState();
    if (widget.analytics == null) {
      _service.init();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.analytics != null) {
      return _buildContent(widget.analytics!);
    }

    return StreamBuilder<PlayerGameAnalytics>(
      stream: _service.analyticsStream,
      initialData: _service.currentAnalytics,
      builder: (context, snapshot) {
        final analytics = snapshot.data ?? PlayerGameAnalytics.empty();
        return _buildContent(analytics);
      },
    );
  }

  Widget _buildContent(PlayerGameAnalytics analytics) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewCard(analytics),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.leaderboard_rounded,
                  color: AppColors.mintGreen, size: 20),
              SizedBox(width: 8),
              Text(
                'খেলা ভিত্তিক পরিসংখ্যান (Game Breakdown)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...OnlineGameType.values.map((type) {
            final stat =
                analytics.gameStats[type] ?? GameStatItem(gameType: type);
            return _buildGameStatCard(stat);
          }),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(PlayerGameAnalytics analytics) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF14241B),
            const Color(0xFF0F1E16).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.mintGreen.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.military_tech_rounded,
                      color: AppColors.mintGreen,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        analytics.playerTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'ট্যুর গেম জোন র‍্যাংক',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${analytics.overallWinRate.toStringAsFixed(0)}% জয়',
                  style: const TextStyle(
                    color: AppColors.mintGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricColumn(
                '${analytics.totalMatches}',
                'মোট ম্যাচ',
                Icons.sports_esports_rounded,
              ),
              _buildVerticalDivider(),
              _buildMetricColumn(
                '${analytics.totalWins}',
                'মোট জয়',
                Icons.emoji_events_rounded,
              ),
              _buildVerticalDivider(),
              _buildMetricColumn(
                '${analytics.bestOverallStreak}',
                'সেরা স্ট্রিক',
                Icons.local_fire_department_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.mintGreen, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 36,
      width: 1,
      color: Colors.white12,
    );
  }

  Widget _buildGameStatCard(GameStatItem stat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(stat.rankIcon, color: AppColors.mintGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.gameType.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'র‍্যাংক: ${stat.rankBadge}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${stat.matchesWon} / ${stat.matchesPlayed} জয়',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${stat.winRate.toStringAsFixed(0)}% উইন রেট',
                    style: const TextStyle(
                      color: AppColors.mintGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stat.matchesPlayed > 0
                  ? stat.matchesWon / stat.matchesPlayed
                  : 0.0,
              backgroundColor: Colors.white10,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
              minHeight: 6,
            ),
          ),
          if (stat.currentStreak > 0 || stat.highestScore > 0) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (stat.currentStreak > 0)
                  Text(
                    '🔥 বর্তমান স্ট্রিক: ${stat.currentStreak}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                if (stat.highestScore > 0)
                  Text(
                    '⭐ সর্বোচ্চ স্কোর: ${stat.highestScore}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
