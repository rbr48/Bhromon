import 'package:flutter/material.dart';
import '../../../../core/theme/colors.dart';
import '../../../tour_group/data/tour_group_repository.dart';
import '../../data/game_analytics_service.dart';
import '../../domain/models/game_analytics_models.dart';

/// Screen view showcasing Game Zone player analytics, match history,
/// win rates, achievement rank badges, and Tour Leaderboard.
class GameAnalyticsView extends StatefulWidget {
  final GameAnalyticsService? analyticsService;
  final PlayerGameAnalytics? analytics;
  final String? activeTourId;
  final TourGroupRepository? tourRepository;

  const GameAnalyticsView({
    super.key,
    this.analyticsService,
    this.analytics,
    this.activeTourId,
    this.tourRepository,
  });

  @override
  State<GameAnalyticsView> createState() => _GameAnalyticsViewState();
}

class _GameAnalyticsViewState extends State<GameAnalyticsView> {
  late final GameAnalyticsService _service =
      widget.analyticsService ?? GameAnalyticsService();
  late final TourGroupRepository _tourRepo =
      widget.tourRepository ?? TourGroupRepository();

  int _selectedSubTab = 0; // 0 = Stats, 1 = History, 2 = Leaderboard
  List<TourLeaderboardEntry>? _leaderboardEntries;
  bool _isLoadingLeaderboard = false;

  @override
  void initState() {
    super.initState();
    if (widget.analytics == null) {
      _service.init();
    }
  }

  Future<void> _loadLeaderboard() async {
    if (widget.activeTourId == null) return;
    setState(() => _isLoadingLeaderboard = true);

    try {
      final members =
          await _tourRepo.watchMembers(widget.activeTourId!).first;
      final uids = <String>[];
      final uidToName = <String, String>{};
      final uidToPhoto = <String, String?>{};

      for (final m in members) {
        if (m.uid != null && m.uid!.isNotEmpty) {
          uids.add(m.uid!);
          uidToName[m.uid!] = m.displayName;
          uidToPhoto[m.uid!] = m.photoUrl;
        }
      }

      final entries = await _service.fetchTourLeaderboard(
        uids,
        uidToName,
        uidToPhoto,
      );

      if (mounted) {
        setState(() {
          _leaderboardEntries = entries;
          _isLoadingLeaderboard = false;
        });
      }
    } catch (e) {
      debugPrint('[GameAnalyticsView] Error loading leaderboard: $e');
      if (mounted) {
        setState(() => _isLoadingLeaderboard = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.analytics != null) {
      return _buildScaffoldContent(widget.analytics!);
    }

    return StreamBuilder<PlayerGameAnalytics>(
      stream: _service.analyticsStream,
      initialData: _service.currentAnalytics,
      builder: (context, snapshot) {
        final analytics = snapshot.data ?? PlayerGameAnalytics.empty();
        return _buildScaffoldContent(analytics);
      },
    );
  }

  Widget _buildScaffoldContent(PlayerGameAnalytics analytics) {
    return Column(
      children: [
        _buildSubTabSelector(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _selectedSubTab == 0
                ? _buildStatsTab(analytics)
                : _selectedSubTab == 1
                    ? _buildHistoryTab(analytics)
                    : _buildLeaderboardTab(),
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF14241B),
      child: Row(
        children: [
          _buildPill(0, 'পরিসংখ্যান (Stats)', Icons.insights_rounded),
          const SizedBox(width: 8),
          _buildPill(1, 'ম্যাচ হিস্টোরি (History)', Icons.history_rounded),
          const SizedBox(width: 8),
          _buildPill(2, 'ট্যুর লিডারবোর্ড', Icons.leaderboard_rounded),
        ],
      ),
    );
  }

  Widget _buildPill(int index, String label, IconData icon) {
    final isSelected = _selectedSubTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _selectedSubTab = index);
          if (index == 2 && _leaderboardEntries == null) {
            _loadLeaderboard();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.mintGreen
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.mintGreen
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? const Color(0xFF0F1E14)
                    : Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF0F1E14)
                        : Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── TAB 0: STATS BREAKDOWN ──────────────────────────────────────────────

  Widget _buildStatsTab(PlayerGameAnalytics analytics) {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverviewCard(analytics),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.sports_esports_rounded,
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        analytics.favoriteGame != null
                          ? 'পছন্দের খেলা: ${analytics.favoriteGame!.label}'
                          : 'সকল খেলার সার্বিক ট্রফি',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
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
                  border: Border.all(
                      color: AppColors.mintGreen.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${analytics.overallWinRate.toStringAsFixed(0)}% Win',
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
              _buildMetricItem(
                label: 'মোট ম্যাচ',
                value: '${analytics.totalMatches}',
                icon: Icons.games_rounded,
              ),
              _buildMetricItem(
                label: 'মোট জয়',
                value: '${analytics.totalWins}',
                icon: Icons.emoji_events_rounded,
                color: Colors.amber,
              ),
              _buildMetricItem(
                label: 'সেরা স্ট্রিক',
                value: '${analytics.bestOverallStreak}',
                icon: Icons.local_fire_department_rounded,
                color: Colors.orangeAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required IconData icon,
    Color color = AppColors.mintGreen,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildGameStatCard(GameStatItem stat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(stat.rankIcon, color: AppColors.mintGreen, size: 20),
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

  // ── TAB 1: MATCH HISTORY ────────────────────────────────────────────────

  Widget _buildHistoryTab(PlayerGameAnalytics analytics) {
    if (analytics.recentMatches.isEmpty) {
      return Center(
        key: const ValueKey(1),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                size: 64,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              const Text(
                'কোনো ম্যাচ হিস্টোরি পাওয়া যায়নি',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Game Zone এ অনলাইন টেবিল অথবা অফলাইন আর্কেড খেললে আপনার সাম্প্রতিক ম্যাচের বিবরণ এখানে জমা হবে।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey(1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: analytics.recentMatches.length,
      itemBuilder: (context, index) {
        final record = analytics.recentMatches[index];
        final isWon = record.won;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isWon
                  ? AppColors.mintGreen.withValues(alpha: 0.3)
                  : Colors.redAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isWon
                      ? AppColors.mintGreen.withValues(alpha: 0.15)
                      : Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWon ? Icons.emoji_events_rounded : Icons.close_rounded,
                  color: isWon ? AppColors.mintGreen : Colors.redAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          record.gameType.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isWon
                                ? AppColors.mintGreen.withValues(alpha: 0.2)
                                : Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isWon ? 'WON' : 'LOST',
                            style: TextStyle(
                              color: isWon
                                  ? AppColors.mintGreen
                                  : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.details ?? record.mode,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (record.score > 0)
                    Text(
                      '${record.score} pts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    _formatTimeAgo(record.timestamp),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
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

  // ── TAB 2: TOUR LEADERBOARD ─────────────────────────────────────────────

  Widget _buildLeaderboardTab() {
    if (widget.activeTourId == null) {
      return Center(
        key: const ValueKey(2),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_rounded,
                size: 64,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              const Text(
                'ট্যুর লিডারবোর্ড সক্রিয় নয়',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'একটি সক্রিয় ট্যুর গ্রুপে যুক্ত থাকলে দলের সকল ভ্রমণসঙ্গীদের গেম পারফরম্যান্স এবং চ্যাম্পিয়ন র‍্যাংকিং এখানে দেখতে পাবেন।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingLeaderboard) {
      return const Center(
        key: ValueKey(2),
        child: CircularProgressIndicator(color: AppColors.mintGreen),
      );
    }

    final entries = _leaderboardEntries ?? [];
    if (entries.isEmpty) {
      return Center(
        key: const ValueKey(2),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.leaderboard_rounded,
                size: 64,
                color: Colors.white24,
              ),
              const SizedBox(height: 16),
              const Text(
                'এখনও লিডারবোর্ড স্কোর নেই',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ট্যুর গ্রুপের সদস্যরা অনলাইন টেবিল খেললে তাদের স্কোর ও ট্রফি লিডারবোর্ডে যুক্ত হবে।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadLeaderboard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mintGreen,
                  foregroundColor: const Color(0xFF0F1E14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('রিফ্রেশ করুন'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      key: const ValueKey(2),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Top Champion Banner
        if (entries.isNotEmpty && entries.first.totalWins > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A2410), Color(0xFF14241B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Text('👑', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ট্যুর চ্যাম্পিয়ন (Tour Champion)',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entries.first.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${entries.first.totalWins} জয় • ${entries.first.winRate.toStringAsFixed(0)}% উইন রেট',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Member Leaderboard Rows
        ...entries.asMap().entries.map((item) {
          final rank = item.key + 1;
          final entry = item.value;
          final medal = rank == 1
              ? '🥇'
              : rank == 2
                  ? '🥈'
                  : rank == 3
                      ? '🥉'
                      : '#$rank';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF14241B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: rank <= 3
                    ? Colors.amber.withValues(alpha: 0.25)
                    : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    medal,
                    style: TextStyle(
                      fontSize: rank <= 3 ? 18 : 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.mintGreen.withValues(alpha: 0.2),
                  backgroundImage: entry.photoUrl != null
                      ? NetworkImage(entry.photoUrl!)
                      : null,
                  child: entry.photoUrl == null
                      ? Text(
                          entry.displayName.isNotEmpty
                              ? entry.displayName.substring(0, 1).toUpperCase()
                              : 'T',
                          style: const TextStyle(
                            color: AppColors.mintGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        entry.favoriteGame != null
                            ? '${entry.rankBadge} • ${entry.favoriteGame!.label}'
                            : entry.rankBadge,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${entry.totalWins} জয়',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${entry.totalMatches} ম্যাচ (${entry.winRate.toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  static String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
