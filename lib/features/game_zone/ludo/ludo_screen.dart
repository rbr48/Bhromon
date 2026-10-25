import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/game_zone_portrait_lock.dart';
import 'ludo_engine.dart';

/// Keeps the race in progress while the player visits other screens.
class _LudoSession {
  static LudoEngine? engine;
  static LudoColor? winner;
  static String statusMessage = 'Your turn! Tap the dice to roll.';
}

/// 52-step coordinates around the outer track as (col, row) on the 15x15 grid.
const List<List<int>> _trackCoordinates = [
  [1, 6], [2, 6], [3, 6], [4, 6], [5, 6],
  [6, 5], [6, 4], [6, 3], [6, 2], [6, 1], [6, 0],
  [7, 0], [8, 0],
  [8, 1], [8, 2], [8, 3], [8, 4], [8, 5],
  [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6],
  [14, 7], [14, 8],
  [13, 8], [12, 8], [11, 8], [10, 8], [9, 8],
  [8, 9], [8, 10], [8, 11], [8, 12], [8, 13], [8, 14],
  [7, 14], [6, 14],
  [6, 13], [6, 12], [6, 11], [6, 10], [6, 9],
  [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
  [0, 7], [0, 6],
];

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen> with SingleTickerProviderStateMixin, GameZonePortraitLock {
  late final LudoEngine _engine;
  late final AnimationController _diceAnimController;
  late final Animation<double> _diceScale;
  Timer? _turnTimer;
  int _flowGeneration = 0;

  String get _statusMessage => _LudoSession.statusMessage;
  set _statusMessage(String value) => _LudoSession.statusMessage = value;

  @override
  void initState() {
    super.initState();
    _engine = _LudoSession.engine ??= LudoEngine();
    _diceAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _diceScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 1),
    ]).animate(_diceAnimController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resumeTurnFlow();
    });
  }

  @override
  void dispose() {
    _flowGeneration++;
    _turnTimer?.cancel();
    _diceAnimController.dispose();
    super.dispose();
  }

  String _playerLabel(LudoColor color) => '${color.name}${_engine.humanPlayers.contains(color) ? '' : ' bot'}';

  void _schedule(Duration delay, VoidCallback action) {
    _turnTimer?.cancel();
    final generation = _flowGeneration;
    _turnTimer = Timer(delay, () {
      if (!mounted || generation != _flowGeneration) return;
      action();
    });
  }

  /// Decides what happens next for the current player. Safe to call at any
  /// time: after a move, a reset, a player-mode change, or on re-entry.
  void _resumeTurnFlow() {
    _turnTimer?.cancel();
    if (_LudoSession.winner != null) return;
    if (_engine.hasRolled) {
      _afterRoll();
    } else if (!_engine.isCurrentTurnHuman()) {
      _schedule(const Duration(milliseconds: 650), _roll);
    }
    setState(() {});
  }

  void _onDiceTapped() {
    if (_engine.hasRolled || !_engine.isCurrentTurnHuman() || _LudoSession.winner != null) return;
    HapticFeedback.lightImpact();
    _roll();
  }

  void _roll() {
    final roller = _engine.currentTurn;
    _diceAnimController.forward(from: 0.0);
    final rolled = _engine.rollDice();

    if (rolled == -1) {
      HapticFeedback.heavyImpact();
      setState(() {
        _statusMessage = '${_playerLabel(roller)} rolled 3 sixes in a row - turn forfeited.';
      });
      _schedule(const Duration(milliseconds: 700), _resumeTurnFlow);
      return;
    }

    setState(() {
      _statusMessage = '${_playerLabel(roller)} rolled a $rolled!';
    });
    _afterRoll();
  }

  void _afterRoll() {
    final movable = _engine.getMovableTokens();
    if (movable.isEmpty) {
      _schedule(const Duration(milliseconds: 800), () {
        setState(() {
          _statusMessage = 'No valid moves for ${_playerLabel(_engine.currentTurn)}. Passing turn.';
          _engine.passTurn();
        });
        _resumeTurnFlow();
      });
    } else if (!_engine.isCurrentTurnHuman()) {
      _schedule(const Duration(milliseconds: 600), () {
        // The player may have switched this colour to human meanwhile.
        if (_engine.isCurrentTurnHuman()) {
          setState(() {});
          return;
        }
        final best = _engine.getBestBotMove();
        if (best != null) _moveToken(best);
      });
    }
  }

  void _moveToken(LudoToken token) {
    HapticFeedback.mediumImpact();
    final mover = token.color;
    final extra = _engine.moveToken(token);

    if (_engine.hasPlayerWon(mover)) {
      HapticFeedback.heavyImpact();
      setState(() {
        _LudoSession.winner = mover;
        _statusMessage = '${mover.name} brought all 4 tokens home!';
      });
      _showWinnerDialog(mover);
      return;
    }

    setState(() {
      _statusMessage = extra
          ? '${_playerLabel(mover)} earned a bonus roll!'
          : "${_playerLabel(_engine.currentTurn)}'s turn.";
    });
    _resumeTurnFlow();
  }

  bool get _hasGameStarted =>
      _engine.tokens.values.expand((t) => t).any((t) => t.state != TokenState.inYard);

  Future<void> _onResetPressed() async {
    if (_hasGameStarted && _LudoSession.winner == null) {
      final ok = await confirmDiscardGame(context, title: 'Start a new game?', message: 'The current race will be lost.');
      if (!ok || !mounted) return;
    }
    _resetGame();
  }

  void _resetGame() {
    _flowGeneration++;
    _turnTimer?.cancel();
    setState(() {
      _engine.reset();
      _LudoSession.winner = null;
      _statusMessage = 'New Game! ${_playerLabel(_engine.currentTurn)} starts.';
    });
    _resumeTurnFlow();
  }

  void _showWinnerDialog(LudoColor winner) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262A30),
        title: const Text('🎉 Victory!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '${_playerLabel(winner)} has brought all 4 tokens home!',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('View board', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: () {
              Navigator.pop(ctx);
              _resetGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPlayerModeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF262A30),
            title: const Text('Player Mode & Pass-and-Play', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...LudoColor.values.map((color) {
                  final isHuman = _engine.humanPlayers.contains(color);
                  final isLastHuman = isHuman && _engine.humanPlayers.length == 1;
                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Container(width: 14, height: 14, decoration: BoxDecoration(color: color.color, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Text(color.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    subtitle: Text(
                      isHuman ? (isLastHuman ? 'Human (at least one human is required)' : 'Human (Pass & Play)') : 'AI Bot',
                      style: TextStyle(color: isHuman ? Colors.amber : Colors.white54, fontSize: 12),
                    ),
                    value: isHuman,
                    activeColor: Colors.amber,
                    onChanged: isLastHuman
                        ? null
                        : (val) {
                            if (val == true) {
                              _engine.humanPlayers.add(color);
                            } else {
                              _engine.humanPlayers.remove(color);
                            }
                            setModalState(() {});
                            setState(() {});
                          },
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Save & Close', style: TextStyle(color: Colors.amber)),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    // A colour may have switched between human and bot: restart the turn flow.
    _flowGeneration++;
    _resumeTurnFlow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2125),
      appBar: AppBar(
        title: const Text('Ludo Express', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14171A),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(icon: const Icon(Icons.group), tooltip: 'Pass & Play Mode', onPressed: _showPlayerModeDialog),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'New Game', onPressed: _onResetPressed),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boardSize = min(constraints.maxWidth - 24, constraints.maxHeight - 16).clamp(240.0, 520.0);
                  return Center(
                    child: Container(
                      width: boardSize,
                      height: boardSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildLudoBoard(boardSize),
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final isHuman = _engine.isCurrentTurnHuman();
    final turn = _engine.currentTurn;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF262A30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: turn.color, border: Border.all(color: Colors.white54)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _LudoSession.winner != null
                      ? 'Winner: ${_LudoSession.winner!.name}'
                      : 'Turn: ${turn.name} (${isHuman ? "Human" : "Bot"})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _statusMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLudoBoard(double size) {
    final cellSize = size / 15.0;

    return Stack(
      children: [
        // Background: yards (6x6), track arms (3x6 / 6x3) and the 3x3 home centre.
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
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _PathwayGridPainter(cellSize: cellSize))),
        ),
        ..._buildTokenOverlays(cellSize),
      ],
    );
  }

  Widget _buildYard(LudoColor color) {
    final yardTokens = _engine.tokens[color]!.where((t) => t.state == TokenState.inYard).toList();
    final isHuman = _engine.humanPlayers.contains(color);

    return Expanded(
      flex: 6,
      child: Container(
        color: color.color.withValues(alpha: 0.15),
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: BoxDecoration(
            color: color.color,
            borderRadius: BorderRadius.circular(10),
            border: _engine.currentTurn == color ? Border.all(color: Colors.black87, width: 2) : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxSize = (constraints.biggest.shortestSide * 0.62).clamp(40.0, 96.0);
              final tokenSize = (boxSize - 18) / 2;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: boxSize,
                    height: boxSize,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: yardTokens.map((t) => _buildTokenWidget(t, tokenSize)).toList(),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${color.name.toUpperCase()} · ${isHuman ? 'YOU' : 'BOT'}',
                        style: TextStyle(color: color.onColor, fontSize: 11, fontWeight: FontWeight.bold),
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
    return Expanded(flex: flex, child: Container(color: const Color(0xFFFAF9F6)));
  }

  Widget _buildCenterHome() {
    return Expanded(
      flex: 3,
      child: Container(
        color: const Color(0xFFEDEDED),
        child: CustomPaint(painter: _CenterHomePainter()),
      ),
    );
  }

  bool _isMovable(LudoToken t) =>
      _LudoSession.winner == null &&
      _engine.currentTurn == t.color &&
      _engine.hasRolled &&
      _engine.canMoveToken(t, _engine.currentDice ?? 0);

  String _describeToken(LudoToken t) {
    switch (t.state) {
      case TokenState.inYard:
        return 'in yard';
      case TokenState.onTrack:
        return 'on track, ${t.stepCount} steps from start';
      case TokenState.inHomeStretch:
        return 'in home column, ${LudoEngine.stepsToHome - t.stepCount} steps from home';
      case TokenState.home:
        return 'home';
    }
  }

  Widget _buildTokenWidget(LudoToken t, double size) {
    final color = t.color;
    final movable = _isMovable(t);
    final tappable = movable && _engine.isCurrentTurnHuman();
    return Semantics(
      button: tappable,
      label: '${color.name} token ${t.id + 1}, ${_describeToken(t)}${tappable ? ', can move' : ''}',
      child: GestureDetector(
        onTap: tappable ? () => _moveToken(t) : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: movable ? Colors.black : Colors.white,
              width: movable ? max(2.0, size * 0.12) : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: movable ? Colors.amberAccent : Colors.black45,
                blurRadius: movable ? 6 : 2,
                spreadRadius: movable ? 1.5 : 0,
              ),
            ],
          ),
          child: Center(
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Text(
                    t.state == TokenState.home ? '★' : '${t.id + 1}',
                    style: TextStyle(color: color.onColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
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
      for (final t in _engine.tokens[color]!) {
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
          final coords = _trackCoordinates[t.boardIndex];
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
          // Share the cell as a 2x2 grid so every token and number stays visible.
          size = cellSize * 0.5;
          final quadrant = i % 4;
          left = col * cellSize + (quadrant % 2) * cellSize * 0.5;
          top = row * cellSize + (quadrant ~/ 2) * cellSize * 0.5;
        }

        widgets.add(Positioned(left: left, top: top, child: _buildTokenWidget(t, size)));
      }
    });

    return widgets;
  }

  Widget _buildBottomControls() {
    final isHuman = _engine.isCurrentTurnHuman();
    final canRoll = !_engine.hasRolled && isHuman && _LudoSession.winner == null;
    final turnColor = _engine.currentTurn;

    final prompt = _LudoSession.winner != null
        ? 'Game over - tap ↻ for a new game'
        : canRoll
            ? 'TAP DICE TO ROLL'
            : (!isHuman ? '${turnColor.name} bot thinking...' : 'Select a highlighted token');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF262A30),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Semantics(
            button: canRoll,
            label: _engine.currentDice != null ? 'Dice showing ${_engine.currentDice}' : 'Roll dice',
            child: GestureDetector(
              onTap: canRoll ? _onDiceTapped : null,
              child: ScaleTransition(
                scale: _diceScale,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: canRoll ? Colors.amberAccent : turnColor.color, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: canRoll ? Colors.amberAccent.withValues(alpha: 0.4) : Colors.black26,
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _engine.currentDice != null
                      ? CustomPaint(painter: _DiceFacePainter(_engine.currentDice!))
                      : Icon(Icons.casino, size: 36, color: canRoll ? Colors.amber.shade800 : Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: canRoll ? Colors.amberAccent : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tokens Home: ${_engine.tokens[turnColor]!.where((t) => t.state == TokenState.home).length}/4',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Classic dice face with dark pips.
class _DiceFacePainter extends CustomPainter {
  _DiceFacePainter(this.value);

  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF212121);
    final r = size.width * 0.09;
    double x(double f) => size.width * f;
    double y(double f) => size.height * f;
    const lo = 0.27;
    const mid = 0.5;
    const hi = 0.73;
    final pips = <Offset>[
      if (value.isOdd) Offset(x(mid), y(mid)),
      if (value >= 2) ...[Offset(x(lo), y(lo)), Offset(x(hi), y(hi))],
      if (value >= 4) ...[Offset(x(hi), y(lo)), Offset(x(lo), y(hi))],
      if (value == 6) ...[Offset(x(lo), y(mid)), Offset(x(hi), y(mid))],
    ];
    for (final p in pips) {
      canvas.drawCircle(p, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiceFacePainter oldDelegate) => oldDelegate.value != value;
}

class _CenterHomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);

    void triangle(Color color, Offset a, Offset b) {
      paint.color = color;
      canvas.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(center.dx, center.dy)..lineTo(b.dx, b.dy)..close(), paint);
    }

    triangle(LudoColor.red.color, Offset.zero, Offset(0, size.height));
    triangle(LudoColor.green.color, Offset.zero, Offset(size.width, 0));
    triangle(LudoColor.yellow.color, Offset(size.width, 0), Offset(size.width, size.height));
    triangle(LudoColor.blue.color, Offset(0, size.height), Offset(size.width, size.height));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PathwayGridPainter extends CustomPainter {
  final double cellSize;

  _PathwayGridPainter({required this.cellSize});

  Rect _cell(num col, num row) => Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize);

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    // Home columns in each player's colour.
    void homeColumn(LudoColor color, Iterable<Rect> cells) {
      fillPaint.color = color.color.withValues(alpha: 0.45);
      for (final rect in cells) {
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
      }
    }

    homeColumn(LudoColor.red, [for (int c = 1; c <= 5; c++) _cell(c, 7)]);
    homeColumn(LudoColor.green, [for (int r = 1; r <= 5; r++) _cell(7, r)]);
    homeColumn(LudoColor.yellow, [for (int c = 9; c <= 13; c++) _cell(c, 7)]);
    homeColumn(LudoColor.blue, [for (int r = 9; r <= 13; r++) _cell(7, r)]);

    // Every track square gets an outline; start squares are tinted with
    // their owner's colour and all safe squares carry a star.
    final startColors = {for (final c in LudoColor.values) c.startIndex: c};
    for (int i = 0; i < _trackCoordinates.length; i++) {
      final rect = _cell(_trackCoordinates[i][0], _trackCoordinates[i][1]);
      final owner = startColors[i];
      if (owner != null) {
        fillPaint.color = owner.color.withValues(alpha: 0.75);
        canvas.drawRect(rect, fillPaint);
      } else if (LudoEngine.safeIndices.contains(i)) {
        fillPaint.color = const Color(0xFFE8E8E8);
        canvas.drawRect(rect, fillPaint);
      }
      canvas.drawRect(rect, borderPaint);
      if (LudoEngine.safeIndices.contains(i)) {
        _drawStar(canvas, rect, owner == LudoColor.yellow || owner == null ? const Color(0x99000000) : const Color(0xCCFFFFFF));
      }
    }
  }

  void _drawStar(Canvas canvas, Rect rect, Color color) {
    final center = rect.center;
    final outer = rect.width * 0.32;
    final inner = outer * 0.45;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / 5;
      final point = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PathwayGridPainter oldDelegate) => oldDelegate.cellSize != cellSize;
}
