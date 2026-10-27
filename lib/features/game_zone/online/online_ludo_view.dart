import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/in_game_voice_bar.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';
import '../ludo/ludo_engine.dart';

class OnlineLudoView extends StatefulWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  const OnlineLudoView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  @override
  State<OnlineLudoView> createState() => _OnlineLudoViewState();
}

class _OnlineLudoViewState extends State<OnlineLudoView> {
  late final LudoEngine _engine;
  int _lastSyncedVersion = -1;
  bool _isRolling = false;

  int get _mySeatIndex =>
      widget.session.playerByEmail(widget.myEmail)?.seatIndex ?? -1;

  bool get _isMyTurn => widget.session.currentTurn == _mySeatIndex;

  bool get _isHost => widget.session.hostEmail == widget.myEmail;

  LudoColor _colorForSeat(int seat) {
    switch (seat) {
      case 0:
        return LudoColor.red;
      case 1:
        return LudoColor.green;
      case 2:
        return LudoColor.yellow;
      case 3:
      default:
        return LudoColor.blue;
    }
  }

  @override
  void initState() {
    super.initState();
    _engine = LudoEngine();
    _syncFromSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant OnlineLudoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.version != _lastSyncedVersion) {
      _syncFromSession(widget.session);
    }
  }

  void _syncFromSession(OnlineGameSession session) {
    _lastSyncedVersion = session.version;
    final state = session.state;

    final currentTurnName = state['currentTurnColor'] as String?;
    if (currentTurnName != null) {
      _engine.currentTurn = LudoColor.values.firstWhere(
        (c) => c.name == currentTurnName,
        orElse: () => LudoColor.red,
      );
    }

    _engine.currentDice = state['currentDice'] as int?;
    _engine.hasRolled = state['hasRolled'] == true;
    _engine.consecutiveSixes =
        (state['consecutiveSixes'] as num?)?.toInt() ?? 0;

    final rawTokens = state['tokens'] as Map<String, dynamic>?;
    if (rawTokens != null) {
      for (final entry in rawTokens.entries) {
        final color = LudoColor.values.firstWhere(
          (c) => c.name == entry.key,
          orElse: () => LudoColor.red,
        );
        final list = entry.value as List<dynamic>? ?? [];
        for (int i = 0; i < list.length && i < 4; i++) {
          final m = list[i] as Map<String, dynamic>;
          final token = _engine.tokens[color]![i];
          token.state = TokenState.values.firstWhere(
            (s) => s.name == m['state'],
            orElse: () => TokenState.inYard,
          );
          token.stepCount = (m['step'] as num?)?.toInt() ?? 0;
        }
      }
    }

    // Check if it's a bot's turn and I am the host -> execute bot move
    final currentPlayer = session.playerAt(session.currentTurn);
    if (_isHost &&
        currentPlayer != null &&
        currentPlayer.isBot &&
        session.status == GameSessionStatus.inProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleBotTurn(session);
      });
    }

    if (mounted) setState(() {});
  }

  Future<void> _handleBotTurn(OnlineGameSession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || session.version != _lastSyncedVersion) return;

    if (!_engine.hasRolled) {
      final dice = _engine.rollDice();
      if (dice == -1) {
        // 3 consecutive sixes: forfeit turn
        await _passTurn(session);
        return;
      }

      final movable = _engine.getMovableTokens();
      if (movable.isEmpty) {
        await _passTurn(session);
      } else {
        await _commitRoll(dice);
      }
    } else {
      // Pick best token
      final movable = _engine.getMovableTokens();
      if (movable.isNotEmpty) {
        // Prefer moving piece out of yard on 6 or furthest forward
        movable.sort((a, b) => b.stepCount.compareTo(a.stepCount));
        await _commitTokenMove(movable.first);
      } else {
        await _passTurn(session);
      }
    }
  }

  Future<void> _rollDice() async {
    if (!_isMyTurn || _engine.hasRolled || _isRolling) return;

    setState(() => _isRolling = true);
    HapticFeedback.mediumImpact();

    final dice = _engine.rollDice();

    await _commitRoll(dice);
    setState(() => _isRolling = false);

    // If no movable tokens, pass turn automatically
    final movable = _engine.getMovableTokens();
    if (movable.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) await _passTurn(widget.session);
    }
  }

  Future<void> _commitRoll(int dice) async {
    final newState = _serializeState();
    newState['currentDice'] = dice;
    newState['hasRolled'] = true;

    final action = {
      'type': 'roll',
      'player': widget.myEmail,
      'dice': dice,
    };

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: action,
      newState: newState,
    );
  }

  Future<void> _onTokenTapped(LudoToken token) async {
    if (!_isMyTurn || !_engine.hasRolled || _engine.currentDice == null) return;
    if (!_engine.canMoveToken(token, _engine.currentDice!)) return;

    await _commitTokenMove(token);
  }

  Future<void> _commitTokenMove(LudoToken token) async {
    final extraTurn = _engine.moveToken(token);
    HapticFeedback.lightImpact();

    // Check winner
    final winnerColor = _checkWinner();
    final isFinished = winnerColor != null;
    int? winnerSeat;
    if (winnerColor != null) {
      winnerSeat = LudoColor.values.indexOf(winnerColor);
    }

    int nextSeat = widget.session.currentTurn;
    if (!extraTurn) {
      nextSeat = (widget.session.currentTurn + 1) % widget.session.maxPlayers;
      _engine.currentTurn = _colorForSeat(nextSeat);
      _engine.hasRolled = false;
      _engine.currentDice = null;
    } else {
      _engine.hasRolled = false;
      _engine.currentDice = null;
    }

    final newState = _serializeState();
    final action = {
      'type': 'move_token',
      'tokenId': token.id,
      'color': token.color.name,
      'extraTurn': extraTurn,
    };

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: action,
      newState: newState,
      nextTurn: nextSeat,
      winnerSeat: winnerSeat,
      isFinished: isFinished,
    );
  }

  Future<void> _passTurn(OnlineGameSession session) async {
    final nextSeat = (session.currentTurn + 1) % session.maxPlayers;
    _engine.currentTurn = _colorForSeat(nextSeat);
    _engine.hasRolled = false;
    _engine.currentDice = null;
    _engine.consecutiveSixes = 0;

    final newState = _serializeState();
    final action = {'type': 'pass_turn'};

    await widget.repository.commitAction(
      tourId: session.tourId,
      gameId: session.id,
      action: action,
      newState: newState,
      nextTurn: nextSeat,
    );
  }

  LudoColor? _checkWinner() {
    for (final color in LudoColor.values) {
      if (_engine.tokens[color]?.every((t) => t.state == TokenState.home) ==
          true) {
        return color;
      }
    }
    return null;
  }

  Map<String, dynamic> _serializeState() {
    return {
      'currentTurnColor': _engine.currentTurn.name,
      'currentDice': _engine.currentDice,
      'hasRolled': _engine.hasRolled,
      'consecutiveSixes': _engine.consecutiveSixes,
      'tokens': {
        for (final entry in _engine.tokens.entries)
          entry.key.name: entry.value
              .map((t) => {
                    'id': t.id,
                    'state': t.state.name,
                    'step': t.stepCount,
                  })
              .toList(),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentTurnColor = _colorForSeat(widget.session.currentTurn);
    final activePlayer = widget.session.playerAt(widget.session.currentTurn);

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

        // Players Turn & Dice Tray
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: currentTurnColor.color.withValues(alpha: 0.8),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: currentTurnColor.color,
                child: Text(
                  '${widget.session.currentTurn + 1}',
                  style: TextStyle(
                    color: currentTurnColor.onColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activePlayer?.displayName ?? currentTurnColor.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _isMyTurn
                          ? (_engine.hasRolled
                              ? 'Tap a glowing token to move'
                              : 'Your turn to roll!')
                          : 'Waiting for player move...',
                      style: TextStyle(
                        color: currentTurnColor.color,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Dice Display / Roll Button
              GestureDetector(
                onTap: _isMyTurn && !_engine.hasRolled ? _rollDice : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _engine.hasRolled
                        ? Colors.white
                        : (_isMyTurn ? currentTurnColor.color : Colors.white12),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      if (_isMyTurn && !_engine.hasRolled)
                        BoxShadow(
                          color: currentTurnColor.color.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _engine.currentDice != null
                      ? Text(
                          '${_engine.currentDice}',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : Icon(
                          Icons.casino_rounded,
                          color: _isMyTurn
                              ? currentTurnColor.onColor
                              : Colors.white38,
                          size: 26,
                        ),
                ),
              ),
            ],
          ),
        ),

        // Ludo Board Canvas
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildLudoGrid(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLudoGrid() {
    return Container(
      color: const Color(0xFFFBFBFB),
      child: Column(
        children: [
          // Top Row: Red Home (6x6), Green/Red Track (3x6), Green Home (6x6)
          Expanded(
            flex: 6,
            child: Row(
              children: [
                _buildHomeYard(LudoColor.red),
                _buildTrackColumn(isTop: true),
                _buildHomeYard(LudoColor.green),
              ],
            ),
          ),

          // Middle Row: Blue/Red Home Stretch (6x3), Center Home (3x3), Yellow/Green Home Stretch (6x3)
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _buildTrackRow(isLeft: true),
                _buildCenterHomeTriangle(),
                _buildTrackRow(isLeft: false),
              ],
            ),
          ),

          // Bottom Row: Blue Home (6x6), Blue/Yellow Track (3x6), Yellow Home (6x6)
          Expanded(
            flex: 6,
            child: Row(
              children: [
                _buildHomeYard(LudoColor.blue),
                _buildTrackColumn(isTop: false),
                _buildHomeYard(LudoColor.yellow),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeYard(LudoColor color) {
    final tokens = _engine.tokens[color] ?? [];
    final movable = _engine.getMovableTokens();

    return Expanded(
      flex: 6,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.color,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: tokens.map((token) {
                final isInYard = token.state == TokenState.inYard;
                final isMovable = _isMyTurn && movable.contains(token);

                return GestureDetector(
                  onTap: isMovable ? () => _onTokenTapped(token) : null,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isInYard ? color.color : Colors.grey.shade300,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isMovable ? Colors.amber : Colors.black26,
                        width: isMovable ? 3.0 : 1.2,
                      ),
                      boxShadow: [
                        if (isMovable)
                          const BoxShadow(
                            color: Colors.amber,
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterHomeTriangle() {
    return Expanded(
      flex: 3,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2C3E50),
        ),
        child: const Center(
          child: Icon(Icons.star_rounded, color: Colors.amber, size: 28),
        ),
      ),
    );
  }

  Widget _buildTrackColumn({required bool isTop}) {
    return Expanded(
      flex: 3,
      child: Container(
        color: Colors.white,
        child: Column(
          children: List.generate(6, (r) {
            return Expanded(
              child: Row(
                children: List.generate(3, (c) {
                  final isHomeStretch = c == 1;
                  final stretchColor =
                      isTop ? LudoColor.green.color : LudoColor.blue.color;

                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12, width: 0.5),
                        color: isHomeStretch
                            ? stretchColor.withValues(alpha: 0.35)
                            : Colors.white,
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTrackRow({required bool isLeft}) {
    return Expanded(
      flex: 6,
      child: Container(
        color: Colors.white,
        child: Row(
          children: List.generate(6, (c) {
            return Expanded(
              child: Column(
                children: List.generate(3, (r) {
                  final isHomeStretch = r == 1;
                  final stretchColor =
                      isLeft ? LudoColor.red.color : LudoColor.yellow.color;

                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12, width: 0.5),
                        color: isHomeStretch
                            ? stretchColor.withValues(alpha: 0.35)
                            : Colors.white,
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}
