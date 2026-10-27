import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../carrom/carrom_engine.dart';
import '../carrom/carrom_game.dart';
import '../common/in_game_voice_bar.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';

class OnlineCarromView extends StatefulWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  const OnlineCarromView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  @override
  State<OnlineCarromView> createState() => _OnlineCarromViewState();
}

class _OnlineCarromViewState extends State<OnlineCarromView>
    with SingleTickerProviderStateMixin {
  late final CarromGame _game;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _lastSyncedVersion = -1;

  Offset? _dragStart;
  Offset? _dragNow;

  int get _mySeatIndex =>
      widget.session.playerByEmail(widget.myEmail)?.seatIndex ?? -1;

  bool get _isMyTurn => widget.session.currentTurn == _mySeatIndex;

  @override
  void initState() {
    super.initState();
    _game = CarromGame();
    _game.vsBot = false;
    _ticker = createTicker(_onTick);
    _syncFromSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant OnlineCarromView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.version != _lastSyncedVersion) {
      _syncFromSession(widget.session);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncFromSession(OnlineGameSession session) {
    _lastSyncedVersion = session.version;
    final lastAction = session.lastAction;

    if (lastAction != null && lastAction['type'] == 'shot') {
      final shotData = lastAction['shot'] as Map<String, dynamic>;
      final x = (shotData['x'] as num).toDouble();
      final angle = (shotData['angle'] as num).toDouble();
      final power = (shotData['power'] as num).toDouble();
      final shooter = (lastAction['shooter'] as num).toInt();

      if (shooter != _mySeatIndex && _game.phase == CarromPhase.aiming) {
        _game.currentPlayer = shooter;
        _game.placeStriker(x);
        if (_game.shoot(angle, power)) {
          _startTicker();
        }
      }
    }

    if (mounted) setState(() {});
  }

  void _startTicker() {
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final settled = _game.advance(dt.clamp(0.0, 0.05));
    setState(() {});

    if (settled) {
      _ticker.stop();
      _afterShot();
    }
  }

  void _afterShot() {
    if (_isMyTurn) {
      _commitTurnEnd();
    }
  }

  Future<void> _commitTurnEnd() async {
    final nextSeat = _game.currentPlayer;
    final winner = _game.winner;
    final isFinished = winner != null;

    final newState = {
      'currentPlayer': _game.currentPlayer,
      'winner': winner,
      'pocketedWhite': _game.pocketed[0].length,
      'pocketedBlack': _game.pocketed[1].length,
    };

    final action = {
      'type': 'settle',
      'player': widget.myEmail,
    };

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: action,
      newState: newState,
      nextTurn: nextSeat,
      winnerSeat: winner,
      isFinished: isFinished,
    );
  }

  // --- AIM & SHOOT INPUT ---

  void _onPanStart(DragStartDetails details, Size boardSize) {
    if (!_isMyTurn || _game.phase != CarromPhase.aiming) return;
    setState(() {
      _dragStart = details.localPosition;
      _dragNow = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size boardSize) {
    if (!_isMyTurn || _dragStart == null) return;
    setState(() => _dragNow = details.localPosition);
  }

  void _onPanEnd(Size boardSize) {
    if (!_isMyTurn || _dragStart == null || _dragNow == null) {
      setState(() {
        _dragStart = null;
        _dragNow = null;
      });
      return;
    }

    final diff = _dragStart! - _dragNow!;
    setState(() {
      _dragStart = null;
      _dragNow = null;
    });

    final pullDist = diff.distance;
    if (pullDist < 12) return;

    final angle = atan2(diff.dy, diff.dx);
    final maxPull = boardSize.width * 0.35;
    final power = (pullDist / maxPull).clamp(0.15, 1.0);

    _fireShot(_game.strikerX, angle, power);
  }

  Future<void> _fireShot(double x, double angle, double power) async {
    _game.placeStriker(x);
    if (!_game.shoot(angle, power)) return;

    HapticFeedback.mediumImpact();
    _startTicker();

    final action = {
      'type': 'shot',
      'shooter': _mySeatIndex,
      'shot': {
        'x': x,
        'angle': angle,
        'power': power,
      },
    };

    final newState = {
      'phase': 'moving',
    };

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: action,
      newState: newState,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePlayer = widget.session.playerAt(widget.session.currentTurn);
    final player1 = widget.session.playerAt(0);
    final player2 = widget.session.playerAt(1);

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

        // Scoreboard & Turn Bar
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
              Text(
                '${player1?.displayName ?? 'Player 1'} (White): ${_game.pocketed[0].length}/9',
                style: TextStyle(
                  color: widget.session.currentTurn == 0
                      ? AppColors.mintGreen
                      : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
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
                      ? 'YOUR SHOT'
                      : "${activePlayer?.displayName ?? 'Opponent'}'s turn",
                  style: TextStyle(
                    color: _isMyTurn ? AppColors.mintGreen : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${player2?.displayName ?? 'Player 2'} (Black): ${_game.pocketed[1].length}/9',
                style: TextStyle(
                  color: widget.session.currentTurn == 1
                      ? AppColors.mintGreen
                      : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Carrom Board Surface
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);

                  return GestureDetector(
                    onPanStart: (d) => _onPanStart(d, size),
                    onPanUpdate: (d) => _onPanUpdate(d, size),
                    onPanEnd: (_) => _onPanEnd(size),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDC99B), // Birch Wood surface
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF5D4037), // Mahogany frame
                          width: 14,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: _CarromBoardPainter(
                          game: _game,
                          dragStart: _dragStart,
                          dragNow: _dragNow,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Striker Placement Slider
        if (_isMyTurn && _game.phase == CarromPhase.aiming)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.arrow_back_rounded,
                    color: Colors.white70, size: 16),
                Expanded(
                  child: Slider(
                    value: _game.strikerX,
                    min: CarromBoard.baselineMin,
                    max: CarromBoard.baselineMax,
                    activeColor: AppColors.mintGreen,
                    inactiveColor: Colors.white24,
                    onChanged: (val) {
                      setState(() => _game.placeStriker(val));
                    },
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white70, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class _CarromBoardPainter extends CustomPainter {
  final CarromGame game;
  final Offset? dragStart;
  final Offset? dragNow;

  _CarromBoardPainter({
    required this.game,
    this.dragStart,
    this.dragNow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 4 Corner Pockets
    final pocketPaint = Paint()..color = const Color(0xFF1E1E1E);
    final pr = size.width * CarromBoard.pocketRadius;
    canvas.drawCircle(Offset(pr, pr), pr, pocketPaint);
    canvas.drawCircle(Offset(size.width - pr, pr), pr, pocketPaint);
    canvas.drawCircle(Offset(pr, size.height - pr), pr, pocketPaint);
    canvas.drawCircle(
        Offset(size.width - pr, size.height - pr), pr, pocketPaint);

    // Center Red Circle
    final centerPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2),
        size.width * 0.12, centerPaint);

    // Draw Coins
    for (final coin in game.coins) {
      if (coin.pocketed) continue;
      final cp = Offset(coin.x * size.width, coin.y * size.height);
      final r = coin.radius * size.width;

      final paint = Paint();
      if (coin.type == CarromPieceType.queen) {
        paint.color = Colors.redAccent;
      } else if (coin.type == CarromPieceType.white) {
        paint.color = const Color(0xFFFFFDD0);
      } else {
        paint.color = const Color(0xFF263238);
      }

      canvas.drawCircle(cp, r, paint);
      canvas.drawCircle(
          cp,
          r,
          Paint()
            ..color = Colors.black38
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0);
    }

    // Draw Striker
    final striker = game.striker;
    final sp = Offset(striker.x * size.width, striker.y * size.height);
    final sr = striker.radius * size.width;

    final strikerPaint = Paint()..color = Colors.amber.shade400;
    canvas.drawCircle(sp, sr, strikerPaint);
    canvas.drawCircle(
        sp,
        sr,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Draw Aim Line
    if (dragStart != null && dragNow != null) {
      final diff = dragStart! - dragNow!;
      final aimEnd = sp + diff * 1.5;
      final aimPaint = Paint()
        ..color = AppColors.mintGreen
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(sp, aimEnd, aimPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CarromBoardPainter oldDelegate) => true;
}
