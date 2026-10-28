import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/entities/explorer_profile.dart';
import '../../domain/usecases/get_top_explorers_usecase.dart';
import '../../../../core/utils/image_sizing.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  // Created once: a future built inside build() refetches on every rebuild.
  late final Future<dynamic> _topExplorers =
      getIt<GetTopExplorersUseCase>()(20);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/group-hub');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050C08), // dark green-black background
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A140D),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 18),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            },
          ),
        title: const Text(
          'EXPLORER LEADERBOARD',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<dynamic>(
            future: _topExplorers,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.mintGreen),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Failed to load leaderboard: ${snapshot.error}',
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                );
              }

              final result = snapshot.data;
              List<ExplorerProfile> profiles = [];

              if (result != null) {
                result.fold(
                  (Object? failure) =>
                      debugPrint('Error fetching leaderboard: $failure'),
                  (Object? list) {
                    if (list is List<ExplorerProfile>) {
                      profiles = list;
                    }
                  },
                );
              }

              if (profiles.isEmpty) {
                return const Center(
                  child: Text(
                    'No explorers found in leaderboard yet.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: profiles.length,
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  final score = profile.explorerScore.value;
                  final rank = index + 1;

                  // Top 3 style decorations
                  Widget rankWidget;
                  Color itemBg = const Color(0xFF0D1A12);
                  Border? itemBorder;

                  if (rank == 1) {
                    rankWidget =
                        const Text('🏆', style: TextStyle(fontSize: 22));
                    itemBg = const Color(0xFF1B3825);
                    itemBorder = Border.all(
                        color: const Color(0xFFF4A261).withValues(alpha: 0.5),
                        width: 1.5);
                  } else if (rank == 2) {
                    rankWidget =
                        const Text('🥈', style: TextStyle(fontSize: 20));
                    itemBg = const Color(0xFF14291B);
                    itemBorder = Border.all(
                        color: Colors.grey.withValues(alpha: 0.4), width: 1.2);
                  } else if (rank == 3) {
                    rankWidget =
                        const Text('🥉', style: TextStyle(fontSize: 18));
                    itemBg = const Color(0xFF102116);
                    itemBorder = Border.all(
                        color: const Color(0xFFCD7F32).withValues(alpha: 0.4),
                        width: 1);
                  } else {
                    rankWidget = CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF1E3A26),
                      child: Text(
                        rank.toString(),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    );
                  }

                  final name = profile.displayName;
                  final initials = name.isNotEmpty
                      ? name
                          .split(' ')
                          .map((e) => e.isNotEmpty ? e[0] : '')
                          .take(2)
                          .join()
                          .toUpperCase()
                      : 'EX';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: itemBg,
                      borderRadius: BorderRadius.circular(16),
                      border: itemBorder ??
                          Border.all(
                              color: const Color(0xFF1E3A26)
                                  .withValues(alpha: 0.5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 32, child: Center(child: rankWidget)),
                          const SizedBox(width: 12),
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF40916C),
                            backgroundImage: profile.avatarUrl != null &&
                                    profile.avatarUrl!.isNotEmpty
                                ? sizedImage(
                                    CachedNetworkImageProvider(
                                      profile.avatarUrl!,
                                      errorListener: (dynamic error) {},
                                    ),
                                    context.decodeWidth(40))
                                : null,
                            child: profile.avatarUrl == null ||
                                    profile.avatarUrl!.isEmpty
                                ? Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold))
                                : null,
                          ),
                        ],
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          color: rank <= 3
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.9),
                          fontWeight:
                              rank <= 3 ? FontWeight.w900 : FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          if (profile.isRegionExpert) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE76F51)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Expert',
                                style: TextStyle(
                                    color: Color(0xFFE76F51),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            profile.division,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$score XP',
                            style: const TextStyle(
                              color: AppColors.mintGreen,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            profile.tier.isVerifiedOrAbove
                                ? 'Verified'
                                : 'Community',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 9),
                          ),
                        ],
                      ),
                      onTap: () => context.push('/profile/${profile.uid}'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    ));
  }
}
