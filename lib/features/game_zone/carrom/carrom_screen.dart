import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../common/game_zone_portrait_lock.dart';
import '../data/game_analytics_service.dart';
import '../domain/models/game_analytics_models.dart';
import 'carrom_engine.dart';
import 'carrom_game.dart';

/// Keeps the board in progress while the player visits other screens.
class _CarromSession {
  static CarromGame? game;
  static double aimNoise = 0.018;
  static bool resultShown = false;
}

const _difficulties = {
  'Easy': 0.035,
  'Medium': 0.018,
  'Hard': 0.008,
};

/// Fraction of the board widget taken by the wooden frame on each side.
const double _frameFraction = 0.06;

class CarromScreen extends StatefulWidget {
  const CarromScreen({super.key});

  @override
  State<CarromScreen> createState() => _CarromScreenState();
}

class _CarromScreenState extends State<CarromScreen>
    with SingleTickerProviderStateMixin, GameZonePortraitLock {
  late final CarromGame _game;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _generation = 0;
  bool _botThinking = false;

  // Aiming: drag back like a slingshot; the shot goes the opposite way.
  Offset? _dragStart;
  Offset? _dragNow;
  bool _positioning = false;

  @override
  void initState() {
    super.initState();
    _game = _CarromSession.game ??= CarromGame();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_game.phase == CarromPhase.moving) {
        _startTicker();
      } else {
        _afterShot();
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _ticker.dispose();
    super.dispose();
  }

  void _startTicker() {
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    final finished = _game.advance(dt);
    setState(() {});
    if (finished) {
      _ticker.stop();
      HapticFeedback.lightImpact();
      _afterShot();
    }
  }

  /// Runs whatever comes next: the result dialog or the bot's shot.
  void _afterShot() {
    if (!mounted) return;
    setState(() {});
    if (_game.phase == CarromPhase.gameOver) {
      if (!_CarromSession.resultShown) {
        _CarromSession.resultShown = true;
        HapticFeedback.heavyImpact();
        final userWon = _game.winner == 0;
        GameAnalyticsService().recordMatch(
          gameType: OnlineGameType.carrom,
          won: userWon,
          score: userWon ? _game.winnerPoints : 0,
        );
        _showResultDialog();
      }
      return;
    }
    if (_game.isBotTurn) _playBotTurn();
  }

  Future<void> _playBotTurn() async {
    final generation = ++_generation;
    setState(() => _botThinking = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || generation != _generation) return;

    final shot = await compute(
        carromBotWorker, _game.botRequest(aimNoise: _CarromSession.aimNoise));
    if (!mounted || generation != _generation || !_game.isBotTurn) return;

    // Slide the striker into place, pause, then shoot.
    setState(() => _game.placeStriker(shot.x));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || generation != _generation || !_game.isBotTurn) return;
    setState(() => _botThinking = false);
    if (_game.shoot(shot.angle, shot.power)) _startTicker();
  }

  // --- INPUT ---

  bool get _canAim => _game.isHumanAiming && !_botThinking;

  Offset _toBoard(Offset local, double size) {
    final frame = size * _frameFraction;
    final play = size - 2 * frame;
    return Offset((local.dx - frame) / play, (local.dy - frame) / play);
  }

  void _onPanStart(DragStartDetails d, double size) {
    if (!_canAim) return;
    final p = _toBoard(d.localPosition, size);
    final baseY = CarromBoard.baselineY(_game.currentPlayer);
    final onStriker =
        (p - Offset(_game.striker.x, _game.striker.y)).distance < 0.06;
    _positioning = onStriker || (p.dy - baseY).abs() < 0.045;
    if (_positioning) {
      setState(() => _game.placeStriker(p.dx));
    } else {
      setState(() {
        _dragStart = p;
        _dragNow = p;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d, double size) {
    if (!_canAim) return;
    final p = _toBoard(d.localPosition, size);
    if (_positioning) {
      setState(() => _game.placeStriker(p.dx));
    } else if (_dragStart != null) {
      setState(() => _dragNow = p);
    }
  }

  void _onPanEnd() {
    final aim = _currentAim;
    setState(() {
      _dragStart = null;
      _dragNow = null;
      _positioning = false;
    });
    if (aim == null || !_canAim) return;
    if (!_game.strikerPlacementValid) {
      _toast('The striker is touching a coin - slide it to a free spot first.');
      return;
    }
    if (_game.shoot(aim.$1, aim.$2)) {
      HapticFeedback.mediumImpact();
      _startTicker();
    }
  }

  /// (angle, power) of the shot being drawn back, or null if too small to fire.
  (double, double)? get _currentAim {
    final start = _dragStart;
    final now = _dragNow;
    if (start == null || now == null) return null;
    final pull = start - now;
    final power = (pull.distance / 0.3).clamp(0.0, 1.0);
    if (power < 0.05) return null;
    return (atan2(pull.dy, pull.dx), power);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message), duration: const Duration(seconds: 2)));
  }

  // --- MENUS & DIALOGS ---

  Future<void> _confirmNewGame() async {
    if (_game.hasStarted && _game.phase != CarromPhase.gameOver) {
      final ok = await confirmDiscardGame(context,
          title: 'Start a new board?',
          message: 'The current board will be lost.');
      if (!ok || !mounted) return;
    }
    _newGame();
  }

  void _newGame() {
    _generation++;
    _ticker.stop();
    _CarromSession.resultShown = false;
    setState(() {
      _botThinking = false;
      _game.reset();
    });
  }

  void _setMode(String value) {
    setState(() {
      if (value == 'two') {
        _game.vsBot = false;
      } else {
        _game.vsBot = true;
        _CarromSession.aimNoise = _difficulties[value]!;
      }
    });
    _toast(value == 'two'
        ? 'Pass & Play: two players share this phone.'
        : 'Playing the bot on $value.');
    if (!_game.vsBot) {
      _generation++;
      _botThinking = false;
    }
    _afterShot();
  }

  void _showResultDialog() {
    final winner = _game.winner!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF3E2414),
        title: Text(
          winner == 0
              ? '🏆 You win the board!'
              : '${_game.nameOf(winner)} wins the board',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${_game.nameOf(winner)} scored ${_game.winnerPoints} points '
          '(${_game.remaining(1 - winner)} opponent coins left'
          '${_game.queenCoveredBy == winner ? ' + 3 for the Queen' : ''}).',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('View board',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: () {
              Navigator.pop(ctx);
              _newGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  void _showRulesDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carrom rules (ক্যারম)'),
        content: const SingleChildScrollView(
          child: Text(
            'You play the white coins from the bottom baseline; your opponent plays black from the top.\n\n'
            '• Slide the striker along your baseline (drag it or use the slider). It must not touch a coin.\n'
            '• Drag back anywhere on the board and release to shoot - the further you pull, the harder the shot.\n'
            '• Pocket one of your own coins and you shoot again. Coins of your opponent\'s colour that you '
            'pocket stay down and count for them.\n'
            '• The Queen (red) can be taken once you have pocketed a coin of your own. Cover her by pocketing '
            'one of your coins on the same or the next shot, or she goes back to the centre.\n'
            '• Fouls (ICF rules): pocketing the striker, pocketing your last coin before the Queen is covered, '
            'or pocketing your opponent\'s last coin. Your coins from that shot, the Queen and the opponent\'s '
            'last coin come back, you pay one penalty coin, and your turn ends.\n'
            '• If you have no coin to pay, the penalty is due and comes out of the next coin you pocket.\n'
            '• First to pocket all 9 coins wins the board: 1 point per opponent coin left, +3 for covering the Queen.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))
        ],
      ),
    );
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        try {
          context.go('/game-zone');
        } catch (_) {}
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF241812),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 18),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                try {
                  context.go('/game-zone');
                } catch (_) {}
              }
            },
          ),
          title: const Text('Carrom (ক্যারম)',
              style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A110C),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Rules',
              onPressed: _showRulesDialog),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            tooltip: 'Opponent',
            onSelected: _setMode,
            itemBuilder: (ctx) => [
              for (final entry in _difficulties.entries)
                CheckedPopupMenuItem(
                  value: entry.key,
                  checked:
                      _game.vsBot && _CarromSession.aimNoise == entry.value,
                  child: Text('Bot - ${entry.key}'),
                ),
              CheckedPopupMenuItem(
                  value: 'two',
                  checked: !_game.vsBot,
                  child: const Text('2 Players (Pass & Play)')),
            ],
          ),
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New Board',
              onPressed: _confirmNewGame),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildScoreHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      min(constraints.maxWidth - 16, constraints.maxHeight - 8)
                          .clamp(220.0, 560.0);
                  return Center(child: _buildBoard(size));
                },
              ),
            ),
            _buildControls(),
          ],
        ),
      ),
    ));
  }

  Widget _buildScoreHeader() {
    Widget panel(int player) {
      final isTurn =
          _game.currentPlayer == player && _game.phase != CarromPhase.gameOver;
      final coinColor =
          player == 0 ? const Color(0xFFF4EBD0) : const Color(0xFF2A2A2A);
      final queenNote = _game.queenCoveredBy == player
          ? ' · 👑 Queen'
          : (_game.queenPendingFor == player ? ' · 👑 cover!' : '');
      final due = _game.penaltyDue[player];
      final dueNote = due > 0 ? ' · $due due' : '';
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isTurn ? const Color(0xFF6D4C2E) : const Color(0x33000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isTurn ? Colors.amber : Colors.white12,
                width: isTurn ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: coinColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _game.nameOf(player),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_game.pocketed[player].length}/${CarromGame.coinsPerPlayer} pocketed$queenNote$dueNote',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1A110C),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        children: [
          Row(children: [panel(0), const SizedBox(width: 8), panel(1)]),
          const SizedBox(height: 6),
          Text(
            _botThinking
                ? '${_game.nameOf(1)} is lining up a shot...'
                : _game.status,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFFE6D5C3),
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(double size) {
    final mine = _game.pocketed[0].length;
    final theirs = _game.pocketed[1].length;
    return Semantics(
      label:
          'Carrom board. ${_game.nameOf(0)} $mine of 9 pocketed, ${_game.nameOf(1)} $theirs of 9 pocketed. '
          '${_game.isHumanAiming ? 'Drag back on the board and release to shoot.' : ''}',
      child: GestureDetector(
        onPanStart: (d) => _onPanStart(d, size),
        onPanUpdate: (d) => _onPanUpdate(d, size),
        onPanEnd: (_) => _onPanEnd(),
        onPanCancel: () => setState(() {
          _dragStart = null;
          _dragNow = null;
          _positioning = false;
        }),
        child: CustomPaint(
          size: Size.square(size),
          painter: _CarromPainter(
            game: _game,
            aim: _currentAim,
            showPlacementError:
                _game.isHumanAiming && !_game.strikerPlacementValid,
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final aim = _currentAim;
    final hint = !_canAim
        ? (_game.phase == CarromPhase.moving
            ? 'Coins in motion...'
            : (_game.phase == CarromPhase.gameOver
                ? 'Board finished - tap ↻ for a new board.'
                : 'Opponent is playing...'))
        : aim != null
            ? 'Power ${(aim.$2 * 100).round()}% - release to shoot'
            : (_game.strikerPlacementValid
                ? 'Slide the striker, then drag back anywhere to aim'
                : 'Striker touches a coin - slide it to a free spot');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1A110C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: aim != null ? Colors.amber : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.white54, size: 20),
              Expanded(
                child: Slider(
                  value: _game.strikerX
                      .clamp(CarromBoard.baselineMin, CarromBoard.baselineMax),
                  min: CarromBoard.baselineMin,
                  max: CarromBoard.baselineMax,
                  activeColor: Colors.amber,
                  inactiveColor: Colors.white24,
                  label: 'Striker position',
                  semanticFormatterCallback: (v) =>
                      'Striker position ${((v - CarromBoard.baselineMin) / (CarromBoard.baselineMax - CarromBoard.baselineMin) * 100).round()}%',
                  onChanged: _canAim
                      ? (v) => setState(() => _game.placeStriker(v))
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarromPainter extends CustomPainter {
  _CarromPainter(
      {required this.game,
      required this.aim,
      required this.showPlacementError});

  final CarromGame game;
  final (double, double)? aim;
  final bool showPlacementError;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final frame = s * _frameFraction;
    final play = s - 2 * frame;
    Offset p(double x, double y) => Offset(frame + x * play, frame + y * play);

    // Wooden frame and playing surface.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.03)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6D3B16), Color(0xFF43230C), Color(0xFF2A1507)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Rect.fromLTWH(
          frame * 0.55, frame * 0.55, s - frame * 1.1, s - frame * 1.1),
      Paint()..color = const Color(0xFF2C1607),
    );

    // Mitred 45-degree frame corner joint lines
    final joint = Paint()
      ..color = const Color(0x44000000)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset.zero, Offset(frame, frame), joint);
    canvas.drawLine(Offset(s, 0), Offset(s - frame, frame), joint);
    canvas.drawLine(Offset(0, s), Offset(frame, s - frame), joint);
    canvas.drawLine(Offset(s, s), Offset(s - frame, s - frame), joint);

    // Lacquered English Birch plywood playing surface
    final surface = Rect.fromLTWH(frame, frame, play, play);
    canvas.drawRect(
      surface,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Color(0xFFFFF9EC), Color(0xFFF7E7C8), Color(0xFFE8C895)],
        ).createShader(surface),
    );

    final line = Paint()
      ..color = const Color(0xFF5B3A1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, play * 0.0025);
    final red = Paint()..color = const Color(0xFFC62828);

    // Baselines with their end circles on all four sides; the current
    // player's baseline gets a soft highlight.
    for (int side = 0; side < 4; side++) {
      canvas.save();
      canvas.translate(s / 2, s / 2);
      canvas.rotate(side * pi / 2);
      canvas.translate(-s / 2, -s / 2);
      const y = 1 - CarromBoard.baselineInset;
      const half = CarromBoard.coinRadius;
      final isActive = (side == 0 && game.currentPlayer == 0) ||
          (side == 2 && game.currentPlayer == 1);
      if (isActive && game.phase == CarromPhase.aiming) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromPoints(p(CarromBoard.baselineMin - 0.02, y - half * 1.6),
                p(CarromBoard.baselineMax + 0.02, y + half * 1.6)),
            const Radius.circular(8),
          ),
          Paint()..color = const Color(0x35FFC107),
        );
      }
      canvas.drawLine(p(CarromBoard.baselineMin, y - half),
          p(CarromBoard.baselineMax, y - half), line);
      canvas.drawLine(p(CarromBoard.baselineMin, y + half),
          p(CarromBoard.baselineMax, y + half), line);
      for (final x in const [
        CarromBoard.baselineMin,
        CarromBoard.baselineMax
      ]) {
        canvas.drawCircle(p(x, y), half * play, red);
        canvas.drawCircle(p(x, y), half * play * 0.45,
            Paint()..color = const Color(0xFFFFF8E7));
        canvas.drawCircle(p(x, y), half * play, line);
      }
      // Corner arrow pointing from the pocket towards the centre.
      canvas.drawLine(p(0.1, 0.9), p(0.27, 0.73), line);
      canvas.drawCircle(p(0.27, 0.73), 0.03 * play, line);
      canvas.restore();
    }

    // Centre circles with decorative tournament mandala rays.
    final centerP = p(0.5, 0.5);
    final mandalaR = 0.09 * play;
    canvas.drawCircle(centerP, mandalaR, line);
    canvas.drawCircle(centerP, 0.075 * play, line);
    final rayPaint = Paint()
      ..color = const Color(0x665B3A1E)
      ..strokeWidth = 0.8;
    for (int i = 0; i < 16; i++) {
      final angle = i * pi / 8;
      final r1 = centerP +
          Offset(cos(angle) * 0.075 * play, sin(angle) * 0.075 * play);
      final r2 = centerP + Offset(cos(angle) * mandalaR, sin(angle) * mandalaR);
      canvas.drawLine(r1, r2, rayPaint);
    }
    canvas.drawCircle(centerP, 0.018 * play, red);
    canvas.drawCircle(
        centerP, 0.007 * play, Paint()..color = const Color(0xFFFFF8E7));

    // Pockets with brass bracket rim and woven string net depth.
    for (final pocket in CarromBoard.pockets) {
      final c = p(pocket.$1, pocket.$2);
      // Brass pocket bracket
      canvas.drawCircle(c, CarromBoard.pocketRadius * play * 1.14,
          Paint()..color = const Color(0xFF8D6E44));
      canvas.drawCircle(c, CarromBoard.pocketRadius * play * 1.06,
          Paint()..color = const Color(0xFF381F0E));
      // Deep pocket drop hole
      canvas.drawCircle(c, CarromBoard.pocketRadius * play,
          Paint()..color = const Color(0xFF090604));
      // Woven netting pattern
      final netPaint = Paint()
        ..color = const Color(0x338D6E63)
        ..strokeWidth = 0.8;
      final pr = CarromBoard.pocketRadius * play * 0.7;
      canvas.drawLine(c - Offset(pr, 0), c + Offset(pr, 0), netPaint);
      canvas.drawLine(c - Offset(0, pr), c + Offset(0, pr), netPaint);
    }

    // Coins and striker.
    for (final piece in game.allPieces) {
      if (piece.pocketed) continue;
      _drawPiece(canvas, piece, p(piece.x, piece.y), piece.radius * play);
    }

    if (showPlacementError) {
      canvas.drawCircle(
        p(game.striker.x, game.striker.y),
        game.striker.radius * play * 1.35,
        Paint()
          ..color = Colors.redAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    final shot = aim;
    if (shot != null) {
      final start = p(game.striker.x, game.striker.y);
      final dir = Offset(cos(shot.$1), sin(shot.$1));
      // Faint guide line
      canvas.drawLine(
        start,
        start + dir * play * 1.4,
        Paint()
          ..color = const Color(0x44FFFFFF)
          ..strokeWidth = 1.2,
      );
      final tip = start + dir * play * (0.08 + shot.$2 * 0.32);
      final arrowColor = Color.lerp(
        Colors.limeAccent.shade400,
        Colors.deepOrangeAccent,
        shot.$2,
      )!;
      final arrow = Paint()
        ..color = arrowColor
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, tip, arrow);
      final side = Offset(-dir.dy, dir.dx);
      final head = play * 0.028;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx + dir.dx * head, tip.dy + dir.dy * head)
          ..lineTo(
              tip.dx + side.dx * head * 0.75, tip.dy + side.dy * head * 0.75)
          ..lineTo(
              tip.dx - side.dx * head * 0.75, tip.dy - side.dy * head * 0.75)
          ..close(),
        Paint()..color = arrowColor,
      );
    }
  }

  void _drawPiece(Canvas canvas, CarromPiece piece, Offset c, double r) {
    // 3D Drop shadow
    canvas.drawCircle(
      c + Offset(r * 0.12, r * 0.18),
      r,
      Paint()..color = const Color(0x55000000),
    );

    final pieceRect = Rect.fromCircle(center: c, radius: r);
    final Paint fillPaint = Paint();
    Color ringColor;

    switch (piece.type) {
      case CarromPieceType.white:
        fillPaint.shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [Color(0xFFFFFFFF), Color(0xFFF3ECE0), Color(0xFFC7B18A)],
        ).createShader(pieceRect);
        ringColor = const Color(0xFF8D734B);
        break;
      case CarromPieceType.black:
        fillPaint.shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [Color(0xFF505050), Color(0xFF282828), Color(0xFF141414)],
        ).createShader(pieceRect);
        ringColor = const Color(0xFF757575);
        break;
      case CarromPieceType.queen:
        fillPaint.shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [Color(0xFFFF5252), Color(0xFFD32F2F), Color(0xFF7F0000)],
        ).createShader(pieceRect);
        ringColor = const Color(0xFFFFD54F);
        break;
      case CarromPieceType.striker:
        fillPaint.shader = const RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 0.85,
          colors: [Color(0xFFFFFFFF), Color(0xFFE8EAF6), Color(0xFF9FA8DA)],
        ).createShader(pieceRect);
        ringColor = const Color(0xFF283593);
        break;
    }

    // Main piece body
    canvas.drawCircle(c, r, fillPaint);

    // Bevel outer ring
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..color = ringColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.12),
    );

    // Concentric lathe groove
    canvas.drawCircle(
      c,
      r * 0.45,
      Paint()
        ..color = ringColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, r * 0.08),
    );

    // Center rosette for Queen and Striker
    if (piece.type == CarromPieceType.queen) {
      canvas.drawCircle(c, r * 0.22, Paint()..color = const Color(0xFFFFD54F));
      canvas.drawCircle(c, r * 0.10, Paint()..color = const Color(0xFFB71C1C));
    } else if (piece.type == CarromPieceType.striker) {
      canvas.drawCircle(c, r * 0.25, Paint()..color = const Color(0xFF3949AB));
      canvas.drawCircle(c, r * 0.12, Paint()..color = const Color(0xFFFFD54F));
    }

    // Top-left Specular gleam for physical glass/acrylic shine
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.32),
      r * 0.14,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _CarromPainter oldDelegate) => true;
}
