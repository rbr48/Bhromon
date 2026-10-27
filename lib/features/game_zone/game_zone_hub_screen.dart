import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/presentation/widgets/bhromon_bottom_nav.dart';
import 'data/online_game_repository.dart';
import 'domain/models/online_game_session.dart';
import 'online/online_game_create_dialog.dart';

class GameZoneHubScreen extends StatefulWidget {
  final OnlineGameRepository? gameRepository;
  final TourGroupRepository? tourRepository;

  const GameZoneHubScreen({
    super.key,
    this.gameRepository,
    this.tourRepository,
  });

  @override
  State<GameZoneHubScreen> createState() => _GameZoneHubScreenState();
}

class _GameZoneHubScreenState extends State<GameZoneHubScreen>
    with SingleTickerProviderStateMixin {
  late final OnlineGameRepository _gameRepo =
      widget.gameRepository ?? OnlineGameRepository();
  late final TourGroupRepository _tourRepo =
      widget.tourRepository ?? TourGroupRepository();

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101C14),
      appBar: AppBar(
        title: const Text(
          'Travel GameZone',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF14241B),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.mintGreen,
                labelColor: AppColors.mintGreen,
                unselectedLabelColor: Colors.white60,
                indicatorWeight: 3,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.offline_bolt_rounded, size: 20),
                    text: 'Offline Arcade',
                  ),
                  Tab(
                    icon: Icon(Icons.groups_rounded, size: 20),
                    text: 'Tour Online Tables',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOfflineArcade(context),
              _buildOnlineTablesTab(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BhromonBottomNav(selectedIndex: 3),
    );
  }

  // --- TAB 1: OFFLINE ARCADE ---

  Widget _buildOfflineArcade(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // Hero Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF193222), Color(0xFF0F1E14)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade400, Colors.amber.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.sports_esports,
                      color: Colors.black87, size: 32),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In-Transit Offline Arcade',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Zero internet required. Perfect for long scenic drives, mountain buses, and quiet nights at camp.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            'CHOOSE A GAME',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // 1. Card 29
          _buildGameCard(
            context,
            title: 'Card 29 (টোয়েন্টি নাইন)',
            subtitle:
                'Classic South Asian 32-card trick-taking game. Bid, set trump, and team up with your AI partner.',
            icon: Icons.style,
            tag: 'CROWD FAVORITE',
            tagColor: Colors.redAccent,
            gradient: const [Color(0xFF1B5E20), Color(0xFF0D3311)],
            route: '/game-zone/card29',
          ),
          const SizedBox(height: 14),

          // 2. Travel Chess AI
          _buildGameCard(
            context,
            title: 'Travel Chess AI',
            subtitle:
                'Sharpen your mind on the road against our built-in Minimax chess engine across 3 difficulty levels.',
            icon: Icons.psychology,
            tag: 'STRATEGY',
            tagColor: Colors.blueAccent,
            gradient: const [Color(0xFF263238), Color(0xFF10171A)],
            route: '/game-zone/chess',
          ),
          const SizedBox(height: 14),

          // 3. Ludo Express
          _buildGameCard(
            context,
            title: 'Ludo Express',
            subtitle:
                'Roll the dice, race your 4 tokens to home base, and knock out your companions in classic 4-player Ludo.',
            icon: Icons.casino,
            tag: 'CASUAL & FUN',
            tagColor: Colors.amber,
            gradient: const [Color(0xFF5D4037), Color(0xFF271C19)],
            route: '/game-zone/ludo',
          ),
          const SizedBox(height: 14),

          // 4. Teen Patti
          _buildGameCard(
            context,
            title: 'Teen Patti (তিন পাত্তি)',
            subtitle:
                'Classic South Asian 3-card poker. Play blind or seen, manage chips, and call showdowns with trail & pure sequence.',
            icon: Icons.filter_3,
            tag: 'DESI CLASSIC',
            tagColor: Colors.tealAccent,
            gradient: const [Color(0xFF004D40), Color(0xFF001F1A)],
            route: '/game-zone/teen-patti',
          ),
          const SizedBox(height: 14),

          // 5. Carrom
          _buildGameCard(
            context,
            title: 'Carrom (ক্যারম)',
            subtitle:
                'Flick the striker and sink your coins on a real-physics board. Cover the Queen, beat the bot or pass the phone.',
            icon: Icons.adjust,
            tag: 'FAMILY FAVORITE',
            tagColor: Colors.orangeAccent,
            gradient: const [Color(0xFF6D4C2E), Color(0xFF2B1A0E)],
            route: '/game-zone/carrom',
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String tag,
    required Color tagColor,
    required List<Color> gradient,
    required String route,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tagColor.withValues(alpha: 0.28), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: tagColor.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tagColor.withValues(alpha: 0.28),
                        tagColor.withValues(alpha: 0.10)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tagColor.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: tagColor.withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            color: tagColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 2: ONLINE TOUR TABLES ---

  Widget _buildOnlineTablesTab(BuildContext context) {
    return StreamBuilder<List<TourGroup>>(
      stream: _tourRepo.watchMyGroups(),
      builder: (context, groupSnapshot) {
        final groups = groupSnapshot.data ?? [];
        if (groupSnapshot.connectionState == ConnectionState.waiting &&
            groups.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.mintGreen),
          );
        }

        if (groups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.groups_outlined,
                      color: Colors.white38, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'No Active Tour Group',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Join or create a tour group to unlock online multiplayer with in-game voice chat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/group-hub'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: const Color(0xFF0F1E14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.hub_outlined),
                    label: const Text('Open Tours Hub'),
                  ),
                ],
              ),
            ),
          );
        }

        // Use the first active tour group
        final activeTour = groups.first;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            // Tour Banner & Host Table Action
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B3827), Color(0xFF102419)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.mintGreen.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.table_bar_rounded,
                            color: AppColors.mintGreen, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeTour.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Live multiplayer tables with voice chat',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      OnlineGameCreateDialog.show(
                        context,
                        tourId: activeTour.id,
                        repository: _gameRepo,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: const Color(0xFF0F1E14),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    label: const Text(
                      'Create New Game Table',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'ACTIVE TOUR TABLES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            // Active Games Stream
            StreamBuilder<List<OnlineGameSession>>(
              stream: _gameRepo.watchActiveGames(activeTour.id),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    sessions.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        color: AppColors.mintGreen,
                      ),
                    ),
                  );
                }

                if (sessions.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.table_restaurant_outlined,
                            color: Colors.white24, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No open game tables yet',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Create a table above and invite your tour group members to play!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: sessions.map((s) => _buildTableCard(context, s)).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableCard(BuildContext context, OnlineGameSession session) {
    final isPlaying = session.status == GameSessionStatus.inProgress;
    final isFull = session.isFull;
    final isSeated = session.playerByEmail(_gameRepo.currentEmail) != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSeated
              ? AppColors.mintGreen.withValues(alpha: 0.6)
              : Colors.white12,
          width: isSeated ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (!isSeated && !isFull) {
              await _gameRepo.joinGameSession(
                tourId: session.tourId,
                gameId: session.id,
              );
            }
            if (context.mounted) {
              context.push('/game-zone/table/${session.tourId}/${session.id}');
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.mintGreen.withValues(alpha: 0.15),
                  child: Icon(
                    _iconForGame(session.gameType),
                    color: AppColors.mintGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.tableName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isPlaying
                                  ? Colors.redAccent.withValues(alpha: 0.2)
                                  : Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPlaying ? 'IN MATCH' : 'OPEN LOBBY',
                              style: TextStyle(
                                color: isPlaying
                                    ? Colors.redAccent
                                    : Colors.amber,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session.gameType.label} • ${session.players.length}/${session.maxPlayers} Seated',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    if (!isSeated && !isFull) {
                      await _gameRepo.joinGameSession(
                        tourId: session.tourId,
                        gameId: session.id,
                      );
                    }
                    if (context.mounted) {
                      context.push(
                          '/game-zone/table/${session.tourId}/${session.id}');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSeated
                        ? AppColors.mintGreen
                        : const Color(0xFF233F2E),
                    foregroundColor: isSeated
                        ? const Color(0xFF0F1E14)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: Text(
                    isSeated ? 'Enter' : (isFull ? 'Watch' : 'Join'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForGame(OnlineGameType type) {
    switch (type) {
      case OnlineGameType.chess:
        return Icons.psychology_rounded;
      case OnlineGameType.ludo:
        return Icons.casino_rounded;
      case OnlineGameType.card29:
        return Icons.style_rounded;
      case OnlineGameType.teenPatti:
        return Icons.monetization_on_rounded;
      case OnlineGameType.carrom:
        return Icons.adjust_rounded;
    }
  }
}
