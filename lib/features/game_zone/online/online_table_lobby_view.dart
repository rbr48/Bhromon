import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../common/in_game_voice_bar.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';

class OnlineTableLobbyView extends StatelessWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;
  final VoidCallback onStartGame;

  const OnlineTableLobbyView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
    required this.onStartGame,
  });

  bool get _isHost => session.hostEmail == myEmail;

  @override
  Widget build(BuildContext context) {
    final maxPlayers = session.maxPlayers;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Voice Bar
          InGameVoiceBar(
            tourId: session.tourId,
            gameId: session.id,
            myEmail: myEmail,
            myDisplayName: repository.currentDisplayName,
            myPhotoUrl: repository.currentPhotoUrl,
            myUid: repository.currentUid,
            initialJoin: false,
          ),

          const SizedBox(height: 12),

          // Table Info Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3526), Color(0xFF112217)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.mintGreen.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.mintGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconForGame(session.gameType),
                    color: AppColors.mintGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.tableName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session.gameType.label} • ${session.players.length}/$maxPlayers Seated',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.amber.shade400, width: 0.8),
                  ),
                  child: const Text(
                    'LOBBY',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Seating Map Title
          const Row(
            children: [
              Icon(Icons.event_seat_rounded,
                  color: AppColors.mintGreen, size: 18),
              SizedBox(width: 8),
              Text(
                'TABLE SEATS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Seats Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: maxPlayers,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: maxPlayers > 2 ? 2 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            itemBuilder: (context, index) {
              final player = session.playerAt(index);
              final isMe = player?.email == myEmail;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: player != null
                      ? const Color(0xFF162B1E)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isMe
                        ? AppColors.mintGreen
                        : (player != null ? Colors.white24 : Colors.white10),
                    width: isMe ? 1.8 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: player != null
                              ? AppColors.mintGreen.withValues(alpha: 0.2)
                              : Colors.white10,
                          child: Icon(
                            player == null
                                ? Icons.chair_alt_rounded
                                : (player.isBot
                                    ? Icons.smart_toy_rounded
                                    : Icons.person_rounded),
                            color: player != null
                                ? (player.isBot
                                    ? Colors.amber
                                    : AppColors.mintGreen)
                                : Colors.white38,
                            size: 24,
                          ),
                        ),
                        if (player?.isHost == true)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.star_rounded,
                                color: Colors.black,
                                size: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      player?.displayName ?? 'Empty Seat',
                      style: TextStyle(
                        color: player != null ? Colors.white : Colors.white38,
                        fontSize: 13,
                        fontWeight: player != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player != null
                          ? (isMe
                              ? 'You (Seat ${index + 1})'
                              : (player.isBot
                                  ? 'Bot Player'
                                  : 'Seat ${index + 1}'))
                          : 'Seat ${index + 1}',
                      style: TextStyle(
                        color: isMe ? AppColors.mintGreen : Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Actions Panel
          if (_isHost) ...[
            if (session.players.length < maxPlayers)
              ElevatedButton.icon(
                onPressed: () async {
                  await repository.fillRemainingSeatsWithBots(
                    tourId: session.tourId,
                    gameId: session.id,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF233F2E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                icon: const Icon(Icons.smart_toy_rounded, color: Colors.amber),
                label: const Text(
                  'Fill Empty Seats with AI Bots',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: session.canStart ? onStartGame : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mintGreen,
                foregroundColor: const Color(0xFF0F1E14),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white38,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: const Text(
                'Start Match Now',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.mintGreen,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Waiting for the host to start the match...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
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
