import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ludo_engine.dart';

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen> with SingleTickerProviderStateMixin {
  final LudoEngine _engine = LudoEngine();
  String _statusMessage = 'Your turn! Tap the dice to roll.';
  late AnimationController _diceAnimController;
  Timer? _botTimer;
  Timer? _autoMoveTimer;

  @override
  void initState() {
    super.initState();
    _diceAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _autoMoveTimer?.cancel();
    _diceAnimController.dispose();
    super.dispose();
  }

  void _onDiceTapped() {
    if (_engine.hasRolled || !_engine.isCurrentTurnHuman()) return;
    HapticFeedback.lightImpact();

    _diceAnimController.forward(from: 0.0);
    final rolled = _engine.rollDice();

    if (rolled == -1) {
      HapticFeedback.heavyImpact();
      setState(() {
        _statusMessage = '3 consecutive 6s! Turn forfeited.';
      });
      _checkBotTurn();
      return;
    }

    setState(() {
      _statusMessage = '${_engine.currentTurn.name} rolled a $rolled!';
    });

    final movable = _engine.getMovableTokens();
    if (movable.isEmpty) {
      _autoMoveTimer?.cancel();
      _autoMoveTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'No valid moves. Passing turn.';
          _engine.hasRolled = false;
          _engine.currentDice = null;
          final nextIdx = (_engine.currentTurn.index + 1) % LudoColor.values.length;
          _engine.currentTurn = LudoColor.values[nextIdx];
        });
        _checkBotTurn();
      });
    } else if (movable.length == 1 && !_engine.isCurrentTurnHuman()) {
      // Auto move single option for bot only
      _autoMoveTimer?.cancel();
      _autoMoveTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _selectTokenToMove(movable.first);
      });
    }
  }

  void _selectTokenToMove(LudoToken token) {
    HapticFeedback.mediumImpact();
    final extra = _engine.moveToken(token);

    if (_engine.hasPlayerWon(token.color)) {
      HapticFeedback.heavyImpact();
      _showWinnerDialog(token.color.name);
      return;
    }

    setState(() {
      if (extra) {
        _statusMessage = '${token.color.name} earned a bonus roll!';
      } else {
        _statusMessage = "${_engine.currentTurn.name}'s turn.";
      }
    });

    _checkBotTurn();
  }

  void _checkBotTurn() {
    if (!_engine.isCurrentTurnHuman()) {
      _runBotSequence();
    }
  }

  void _runBotSequence() {
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _engine.isCurrentTurnHuman()) return;

      _diceAnimController.forward(from: 0.0);
      final rolled = _engine.rollDice();

      if (rolled == -1) {
        setState(() {
          _statusMessage = '${_engine.currentTurn.name} rolled 3 sixes! Turn passed.';
        });
        _checkBotTurn();
        return;
      }

      setState(() {
        _statusMessage = '${_engine.currentTurn.name} bot rolled a $rolled!';
      });

      _botTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted || _engine.isCurrentTurnHuman()) return;

        final bestToken = _engine.getBestBotMove();
        if (bestToken != null) {
          final extra = _engine.moveToken(bestToken);

          if (_engine.hasPlayerWon(bestToken.color)) {
            _showWinnerDialog(bestToken.color.name);
            return;
          }

          setState(() {
            if (extra) {
              _statusMessage = '${bestToken.color.name} bot earned a bonus roll!';
            } else {
              _statusMessage = "${_engine.currentTurn.name}'s turn.";
            }
          });

          _checkBotTurn();
        } else {
          // No moves for bot
          setState(() {
            _statusMessage = '${_engine.currentTurn.name} has no valid moves.';
            _engine.hasRolled = false;
            _engine.currentDice = null;
            final nextIdx = (_engine.currentTurn.index + 1) % LudoColor.values.length;
            _engine.currentTurn = LudoColor.values[nextIdx];
          });
          _checkBotTurn();
        }
      });
    });
  }

  void _resetGame() {
    _botTimer?.cancel();
    _autoMoveTimer?.cancel();
    setState(() {
      _engine.reset();
      _statusMessage = 'New Game! Tap dice to roll.';
    });
  }

  void _showWinnerDialog(String winnerColor) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262A30),
        title: const Text('🎉 Victory!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('$winnerColor player has brought all 4 tokens home!', style: const TextStyle(color: Colors.white70)),
        actions: [
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

  void _showPlayerModeDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF262A30),
            title: const Text('Player Mode & Pass-and-Play', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: LudoColor.values.map((color) {
                final isHuman = _engine.humanPlayers.contains(color);
                return CheckboxListTile(
                  title: Row(
                    children: [
                      Container(width: 14, height: 14, decoration: BoxDecoration(color: color.color, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(color.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  subtitle: Text(isHuman ? 'Human (Pass & Play)' : 'AI Bot', style: TextStyle(color: isHuman ? Colors.amber : Colors.white54, fontSize: 11)),
                  value: isHuman,
                  activeColor: Colors.amber,
                  onChanged: (val) {
                    if (val == true) {
                      _engine.humanPlayers.add(color);
                    } else {
                      if (_engine.humanPlayers.length > 1) {
                        _engine.humanPlayers.remove(color);
                      }
                    }
                    setModalState(() {});
                    setState(() {});
                  },
                );
              }).toList(),
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
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = (screenWidth - 24).clamp(300.0, 440.0);

    return Scaffold(
      backgroundColor: const Color(0xFF1E2125),
      appBar: AppBar(
        title: const Text('Ludo Express', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14171A),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'Pass & Play Mode',
            onPressed: _showPlayerModeDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New Game',
            onPressed: _resetGame,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status bar & Turn Indicator
            _buildStatusBar(),

            const Spacer(),

            // Interactive Ludo Board
            Center(
              child: Container(
                width: boardSize,
                height: boardSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildLudoBoard(boardSize),
                ),
              ),
            ),

            const Spacer(),

            // Bottom Control Area: Dice Roller & Turn Action
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final isHuman = _engine.isCurrentTurnHuman();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF262A30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _engine.currentTurn.color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Turn: ${_engine.currentTurn.name} (${isHuman ? "Human" : "Bot"})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLudoBoard(double size) {
    final cellSize = size / 15.0;

    return Stack(
      children: [
        // Background Grid: Bases, pathways & home triangles
        Column(
          children: [
            // Top Row: Red Yard (6x6) | Top Pathway (3x6) | Green Yard (6x6)
            Expanded(
              flex: 6,
              child: Row(
                children: [
                  _buildYard(LudoColor.red),
                  _buildPathwaySection(isVertical: true, sectionIndex: 0),
                  _buildYard(LudoColor.green),
                ],
              ),
            ),
            // Middle Row: Left Pathway (6x3) | Center Home (3x3) | Right Pathway (6x3)
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _buildPathwaySection(isVertical: false, sectionIndex: 0),
                  _buildCenterHome(),
                  _buildPathwaySection(isVertical: false, sectionIndex: 1),
                ],
              ),
            ),
            // Bottom Row: Blue Yard (6x6) | Bottom Pathway (3x6) | Yellow Yard (6x6)
            Expanded(
              flex: 6,
              child: Row(
                children: [
                  _buildYard(LudoColor.blue),
                  _buildPathwaySection(isVertical: true, sectionIndex: 1),
                  _buildYard(LudoColor.yellow),
                ],
              ),
            ),
          ],
        ),

        // Grid lines overlay for pathway cells
        Positioned.fill(
          child: CustomPaint(
            painter: _PathwayGridPainter(cellSize: cellSize),
          ),
        ),

        // Active Tokens Overlay on Track, Stretch, and Home Box
        ..._buildTokenOverlays(cellSize),
      ],
    );
  }

  Widget _buildYard(LudoColor color) {
    final playerTokens = _engine.tokens[color]!;
    final yardTokens = playerTokens.where((t) => t.state == TokenState.inYard).toList();

    return Expanded(
      flex: 6,
      child: Container(
        color: color.color.withValues(alpha: 0.15),
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: color.color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Container(
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: yardTokens.map((t) {
                  final isMovable = _engine.currentTurn == color &&
                      _engine.hasRolled &&
                      _engine.canMoveToken(t, _engine.currentDice ?? 0);

                  final isHuman = _engine.isCurrentTurnHuman();

                  return GestureDetector(
                    onTap: (isMovable && isHuman) ? () => _selectTokenToMove(t) : null,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isMovable ? Colors.amberAccent : Colors.white,
                          width: isMovable ? 2.5 : 1.5,
                        ),
                        boxShadow: isMovable
                            ? [
                                const BoxShadow(
                                  color: Colors.amberAccent,
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${t.id + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPathwaySection({required bool isVertical, required int sectionIndex}) {
    return Expanded(
      flex: 3,
      child: Container(
        color: const Color(0xFFFAF9F6),
      ),
    );
  }

  Widget _buildCenterHome() {
    return Expanded(
      flex: 3,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFEDEDED),
        ),
        child: CustomPaint(
          painter: _CenterHomePainter(),
        ),
      ),
    );
  }

  List<Widget> _buildTokenOverlays(double cellSize) {
    final widgets = <Widget>[];

    // Group active tokens by position to offset co-located tokens
    final Map<String, List<LudoToken>> positionBuckets = {};

    for (final color in LudoColor.values) {
      for (final t in _engine.tokens[color]!) {
        if (t.state == TokenState.inYard) continue;

        String key;
        if (t.state == TokenState.home) {
          key = 'home_${color.name}';
        } else if (t.state == TokenState.inHomeStretch) {
          key = 'stretch_${color.name}_${t.stepCount}';
        } else {
          key = 'track_${t.boardIndex}';
        }

        positionBuckets.putIfAbsent(key, () => []).add(t);
      }
    }

    positionBuckets.forEach((key, tokenGroup) {
      for (int i = 0; i < tokenGroup.length; i++) {
        final t = tokenGroup[i];
        final color = t.color;

        double top = 0;
        double left = 0;

        if (t.state == TokenState.home) {
          // Home triangle coordinates inside center 3x3 (row 6..8, col 6..8)
          if (color == LudoColor.red) {
            top = 7.15 * cellSize;
            left = 6.45 * cellSize;
          } else if (color == LudoColor.green) {
            top = 6.45 * cellSize;
            left = 7.15 * cellSize;
          } else if (color == LudoColor.yellow) {
            top = 7.15 * cellSize;
            left = 7.85 * cellSize;
          } else {
            top = 7.85 * cellSize;
            left = 7.15 * cellSize;
          }
        } else if (t.state == TokenState.inHomeStretch) {
          final stretchIdx = t.stepCount - 51; // 0 to 4
          if (color == LudoColor.red) {
            top = 7 * cellSize;
            left = (1 + stretchIdx) * cellSize;
          } else if (color == LudoColor.green) {
            top = (1 + stretchIdx) * cellSize;
            left = 7 * cellSize;
          } else if (color == LudoColor.yellow) {
            top = 7 * cellSize;
            left = (13 - stretchIdx) * cellSize;
          } else {
            top = (13 - stretchIdx) * cellSize;
            left = 7 * cellSize;
          }
        } else {
          final idx = t.boardIndex;
          final coords = _getTrackCoordinates(idx);
          left = coords[0] * cellSize;
          top = coords[1] * cellSize;
        }

        // Apply slight offset if multiple tokens share the same space
        if (tokenGroup.length > 1) {
          final offsets = [
            const Offset(-3, -3),
            const Offset(3, 3),
            const Offset(3, -3),
            const Offset(-3, 3),
          ];
          final off = offsets[i % offsets.length];
          left += off.dx;
          top += off.dy;
        }

        final isMovable = _engine.currentTurn == color &&
            _engine.hasRolled &&
            _engine.canMoveToken(t, _engine.currentDice ?? 0);
        final isHuman = _engine.isCurrentTurnHuman();

        widgets.add(
          Positioned(
            left: left + 2,
            top: top + 2,
            child: GestureDetector(
              onTap: (isMovable && isHuman) ? () => _selectTokenToMove(t) : null,
              child: Container(
                width: cellSize - 4,
                height: cellSize - 4,
                decoration: BoxDecoration(
                  color: color.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isMovable ? Colors.amberAccent : Colors.white,
                    width: isMovable ? 2.5 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isMovable ? Colors.amberAccent : Colors.black45,
                      blurRadius: isMovable ? 6 : 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    t.state == TokenState.home ? '★' : '${t.id + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    });

    return widgets;
  }

  List<int> _getTrackCoordinates(int idx) {
    // 52-step coordinates around outer track (col, row)
    const track = [
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

    if (idx < 0 || idx >= track.length) return [0, 0];
    return track[idx];
  }

  Widget _buildBottomControls() {
    final isHuman = _engine.isCurrentTurnHuman();
    final canRoll = !_engine.hasRolled && isHuman;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF262A30),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Dice Widget
          GestureDetector(
            onTap: canRoll ? _onDiceTapped : null,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.15).animate(
                CurvedAnimation(parent: _diceAnimController, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: canRoll ? Colors.amberAccent : Colors.grey.shade400,
                    width: canRoll ? 3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: canRoll ? Colors.amberAccent.withValues(alpha: 0.4) : Colors.black26,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: _engine.currentDice != null
                      ? Text(
                          '${_engine.currentDice}',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _engine.currentTurn.color,
                          ),
                        )
                      : Icon(
                          Icons.casino,
                          size: 36,
                          color: canRoll ? Colors.amber.shade800 : Colors.grey,
                        ),
                ),
              ),
            ),
          ),

          // Action prompt & Home Counter
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                canRoll
                    ? 'TAP DICE TO ROLL'
                    : (!isHuman ? '${_engine.currentTurn.name} bot thinking...' : 'Select a token to move'),
                style: TextStyle(
                  color: canRoll ? Colors.amberAccent : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tokens Home: ${_engine.tokens[_engine.currentTurn]!.where((t) => t.state == TokenState.home).length}/4',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CenterHomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Red Left Triangle
    paint.color = const Color(0xFFE53935);
    final redPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(redPath, paint);

    // Green Top Triangle
    paint.color = const Color(0xFF43A047);
    final greenPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height / 2)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(greenPath, paint);

    // Yellow Right Triangle
    paint.color = const Color(0xFFFDD835);
    final yellowPath = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width / 2, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(yellowPath, paint);

    // Blue Bottom Triangle
    paint.color = const Color(0xFF1E88E5);
    final bluePath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(bluePath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PathwayGridPainter extends CustomPainter {
  final double cellSize;

  _PathwayGridPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    // Safe indices coordinates on 15x15 grid
    const safeGridSpots = [
      [1, 6], [6, 2], [8, 1], [12, 6], [13, 8], [8, 12], [6, 13], [2, 8]
    ];

    // Highlight safe spots with subtle gray-gold tint and a star
    fillPaint.color = const Color(0xFFE8E8E8);
    for (final spot in safeGridSpots) {
      final rect = Rect.fromLTWH(spot[0] * cellSize, spot[1] * cellSize, cellSize, cellSize);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, borderPaint);
    }

    // Paint colored home column pathways
    // Red home column (row 7, col 1..5)
    fillPaint.color = const Color(0xFFFFCDD2);
    for (int c = 1; c <= 5; c++) {
      canvas.drawRect(Rect.fromLTWH(c * cellSize, 7 * cellSize, cellSize, cellSize), fillPaint);
    }
    // Green home column (row 1..5, col 7)
    fillPaint.color = const Color(0xFFC8E6C9);
    for (int r = 1; r <= 5; r++) {
      canvas.drawRect(Rect.fromLTWH(7 * cellSize, r * cellSize, cellSize, cellSize), fillPaint);
    }
    // Yellow home column (row 7, col 9..13)
    fillPaint.color = const Color(0xFFFFF9C4);
    for (int c = 9; c <= 13; c++) {
      canvas.drawRect(Rect.fromLTWH(c * cellSize, 7 * cellSize, cellSize, cellSize), fillPaint);
    }
    // Blue home column (row 9..13, col 7)
    fillPaint.color = const Color(0xFFBBDEFB);
    for (int r = 9; r <= 13; r++) {
      canvas.drawRect(Rect.fromLTWH(7 * cellSize, r * cellSize, cellSize, cellSize), fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
