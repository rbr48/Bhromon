import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import 'package:bhromon/features/tour_group/data/tour_group_repository.dart';
import 'package:bhromon/features/tour_group/domain/models/tour_group.dart';
import 'package:bhromon/features/tour_group/domain/services/tour_choice.dart';
import 'package:bhromon/features/tour_group/presentation/tour_routes.dart';
import 'data/online_game_repository.dart';
import 'domain/models/online_game_session.dart';
import 'online/online_game_create_dialog.dart';
import 'presentation/widgets/game_analytics_view.dart';

enum GameCategory { all, cards, board, arcade }

class ArcadeGameItem {
  final String id;
  final String title;
  final String titleBn;
  final String description;
  final IconData icon;
  final String tag;
  final Color tagColor;
  final String players;
  final String highlight;
  final List<Color> gradient;
  final Color glowColor;
  final String route;
  final GameCategory category;

  const ArcadeGameItem({
    required this.id,
    required this.title,
    required this.titleBn,
    required this.description,
    required this.icon,
    required this.tag,
    required this.tagColor,
    required this.players,
    required this.highlight,
    required this.gradient,
    required this.glowColor,
    required this.route,
    required this.category,
  });
}

class GameZoneHubScreen extends StatefulWidget {
  final OnlineGameRepository? gameRepository;
  final TourGroupRepository? tourRepository;

  /// The tour the user opened the games from, if any.
  final String? initialTourId;

  const GameZoneHubScreen({
    super.key,
    this.gameRepository,
    this.tourRepository,
    this.initialTourId,
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
  late final Stream<List<TourGroup>> _groupsStream;

  String? _gamesStreamTourId;
  Stream<List<OnlineGameSession>>? _activeGamesStream;

  GameCategory _selectedCategory = GameCategory.all;
  bool _isCompactView = false;

  static const List<ArcadeGameItem> _games = [
    ArcadeGameItem(
      id: 'card29',
      title: 'Card 29 (টোয়েন্টি নাইন)',
      titleBn: 'টোয়েন্টি নাইন',
      description:
          'South Asian 32-card trick-taking game. Bid 16–28, reveal trump, and team up with smart AI partner.',
      icon: Icons.style_rounded,
      tag: 'CROWD FAVORITE',
      tagColor: Color(0xFFFF5252),
      players: '👥 4 Players • 2 Teams',
      highlight: '32 Cards • Bid 16-28',
      gradient: [Color(0xFF14301C), Color(0xFF09160D)],
      glowColor: Color(0xFF2E7D32),
      route: '/game-zone/card29',
      category: GameCategory.cards,
    ),
    ArcadeGameItem(
      id: 'chess',
      title: 'Travel Chess AI',
      titleBn: 'দাবা',
      description:
          'Sharpen your mind with tactical road battles against our Minimax engine with takeback, move history & clocks.',
      icon: Icons.psychology_rounded,
      tag: 'TACTICAL STRATEGY',
      tagColor: Color(0xFF448AFF),
      players: '🧠 1 vs 1 • Minimax AI',
      highlight: '3 Difficulty Levels',
      gradient: [Color(0xFF132435), Color(0xFF0A131C)],
      glowColor: Color(0xFF1976D2),
      route: '/game-zone/chess',
      category: GameCategory.board,
    ),
    ArcadeGameItem(
      id: 'ludo',
      title: 'Ludo Express',
      titleBn: 'লুডো',
      description:
          'Roll the dice, race 4 tokens to home base, and knock out companions. 3-sixes rule, safe squares & pass-and-play.',
      icon: Icons.casino_rounded,
      tag: 'FAMILY CLASSIC',
      tagColor: Color(0xFFFFB300),
      players: '🎲 2-4 Players • Pass & Play',
      highlight: '3 Sixes & Auto Knockout',
      gradient: [Color(0xFF2F1F17), Color(0xFF150D0A)],
      glowColor: Color(0xFFD84315),
      route: '/game-zone/ludo',
      category: GameCategory.board,
    ),
    ArcadeGameItem(
      id: 'teen_patti',
      title: 'Teen Patti (তিন পাত্তি)',
      titleBn: 'তিন পাত্তি',
      description:
          'Authentic South Asian 3-card poker. Play blind or seen, manage chips, request sideshows & win with Trail & Sequence.',
      icon: Icons.filter_3_rounded,
      tag: 'DESI POKER',
      tagColor: Color(0xFF00E676),
      players: '🃏 3-6 Players • AI Bots',
      highlight: 'Sideshow • Blind & Chaal',
      gradient: [Color(0xFF112E24), Color(0xFF081611)],
      glowColor: Color(0xFF00BFA5),
      route: '/game-zone/teen-patti',
      category: GameCategory.cards,
    ),
    ArcadeGameItem(
      id: 'carrom',
      title: 'Carrom (ক্যারম)',
      titleBn: 'ক্যারম',
      description:
          'Flick the striker on a realistic physics board. Sink coins, cover the Queen, and challenge the bot or pass the phone.',
      icon: Icons.adjust_rounded,
      tag: 'PHYSICS ARCADE',
      tagColor: Color(0xFFFF9100),
      players: '🎯 2-4 Players • Pass / Bot',
      highlight: 'Queen Cover • Real Physics',
      gradient: [Color(0xFF332015), Color(0xFF170D08)],
      glowColor: Color(0xFFE65100),
      route: '/game-zone/carrom',
      category: GameCategory.arcade,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _groupsStream = _tourRepo.watchMyGroups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        try {
          context.go(tourHubPath(widget.initialTourId));
        } catch (_) {}
      },
      child: StreamBuilder<List<TourGroup>>(
        stream: _groupsStream,
        builder: (context, groupSnapshot) {
          final groups = groupSnapshot.data ?? [];
          final activeTour = pickTour(groups, [widget.initialTourId]);

          return Scaffold(
            backgroundColor: const Color(0xFF0D1711),
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white70, size: 18),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    try {
                      context.go(tourHubPath(widget.initialTourId));
                    } catch (_) {}
                  }
                },
              ),
              title: const Text(
                'Travel GameZone',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              centerTitle: true,
              backgroundColor: const Color(0xFF122218),
              foregroundColor: Colors.white,
              elevation: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
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
                        Tab(
                          icon: Icon(Icons.insights_rounded, size: 20),
                          text: 'Stats & Trophies',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOfflineArcade(context),
                    _buildOnlineTablesTab(context, groupSnapshot, activeTour),
                    GameAnalyticsView(
                      activeTourId: activeTour?.id,
                      tourRepository: _tourRepo,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- TAB 1: OFFLINE ARCADE ---

  Widget _buildOfflineArcade(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final filteredGames = _games.where((g) {
          if (_selectedCategory == GameCategory.all) return true;
          return g.category == _selectedCategory;
        }).toList();

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // 1. Sleek Spotlight Console Banner
              _buildSpotlightBanner(context),
              const SizedBox(height: 16),

              // 2. Filter chips & View Switcher Bar
              _buildFilterAndToolbar(context, isWide),
              const SizedBox(height: 12),

              // 3. Game Cards Grid or List
              if (isWide && !_isCompactView)
                _buildWideGrid(context, filteredGames)
              else if (_isCompactView)
                _buildCompactList(context, filteredGames)
              else
                _buildMobileCardList(context, filteredGames),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  // --- SPOTLIGHT BANNER ---
  Widget _buildSpotlightBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF142B1E), Color(0xFF0C1911)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.mintGreen.withValues(alpha: 0.28),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.mintGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D6A4F), Color(0xFF1B4332)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.mintGreen.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.mintGreen.withValues(alpha: 0.2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.sports_esports_rounded,
              color: AppColors.mintGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Offline Arcade Hub',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded,
                              size: 11, color: AppColors.mintGreen),
                          Text(
                            '100% OFFLINE',
                            style: TextStyle(
                              color: AppColors.mintGreen,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Zero internet required. Built for scenic bus rides, camping nights & flights.',
                  style: TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- FILTER & TOOLBAR ---
  Widget _buildFilterAndToolbar(BuildContext context, bool isWide) {
    final categories = [
      {'cat': GameCategory.all, 'label': 'All (5)'},
      {'cat': GameCategory.cards, 'label': 'Cards (2)'},
      {'cat': GameCategory.board, 'label': 'Board & AI (2)'},
      {'cat': GameCategory.arcade, 'label': 'Arcade (1)'},
    ];

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((c) {
                final cat = c['cat'] as GameCategory;
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(c['label'] as String),
                    selected: isSelected,
                    showCheckmark: false,
                    backgroundColor: const Color(0xFF142017),
                    selectedColor: AppColors.mintGreen.withValues(alpha: 0.22),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.mintGreen
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.mintGreen : Colors.white70,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Layout switcher button
        IconButton(
          icon: Icon(
            _isCompactView
                ? Icons.grid_view_rounded
                : Icons.view_agenda_rounded,
            color: Colors.white60,
            size: 20,
          ),
          tooltip: _isCompactView ? 'Grid View' : 'Compact List',
          onPressed: () => setState(() => _isCompactView = !_isCompactView),
        ),
      ],
    );
  }

  // --- WIDE 2-COLUMN GRID (FOR DESKTOP & TABLETS) ---
  Widget _buildWideGrid(BuildContext context, List<ArcadeGameItem> games) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: games.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.88,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        return _buildElevatedCard(context, games[index]);
      },
    );
  }

  // --- MOBILE STANDARD CARD LIST ---
  Widget _buildMobileCardList(
      BuildContext context, List<ArcadeGameItem> games) {
    return Column(
      children: games.map((g) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildElevatedCard(context, g),
        );
      }).toList(),
    );
  }

  // --- COMPACT DENSE LIST VIEW ---
  Widget _buildCompactList(BuildContext context, List<ArcadeGameItem> games) {
    return Column(
      children: games.map((g) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF132219),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: g.tagColor.withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push(g.route),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            g.tagColor.withValues(alpha: 0.28),
                            g.tagColor.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: g.tagColor.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Icon(g.icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${g.players} • ${g.highlight}',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: g.tagColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: g.tagColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              size: 14, color: g.tagColor),
                          const SizedBox(width: 2),
                          Text(
                            'PLAY',
                            style: TextStyle(
                              color: g.tagColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- SOPHISTICATED ELEVATED GAME CARD ---
  Widget _buildElevatedCard(BuildContext context, ArcadeGameItem item) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: item.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.tagColor.withValues(alpha: 0.32),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: item.tagColor.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(item.route),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top row: Squircle icon, category tag, play button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            item.tagColor.withValues(alpha: 0.35),
                            item.tagColor.withValues(alpha: 0.12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.tagColor.withValues(alpha: 0.45),
                          width: 1.0,
                        ),
                      ),
                      child: Icon(item.icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.tagColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: item.tagColor.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  item.tag,
                                  style: TextStyle(
                                    color: item.tagColor,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.players,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.tagColor.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: item.tagColor.withValues(alpha: 0.45),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              size: 14, color: item.tagColor),
                          const SizedBox(width: 2),
                          Text(
                            'PLAY',
                            style: TextStyle(
                              color: item.tagColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Middle: Bilingual Title & Subtitle
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),

                // Bottom feature chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stars_rounded, size: 11, color: item.tagColor),
                      const SizedBox(width: 4),
                      Text(
                        item.highlight,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 2: ONLINE TOUR TABLES ---

  Widget _buildOnlineTablesTab(
    BuildContext context,
    AsyncSnapshot<List<TourGroup>> groupSnapshot,
    TourGroup? activeTour,
  ) {
    final groups = groupSnapshot.data ?? [];
    if (groupSnapshot.connectionState == ConnectionState.waiting &&
        groups.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mintGreen),
      );
    }

    if (activeTour == null) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

    if (_gamesStreamTourId != activeTour.id || _activeGamesStream == null) {
      _gamesStreamTourId = activeTour.id;
      _activeGamesStream = _gameRepo.watchActiveGames(activeTour.id);
    }

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
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
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
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 18),
                      label: const Text(
                        'Create Table',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showJoinByCodeDialog(context, activeTour.id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.pin_rounded,
                          size: 18, color: AppColors.mintGreen),
                      label: const Text(
                        'Join with Code',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
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
          stream: _activeGamesStream!,
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
              children:
                  sessions.map((s) => _buildTableCard(context, s)).toList(),
            );
          },
        ),
      ],
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
                          if (session.isTournament) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color:
                                        AppColors.gold.withValues(alpha: 0.5),
                                    width: 0.8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.emoji_events_rounded,
                                      size: 11, color: AppColors.gold),
                                  SizedBox(width: 3),
                                  Text(
                                    'TOURNAMENT',
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                                color:
                                    isPlaying ? Colors.redAccent : Colors.amber,
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
                    foregroundColor:
                        isSeated ? const Color(0xFF0F1E14) : Colors.white,
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

  void _showJoinByCodeDialog(BuildContext context, String tourId) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF14241B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(Icons.pin_rounded, color: AppColors.mintGreen),
            SizedBox(width: 8),
            Text(
              'Join with Code',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Table Code or paste the invite shared by your host:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'e.g. 7kX9qLm...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded,
                      color: AppColors.mintGreen, size: 20),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && data!.text!.trim().isNotEmpty) {
                      final text = data.text!.trim();
                      final match =
                          RegExp(r'[a-zA-Z0-9_-]{10,}').firstMatch(text);
                      controller.text = match != null ? match.group(0)! : text;
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: const Color(0xFF0F1E14),
            ),
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.of(dialogCtx).pop();

              try {
                await _gameRepo.joinGameSession(
                  tourId: tourId,
                  gameId: code,
                );
                if (context.mounted) {
                  context.push('/game-zone/table/$tourId/$code');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not join table: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Join Table',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
