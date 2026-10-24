import 'dart:async';
import 'package:flutter/material.dart';
import 'ludo_engine.dart';

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen> with SingleTickerProviderStateMixin {
  final LudoEngine _engine = LudoEngine();
  bool _isBotTurn = false;
  String _statusMessage = 'Your turn! Tap the dice to roll.';
  late AnimationController _diceAnimController;

  @override
  void initState() {
    super.initState();
    _diceAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _diceAnimController.dispose();
    super.dispose();
  }

  void _onDiceTapped() {
    if (_engine.hasRolled || _isBotTurn) return;

    _diceAnimController.forward(from: 0.0);
    final rolled = _engine.rollDice();

    setState(() {
      _statusMessage = 'You rolled a $rolled!';
    });

    final movable = _engine.getMovableTokens();
    if (movable.isEmpty) {
      Timer(const Duration(milliseconds: 800), () {
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
    } else if (movable.length == 1) {
      // Auto move single option
      Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _selectTokenToMove(movable.first);
      });
    }
  }

  void _selectTokenToMove(LudoToken token) {
    final extra = _engine.moveToken(token);

    if (_engine.hasPlayerWon(token.color)) {
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
    if (_engine.currentTurn != LudoColor.red) {
      setState(() {
        _isBotTurn = true;
      });
      _runBotSequence();
    } else {
      setState(() {
        _isBotTurn = false;
      });
    }
  }

  void _runBotSequence() {
    Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;

      _diceAnimController.forward(from: 0.0);
      final rolled = _engine.rollDice();

      setState(() {
        _statusMessage = '${_engine.currentTurn.name} bot rolled a $rolled!';
      });

      Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;

        final bestToken = _engine.getBestBotMove();
        if (bestToken != null) {
          final extra = _engine.moveToken(bestToken);

          if (_engine.hasPlayerWon(bestToken.color)) {
            _showWinnerDialog(bestToken.color.name);
            return;
          }

          setState(() {
            if (extra) {
              _statusMessage = '${bestToken.color.name} earned a bonus roll!';
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
    setState(() {
      _engine.reset();
      _isBotTurn = false;
      _statusMessage = 'New Game! Tap dice to roll.';
    });
  }

  void _showWinnerDialog(String winnerColor) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 Victory!'),
        content: Text('$winnerColor player has brought all 4 tokens home!'),
        actions: [
          ElevatedButton(
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth.clamp(300.0, 480.0);

    return Scaffold(
      backgroundColor: const Color(0xFF1E2125),
      appBar: AppBar(
        title: const Text('Ludo Express', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14171A),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
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

            // Bottom Control Area: Dice Roller & Token Quick-Select
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                'Turn: ${_engine.currentTurn.name} ${_engine.currentTurn == LudoColor.red ? "(You)" : "(Bot)"}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          Text(
            _statusMessage,
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

        // Active Tokens Overlay on Track & Stretch
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
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: color.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Container(
              width: 70,
              height: 70,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: yardTokens.map((t) {
                  final isMovable = _engine.currentTurn == color &&
                      _engine.hasRolled &&
                      _engine.canMoveToken(t, _engine.currentDice ?? 0);

                  return GestureDetector(
                    onTap: (isMovable && color == LudoColor.red) ? () => _selectTokenToMove(t) : null,
                    child: Container(
                      width: 22,
                      height: 22,
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
        color: const Color(0xFFF9F9F9),
        child: CustomPaint(
          painter: _PathwayPainter(isVertical: isVertical, sectionIndex: sectionIndex),
        ),
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

    // For simplicity and responsive rendering, show active tokens on track
    for (final color in LudoColor.values) {
      final activeTokens = _engine.tokens[color]!.where((t) => t.state == TokenState.onTrack || t.state == TokenState.inHomeStretch).toList();

      for (final t in activeTokens) {
        // Calculate rough board coordinate
        double top = 0;
        double left = 0;

        if (t.state == TokenState.inHomeStretch) {
          // Home stretch coordinates
          final stretchIdx = t.stepCount - 51; // 0 to 4
          if (color == LudoColor.red) {
            top = (6) * cellSize;
            left = (1 + stretchIdx) * cellSize;
          } else if (color == LudoColor.green) {
            top = (1 + stretchIdx) * cellSize;
            left = (8) * cellSize;
          } else if (color == LudoColor.yellow) {
            top = (8) * cellSize;
            left = (13 - stretchIdx) * cellSize;
          } else {
            top = (13 - stretchIdx) * cellSize;
            left = (6) * cellSize;
          }
        } else {
          // Track 0 to 51
          final idx = t.boardIndex;
          final coords = _getTrackCoordinates(idx);
          left = coords[0] * cellSize;
          top = coords[1] * cellSize;
        }

        final isMovable = _engine.currentTurn == color &&
            _engine.hasRolled &&
            _engine.canMoveToken(t, _engine.currentDice ?? 0);

        widgets.add(
          Positioned(
            left: left + 2,
            top: top + 2,
            child: GestureDetector(
              onTap: (isMovable && color == LudoColor.red) ? () => _selectTokenToMove(t) : null,
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
                      color: isMovable ? Colors.amberAccent : Colors.black38,
                      blurRadius: isMovable ? 6 : 3,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '${t.id + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

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
    final canRoll = !_engine.hasRolled && !_isBotTurn && _engine.currentTurn == LudoColor.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                width: 64,
                height: 64,
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

          // Action prompt
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                canRoll ? 'TAP DICE TO ROLL' : (_isBotTurn ? 'Bot thinking...' : 'Select a token to move'),
                style: TextStyle(
                  color: canRoll ? Colors.amberAccent : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Red Tokens: ${_engine.tokens[LudoColor.red]!.where((t) => t.state == TokenState.home).length}/4 Home',
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

class _PathwayPainter extends CustomPainter {
  final bool isVertical;
  final int sectionIndex;

  _PathwayPainter({required this.isVertical, required this.sectionIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
