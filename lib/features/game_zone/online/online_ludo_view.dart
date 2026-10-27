import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/in_game_voice_bar.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';
import '../ludo/ludo_board_painters.dart';
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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isMyTurn && !_engine.hasRolled
                          ? Colors.amberAccent
                          : Colors.black26,
                      width: _isMyTurn && !_engine.hasRolled ? 2.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isMyTurn && !_engine.hasRolled
                            ? Colors.amberAccent.withValues(alpha: 0.6)
                            : Colors.black.withValues(alpha: 0.2),
                        blurRadius: _isMyTurn && !_engine.hasRolled ? 10 : 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _engine.currentDice != null
                      ? CustomPaint(
                          size: const Size(44, 44),
                          painter: LudoDiceFacePainter(_engine.currentDice!),
                        )
                      : Icon(
                          Icons.casino_rounded,
                          color: _isMyTurn
                              ? currentTurnColor.color
                              : Colors.black38,
                          size: 30,
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
                  color: const Color(0xFFFBFBFB),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest.shortestSide;
                    final cellSize = size / 15.0;

                    return Stack(
                      children: [
                        // Background: yards (6x6), track arms (3x6 / 6x3) and center home (3x3).
                        Column(
                          children: [
                            Expanded(
                              flex: 6,
                              child: Row(
                                children: [
                                  _buildYard(LudoColor.red),
                                  _buildPathwaySection(flex: 3),
                                  _buildYard(LudoColor.green),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  _buildPathwaySection(flex: 6),
                                  _buildCenterHome(),
                                  _buildPathwaySection(flex: 6),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 6,
                              child: Row(
                                children: [
                                  _buildYard(LudoColor.blue),
                                  _buildPathwaySection(flex: 3),
                                  _buildYard(LudoColor.yellow),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Pathway grid overlay
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: LudoPathwayGridPainter(
                                cellSize: cellSize,
                              ),
                            ),
                          ),
                        ),

                        // Tokens on track, home stretch, and center home
                        ..._buildTokenOverlays(cellSize),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildYard(LudoColor color) {
    final seatIdx = switch (color) {
      LudoColor.red => 0,
      LudoColor.green => 1,
      LudoColor.yellow => 2,
      LudoColor.blue => 3,
    };
    final player = widget.session.playerAt(seatIdx);
    final playerName = player != null
        ? (player.email == widget.myEmail ? 'YOU' : player.displayName)
        : 'WAITING';
    final yardTokens = (_engine.tokens[color] ?? [])
        .where((t) => t.state == TokenState.inYard)
        .toList();
    final isCurrentTurn = _colorForSeat(widget.session.currentTurn) == color;

    return Expanded(
      flex: 6,
      child: Container(
        color: color.color.withValues(alpha: 0.15),
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            color: color.color,
            borderRadius: BorderRadius.circular(12),
            border: isCurrentTurn
                ? Border.all(color: Colors.white, width: 2.5)
                : null,
            boxShadow: [
              if (isCurrentTurn)
                BoxShadow(
                  color: color.color.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxSize =
                  (constraints.biggest.shortestSide * 0.64).clamp(40.0, 96.0);
              final tokenSize = (boxSize - 18) / 2;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: boxSize,
                    height: boxSize,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: yardTokens
                          .map((t) => _buildTokenWidget(t, tokenSize))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${color.name.toUpperCase()} · $playerName',
                          style: TextStyle(
                            color: color.onColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(color: Colors.black38, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPathwaySection({required int flex}) {
    return Expanded(
      flex: flex,
      child: Container(color: const Color(0xFFFAF9F6)),
    );
  }

  Widget _buildCenterHome() {
    return Expanded(
      flex: 3,
      child: Container(
        color: const Color(0xFFEDEDED),
        child: const CustomPaint(painter: LudoCenterHomePainter()),
      ),
    );
  }

  bool _isMovable(LudoToken t) =>
      _isMyTurn &&
      _engine.hasRolled &&
      _colorForSeat(widget.session.currentTurn) == t.color &&
      _engine.canMoveToken(t, _engine.currentDice ?? 0);

  Widget _buildTokenWidget(LudoToken t, double size) {
    final color = t.color;
    final movable = _isMovable(t);

    return Semantics(
      button: movable,
      label: '${color.name} token ${t.id + 1}${movable ? ', can move' : ''}',
      child: GestureDetector(
        onTap: movable ? () => _onTokenTapped(t) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, movable ? -2.0 : 0.0, 0),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.35, -0.35),
              radius: 0.85,
              colors: [
                Color.lerp(color.color, Colors.white, 0.45)!,
                color.color,
                Color.lerp(color.color, Colors.black, 0.35)!,
              ],
            ),
            border: Border.all(
              color: movable
                  ? Colors.amberAccent
                  : Colors.white.withValues(alpha: 0.9),
              width: movable ? max(2.2, size * 0.14) : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: movable
                    ? Colors.amberAccent.withValues(alpha: 0.75)
                    : Colors.black.withValues(alpha: 0.45),
                blurRadius: movable ? 7 : 3,
                spreadRadius: movable ? 2.0 : 0.5,
                offset: Offset(0, movable ? 2.5 : 1.5),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Specular shine dot
              Positioned(
                top: size * 0.12,
                left: size * 0.16,
                child: Container(
                  width: size * 0.22,
                  height: size * 0.15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
              Center(
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: Text(
                        t.state == TokenState.home ? '★' : '${t.id + 1}',
                        style: TextStyle(
                          color: color.onColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTokenOverlays(double cellSize) {
    final widgets = <Widget>[];

    // Group tokens that share a square so they can be laid out side by side.
    final Map<String, List<LudoToken>> positionBuckets = {};
    for (final color in LudoColor.values) {
      for (final t in _engine.tokens[color] ?? <LudoToken>[]) {
        if (t.state == TokenState.inYard) continue;
        final key = switch (t.state) {
          TokenState.home => 'home_${color.name}',
          TokenState.inHomeStretch => 'stretch_${color.name}_${t.stepCount}',
          _ => 'track_${t.boardIndex}',
        };
        positionBuckets.putIfAbsent(key, () => []).add(t);
      }
    }

    positionBuckets.forEach((key, group) {
      for (int i = 0; i < group.length; i++) {
        final t = group[i];
        final color = t.color;

        // Top-left corner of the (col,row) cell the group occupies.
        double col;
        double row;
        if (t.state == TokenState.home) {
          // A one-cell spot inside each colour's triangle of the 3x3 centre (cols/rows 6..8).
          const spots = {
            LudoColor.red: [6.15, 7.0],
            LudoColor.green: [7.0, 6.15],
            LudoColor.yellow: [7.85, 7.0],
            LudoColor.blue: [7.0, 7.85],
          };
          col = spots[color]![0];
          row = spots[color]![1];
        } else if (t.state == TokenState.inHomeStretch) {
          final stretchIdx = t.stepCount - 51; // 0 to 4
          switch (color) {
            case LudoColor.red:
              col = 1.0 + stretchIdx;
              row = 7;
              break;
            case LudoColor.green:
              col = 7;
              row = 1.0 + stretchIdx;
              break;
            case LudoColor.yellow:
              col = 13.0 - stretchIdx;
              row = 7;
              break;
            case LudoColor.blue:
              col = 7;
              row = 13.0 - stretchIdx;
              break;
          }
        } else {
          final coords = kLudoTrackCoordinates[t.boardIndex];
          col = coords[0].toDouble();
          row = coords[1].toDouble();
        }

        double size;
        double left;
        double top;
        if (group.length == 1) {
          size = cellSize - 4;
          left = col * cellSize + 2;
          top = row * cellSize + 2;
        } else {
          // Share the cell as a 2x2 grid so every token stays visible.
          size = cellSize * 0.5;
          final quadrant = i % 4;
          left = col * cellSize + (quadrant % 2) * cellSize * 0.5;
          top = row * cellSize + (quadrant ~/ 2) * cellSize * 0.5;
        }

        widgets.add(Positioned(
          left: left,
          top: top,
          child: _buildTokenWidget(t, size),
        ));
      }
    });

    return widgets;
  }
}
