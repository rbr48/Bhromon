import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../common/in_game_voice_bar.dart';
import '../common/playing_card_view.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';
import '../teen_patti/teen_patti_game.dart';

class OnlineTeenPattiView extends StatefulWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  const OnlineTeenPattiView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  @override
  State<OnlineTeenPattiView> createState() => _OnlineTeenPattiViewState();
}

class _OnlineTeenPattiViewState extends State<OnlineTeenPattiView> {
  late final TeenPattiGame _game;
  int _lastSyncedVersion = -1;
  bool _seeCardsLocally = false;

  int get _mySeatIndex =>
      widget.session.playerByEmail(widget.myEmail)?.seatIndex ?? 0;

  bool get _isMyTurn => widget.session.currentTurn == _mySeatIndex;

  bool get _isHost => widget.session.hostEmail == widget.myEmail;

  @override
  void initState() {
    super.initState();
    _game = TeenPattiGame();
    _syncFromSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant OnlineTeenPattiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.version != _lastSyncedVersion) {
      _syncFromSession(widget.session);
    }
  }

  void _syncFromSession(OnlineGameSession session) {
    _lastSyncedVersion = session.version;
    final state = session.state;

    _game.pot = (state['pot'] as num?)?.toInt() ?? 0;
    _game.baseBet = (state['baseBet'] as num?)?.toInt() ?? TeenPattiGame.startingBase;
    _game.currentTurn = (state['currentTurn'] as num?)?.toInt() ?? 0;

    final phaseName = state['phase'] as String?;
    if (phaseName != null) {
      _game.phase = TeenPattiPhase.values.firstWhere(
        (p) => p.name == phaseName,
        orElse: () => TeenPattiPhase.betting,
      );
    }

    // Bot automation on host device
    final currentPlayer = session.playerAt(_game.currentTurn);
    if (_isHost &&
        currentPlayer != null &&
        currentPlayer.isBot &&
        session.status == GameSessionStatus.inProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleBotTurn();
      });
    }

    if (mounted) setState(() {});
  }

  Future<void> _handleBotTurn() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || widget.session.version != _lastSyncedVersion) return;

    final bot = _game.players[_game.currentTurn];
    if (bot.isFolded) return;

    if (_game.canBet(_game.currentTurn)) {
      _game.bet(_game.currentTurn);
    } else {
      _game.pack(_game.currentTurn);
    }

    await _commitGameState();
  }

  Future<void> _actionBet() async {
    if (!_isMyTurn || !_game.canBet(_mySeatIndex)) return;
    HapticFeedback.lightImpact();

    _game.bet(_mySeatIndex);
    await _commitGameState();
  }

  Future<void> _actionRaise() async {
    if (!_isMyTurn || !_game.canRaise(_mySeatIndex)) return;
    HapticFeedback.mediumImpact();

    _game.raise(_mySeatIndex);
    await _commitGameState();
  }

  Future<void> _actionPack() async {
    if (!_isMyTurn) return;
    HapticFeedback.lightImpact();

    _game.pack(_mySeatIndex);
    await _commitGameState();
  }

  Future<void> _actionShow() async {
    if (!_isMyTurn || !_game.canShow(_mySeatIndex)) return;
    HapticFeedback.heavyImpact();

    _game.show(_mySeatIndex);
    await _commitGameState();
  }

  Future<void> _commitGameState() async {
    final newState = {
      'phase': _game.phase.name,
      'pot': _game.pot,
      'baseBet': _game.baseBet,
      'currentTurn': _game.currentTurn,
    };

    final isFinished = _game.isRoundOver;
    final winnerSeat = _game.result?.winnerIds.isNotEmpty == true
        ? _game.result!.winnerIds.first
        : null;

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: {'type': 'betting_action'},
      newState: newState,
      nextTurn: _game.currentTurn,
      winnerSeat: winnerSeat,
      isFinished: isFinished,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myPlayer = _game.players[_mySeatIndex];
    final activePlayer = widget.session.playerAt(_game.currentTurn);

    return Column(
      children: [
        // Voice Bar
        InGameVoiceBar(
          tourId: widget.session.tourId,
          gameId: widget.session.id,
          myEmail: widget.myEmail,
          myDisplayName: widget.repository.currentDisplayName,
          myPhotoUrl: widget.repository.currentPhotoUrl,
          myUid: widget.repository.currentUid,
        ),

        // Pot & Turn Header
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isMyTurn ? AppColors.mintGreen : Colors.white12,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.monetization_on_rounded,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Pot: ${_game.pot} Chips',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isMyTurn
                      ? AppColors.mintGreen.withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isMyTurn
                      ? 'YOUR TURN'
                      : "${activePlayer?.displayName ?? 'Seat ${_game.currentTurn + 1}'}'s turn",
                  style: TextStyle(
                    color: _isMyTurn ? AppColors.mintGreen : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Green Poker Felt Table
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B4332), // Felt
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2D6A4F), width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Table branding
                const Text(
                  'TEEN PATTI TABLE',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),

                // Player cards in center when seen
                if (_seeCardsLocally && myPlayer.hand.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: myPlayer.hand.map((card) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: PlayingCardView(
                          rank: card.rank,
                          suitSymbol: card.suitSymbol,
                          isRed: card.suit == 'H' || card.suit == 'D',
                          width: 58,
                          height: 84,
                        ),
                      );
                    }).toList(),
                  ),

                // Round Result Overlay if finished
                if (_game.result != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            color: Colors.amber, size: 36),
                        const SizedBox(height: 6),
                        Text(
                          _game.result!.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _game.result!.detail,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Card peek & Bet controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _seeCardsLocally = !_seeCardsLocally;
                    if (_seeCardsLocally) {
                      _game.see(_mySeatIndex);
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _seeCardsLocally
                      ? Colors.amber
                      : const Color(0xFF233F2E),
                  foregroundColor:
                      _seeCardsLocally ? Colors.black87 : Colors.white,
                ),
                icon: Icon(
                  _seeCardsLocally
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 16,
                ),
                label: Text(_seeCardsLocally ? 'Hide' : 'See Cards'),
              ),
              const Spacer(),
              if (_isMyTurn) ...[
                TextButton(
                  onPressed: _actionPack,
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: const Text('Pack'),
                ),
                if (_game.canRaise(_mySeatIndex))
                  TextButton(
                    onPressed: _actionRaise,
                    style: TextButton.styleFrom(foregroundColor: Colors.amber),
                    child: const Text('Raise'),
                  ),
                if (_game.canShow(_mySeatIndex))
                  ElevatedButton(
                    onPressed: _actionShow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Show'),
                  ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: _actionBet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mintGreen,
                    foregroundColor: Colors.black87,
                  ),
                  child: Text(myPlayer.isSeen ? 'Chaal' : 'Blind'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
