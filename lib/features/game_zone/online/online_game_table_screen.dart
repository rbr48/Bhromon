import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/colors.dart';
import '../../../core/utils/app_logger.dart';
import '../common/game_zone_portrait_lock.dart';
import '../data/game_analytics_service.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';
import 'online_card29_view.dart';
import 'online_carrom_view.dart';
import 'online_chess_view.dart';
import 'online_ludo_view.dart';
import 'online_table_lobby_view.dart';
import 'online_teen_patti_view.dart';

class OnlineGameTableScreen extends StatefulWidget {
  final String tourId;
  final String gameId;
  final OnlineGameRepository? repository;

  const OnlineGameTableScreen({
    super.key,
    required this.tourId,
    required this.gameId,
    this.repository,
  });

  @override
  State<OnlineGameTableScreen> createState() => _OnlineGameTableScreenState();
}

class _OnlineGameTableScreenState extends State<OnlineGameTableScreen>
    with GameZonePortraitLock {
  late final OnlineGameRepository _repository =
      widget.repository ?? OnlineGameRepository();
  final Set<String> _recordedSessionIds = {};

  String get _myEmail => _repository.currentEmail;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OnlineGameSession?>(
      stream: _repository.watchGame(widget.tourId, widget.gameId),
      builder: (context, snapshot) {
        final session = snapshot.data;

        if (session != null &&
            session.status == GameSessionStatus.finished &&
            session.winnerSeat != null &&
            !_recordedSessionIds.contains(session.id)) {
          _recordedSessionIds.add(session.id);
          final myPlayer =
              session.players.where((p) => p.email == _myEmail).firstOrNull;
          if (myPlayer != null) {
            final won = myPlayer.seatIndex == session.winnerSeat;
            GameAnalyticsService().recordMatch(
              gameType: session.gameType,
              won: won,
            );
          }
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F1E14),
            body: Center(
              child: CircularProgressIndicator(color: AppColors.mintGreen),
            ),
          );
        }

        if (session == null) {
          final canPop = Navigator.of(context).canPop();
          return PopScope(
            canPop: canPop,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              try {
                context.go('/game-zone');
              } catch (error, stackTrace) {
                logSkipped(error, stackTrace);
              }
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0F1E14),
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      try {
                        context.go('/game-zone');
                      } catch (error, stackTrace) {
                        logSkipped(error, stackTrace);
                      }
                    }
                  },
                ),
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.table_restaurant_outlined,
                        color: Colors.white38, size: 54),
                    const SizedBox(height: 16),
                    const Text(
                      'This table is no longer available.',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          try {
                            context.go('/game-zone');
                          } catch (error, stackTrace) {
                            logSkipped(error, stackTrace);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.mintGreen,
                        foregroundColor: Colors.black87,
                      ),
                      child: const Text('Back to Game Zone'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _confirmLeaveTable(session);
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0B1710),
              appBar: AppBar(
                backgroundColor: const Color(0xFF14241B),
                elevation: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.tableName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${session.gameType.label} • ${session.status.name.toUpperCase()}',
                      style: const TextStyle(
                        color: AppColors.mintGreen,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                leading: IconButton(
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => _confirmLeaveTable(session),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.exit_to_app_rounded,
                        color: Colors.white70),
                    tooltip: 'Leave Table',
                    onPressed: () => _confirmLeaveTable(session),
                  ),
                ],
              ),
              body: SafeArea(
                child: _buildSessionBody(session),
              ),
            ));
      },
    );
  }

  Widget _buildSessionBody(OnlineGameSession session) {
    if (session.status == GameSessionStatus.waiting) {
      return OnlineTableLobbyView(
        session: session,
        repository: _repository,
        myEmail: _myEmail,
        onStartGame: () => _startGame(session),
      );
    }

    // Active or Finished match: render corresponding online game view
    switch (session.gameType) {
      case OnlineGameType.chess:
        return OnlineChessView(
          session: session,
          repository: _repository,
          myEmail: _myEmail,
        );
      case OnlineGameType.ludo:
        return OnlineLudoView(
          session: session,
          repository: _repository,
          myEmail: _myEmail,
        );
      case OnlineGameType.carrom:
        return OnlineCarromView(
          session: session,
          repository: _repository,
          myEmail: _myEmail,
        );
      case OnlineGameType.card29:
        return OnlineCard29View(
          session: session,
          repository: _repository,
          myEmail: _myEmail,
        );
      case OnlineGameType.teenPatti:
        return OnlineTeenPattiView(
          session: session,
          repository: _repository,
          myEmail: _myEmail,
        );
    }
  }

  Future<void> _startGame(OnlineGameSession session) async {
    // The server deals and runs the 29 and Teen Patti tables, so the phone only
    // asks it to start.
    if (session.gameType == OnlineGameType.card29) {
      await _repository.start29Table(
        tourId: session.tourId,
        gameId: session.id,
      );
      return;
    }
    if (session.gameType == OnlineGameType.teenPatti) {
      await _repository.startTeenPattiTable(
        tourId: session.tourId,
        gameId: session.id,
      );
      return;
    }
    if (session.gameType == OnlineGameType.carrom) {
      await _repository.startCarromTable(
        tourId: session.tourId,
        gameId: session.id,
      );
      return;
    }

    Map<String, dynamic> initialState = {};

    switch (session.gameType) {
      case OnlineGameType.chess:
        initialState = {
          'moves': <Map<String, dynamic>>[],
          'turn': 'white',
          'isCheck': false,
          'isCheckmate': false,
          'isDraw': false,
        };
        break;
      case OnlineGameType.ludo:
        initialState = {
          'currentTurnColor': 'red',
          'currentDice': null,
          'hasRolled': false,
          'consecutiveSixes': 0,
        };
        break;
      case OnlineGameType.carrom:
        // Laid out by the server (see the early return above).
        break;
      case OnlineGameType.card29:
        // Dealt by the server (see the early return above).
        break;
      case OnlineGameType.teenPatti:
        // Dealt by the server (see the early return above).
        break;
    }

    await _repository.startGameSession(
      tourId: session.tourId,
      gameId: session.id,
      initialState: initialState,
    );
  }

  Future<void> _confirmLeaveTable(OnlineGameSession session) async {
    if (session.status == GameSessionStatus.inProgress) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF14241B),
          title:
              const Text('Leave Table?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'The match is currently in progress. If you leave now, you forfeit your seat.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Leave'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    await _repository.leaveGameSession(
      tourId: session.tourId,
      gameId: session.id,
    );

    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        try {
          context.go('/game-zone');
        } catch (error, stackTrace) {
          logSkipped(error, stackTrace);
        }
      }
    }
  }
}
