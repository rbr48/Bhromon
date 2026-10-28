import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../carrom/carrom_engine.dart';
import '../carrom/carrom_game.dart';
import '../common/in_game_voice_bar.dart';
import '../data/online_game_repository.dart';
import '../domain/models/carrom_table.dart';
import '../domain/models/online_game_session.dart';

/// Pauses before the board plays a bot's shot, so people can follow it.
/// Pacing is tuned to feel natural and snappy, avoiding dead silence.
const Duration _botPaceHost = Duration(milliseconds: 350);
const Duration _botPaceOther = Duration(milliseconds: 900);

/// Extra time after a person's deadline, to allow for clock differences.
const Duration _deadlineGrace = Duration(seconds: 2);
const Duration _retryAfter = Duration(seconds: 3);

/// Failed advances in a row before this phone stops asking for the same step.
/// Reopening the table starts again, and another member's phone can still move it.
const int _maxAdvanceFailures = 5;

/// Private notifier to trigger 60/120 FPS piece repainting without top-level rebuilds.
class _BoardNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// The online carrom board. The server plays every shot and stores the board.
/// The phone shows the stored board, plays each shot's motion from the shot the
/// server recorded, then snaps to the stored result. It sends the striker's
/// position and the shot, and nothing it computes is kept as the result.
class OnlineCarromView extends StatefulWidget {
  const OnlineCarromView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  @override
  State<OnlineCarromView> createState() => _OnlineCarromViewState();
}

class _OnlineCarromViewState extends State<OnlineCarromView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  /// The board as the server last stored it, before the shot now on screen.
  List<CarromPiece>? _board;

  /// The board while the last shot is being played on this phone.
  List<CarromPiece>? _animPieces;
  CarromTable? _animTarget;
  double _animSeconds = 0;

  CarromTable? _table;
  int _lastStep = -1;
  int _scheduledStep = -1;
  int _advanceFailures = 0;
  Timer? _advanceTimer;
  bool _busy = false;

  /// Local optimistic shot record currently animating on this shooter's phone.
  CarromShotRecord? _localShot;

  /// Repaint notifier to drive 60/120 FPS piece animation and aim updates
  /// without triggering expensive top-level widget rebuilds.
  final _BoardNotifier _boardNotifier = _BoardNotifier();

  /// Where this person has slid the striker before shooting.
  double _strikerX = 0.5;
  late final ValueNotifier<double> _strikerXNotifier;
  final ValueNotifier<String?> _aimHintNotifier = ValueNotifier<String?>(null);

  Offset? _dragStart;
  Offset? _dragNow;

  OnlineGameSession get _session => widget.session;

  int get _mySeat => _session.playerByEmail(widget.myEmail)?.seatIndex ?? -1;

  bool get _isHost => _session.hostEmail == widget.myEmail;

  bool get _canShoot {
    final table = _table;
    return table != null &&
        !table.isGameOver &&
        table.currentPlayer == _mySeat &&
        _animPieces == null &&
        !_busy &&
        _session.status == GameSessionStatus.inProgress;
  }

  @override
  void initState() {
    super.initState();
    _strikerXNotifier = ValueNotifier<double>(_strikerX);
    _ticker = createTicker(_onTick);
    _syncFromSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleAdvance();
    });
  }

  @override
  void didUpdateWidget(covariant OnlineCarromView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromSession();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _advanceTimer?.cancel();
    _boardNotifier.dispose();
    _strikerXNotifier.dispose();
    _aimHintNotifier.dispose();
    super.dispose();
  }

  // --- The stored board and the shot on screen -------------------------------

  void _syncFromSession() {
    final table = CarromTable.fromState(_session.state);
    if (table.step == _lastStep) return;
    final previous = _board;
    _lastStep = table.step;
    _advanceFailures = 0;
    _table = table;

    // Keep striker position in sync if not actively aiming locally
    if (!_canShoot || _dragStart == null) {
      _strikerX = table.strikerX;
      _strikerXNotifier.value = table.strikerX;
    }

    final shot = table.lastShot;
    final local = _localShot;
    final isOurLocalShot = local != null &&
        shot != null &&
        shot.shooter == _mySeat &&
        _animPieces != null;

    if (isOurLocalShot) {
      // The server confirmed our optimistic shot! Keep the local simulation running smoothly.
      _animTarget = table;
    } else if (shot != null && previous != null && previous.isNotEmpty) {
      _animTarget = table;
      _animPieces = _piecesForShot(previous, shot);
      _animSeconds = 0;
      _lastTick = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    } else {
      _board = table.pieces;
      _animPieces = null;
      _animTarget = null;
      _localShot = null;
    }

    if (mounted) setState(() {});
    _boardNotifier.tick();
    _scheduleAdvance();
  }

  /// The board just before [shot], with the striker fired as the shooter fired it.
  List<CarromPiece> _piecesForShot(
      List<CarromPiece> from, CarromShotRecord shot) {
    final pieces = [for (final p in from) p.copy()];
    final striker = pieces.firstWhere((p) => p.type == CarromPieceType.striker);
    final speed = CarromBoard.shotSpeed(shot.power);
    striker
      ..pocketed = false
      ..x = shot.x
      ..y = CarromBoard.baselineY(shot.shooter)
      ..vx = cos(shot.angle) * speed
      ..vy = sin(shot.angle) * speed;
    return pieces;
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final pieces = _animPieces;
    if (pieces == null) {
      _ticker.stop();
      return;
    }
    final frame = min(max(dt, 0.0), 0.05);
    final steps = max(1, (frame / CarromBoard.stepSeconds).round());
    var settled = false;
    for (var i = 0; i < steps; i++) {
      CarromBoard.step(pieces);
      _animSeconds += CarromBoard.stepSeconds;
      if (CarromBoard.isSettled(pieces) || _animSeconds > 20) {
        settled = true;
        break;
      }
    }
    if (settled) {
      _finishAnimation();
    } else {
      _boardNotifier.tick();
    }
  }

  /// Snaps to the board the server stored, and lets the next step be scheduled.
  void _finishAnimation() {
    _ticker.stop();
    final target = _animTarget;
    _animPieces = null;
    _animTarget = null;
    _localShot = null;
    _busy = false;
    if (target != null) _board = target.pieces;
    if (mounted) setState(() {});
    _boardNotifier.tick();
    _scheduleAdvance();
  }

  // --- Keeping the board moving ----------------------------------------------

  /// Arranges the next step when a bot is to shoot, or a person's time has run
  /// out. Waits until the shot on screen has finished.
  void _scheduleAdvance() {
    final table = _table;
    if (table == null || _session.status != GameSessionStatus.inProgress) {
      return;
    }
    if (_animPieces != null) return;
    if (table.step == _scheduledStep) return;
    final delay = _delayFor(table);
    if (delay == null) return;
    _scheduledStep = table.step;
    _advanceTimer?.cancel();
    final step = table.step;
    _advanceTimer = Timer(delay, () => _advance(step));
  }

  Duration? _delayFor(CarromTable table) {
    if (table.isGameOver) return null;
    if (_session.playerAt(table.currentPlayer)?.isBot ?? false) {
      return _isHost ? _botPaceHost : _botPaceOther;
    }
    final deadline = table.turnDeadline;
    if (deadline == null) return null;
    final wait = deadline.difference(DateTime.now()) + _deadlineGrace;
    return wait.isNegative ? _deadlineGrace : wait;
  }

  Future<void> _advance(int step) async {
    if (!mounted) return;
    final table = _table;
    if (table == null || table.step != step) {
      return; // a newer step is already scheduled
    }

    try {
      final status = await widget.repository.carrom.advance(
        tourId: _session.tourId,
        gameId: _session.id,
        expectedStep: step,
      );
      _advanceFailures = 0;
      // The server refuses a turn that has not run out, so ask again once this
      // phone's clock says it has.
      if (status == 'noop' && _awaitingPastDeadline(table)) {
        _retry(step);
      }
    } catch (_) {
      _advanceFailures++;
      if (_advanceFailures < _maxAdvanceFailures) _retry(step);
    }
  }

  bool _awaitingPastDeadline(CarromTable table) {
    final deadline = table.turnDeadline;
    return deadline != null && DateTime.now().isAfter(deadline);
  }

  void _retry(int step) {
    if (!mounted) return;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(_retryAfter, () => _advance(step));
  }

  // --- Aiming and shooting ---------------------------------------------------

  bool _strikerPlacementValid(double x, int player, List<CarromPiece> pieces) {
    final baseY = CarromBoard.baselineY(player);
    for (int i = 0; i < pieces.length; i++) {
      final c = pieces[i];
      if (c.pocketed || c.type == CarromPieceType.striker) continue;
      final dx = c.x - x;
      final dy = c.y - baseY;
      final minDist = c.radius + CarromBoard.strikerRadius;
      if (dx * dx + dy * dy < minDist * minDist) return false;
    }
    return true;
  }

  void _onPanStart(DragStartDetails details) {
    if (!_canShoot) return;
    _dragStart = details.localPosition;
    _dragNow = details.localPosition;
    _boardNotifier.tick();
  }

  void _onPanUpdate(DragUpdateDetails details, Size boardSize) {
    final start = _dragStart;
    if (!_canShoot || start == null) return;
    _dragNow = details.localPosition;
    final diff = start - details.localPosition;
    if (diff.distance > 8) {
      final maxPull = boardSize.width * 0.35;
      final power = (diff.distance / maxPull).clamp(0.15, 1.0);
      _aimHintNotifier.value =
          'Power ${(power * 100).round()}% · release to strike';
    } else {
      _aimHintNotifier.value = null;
    }
    _boardNotifier.tick();
  }

  void _onPanCancel() {
    _dragStart = null;
    _dragNow = null;
    _aimHintNotifier.value = null;
    _boardNotifier.tick();
  }

  void _onPanEnd(Size boardSize) {
    final start = _dragStart;
    final now = _dragNow;
    _dragStart = null;
    _dragNow = null;
    _aimHintNotifier.value = null;
    _boardNotifier.tick();
    if (!_canShoot || start == null || now == null) return;

    final diff = start - now;
    if (diff.distance < 12) return;

    final currentBoard = _board ?? _table?.pieces ?? const <CarromPiece>[];
    if (!_strikerPlacementValid(_strikerX, _mySeat, currentBoard)) {
      _snack('The striker is touching a coin — slide it to a free spot first.');
      return;
    }

    final angle = atan2(diff.dy, diff.dx);
    final maxPull = boardSize.width * 0.35;
    final power = (diff.distance / maxPull).clamp(0.15, 1.0).toDouble();
    _shoot(angle, power);
  }

  Future<void> _shoot(double angle, double power) async {
    final table = _table;
    final board = _board ?? table?.pieces;
    if (table == null || board == null || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.selectionClick();

    // OPTIMISTIC SHOT: Immediately play the shot locally with zero response lag!
    final localShot = CarromShotRecord(
      shooter: _mySeat,
      x: _strikerX,
      angle: angle,
      power: power,
    );
    _localShot = localShot;
    _animPieces = _piecesForShot(board, localShot);
    _animTarget = null;
    _animSeconds = 0;
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    _boardNotifier.tick();

    try {
      await widget.repository.carrom.shoot(
        tourId: _session.tourId,
        gameId: _session.id,
        x: _strikerX,
        angle: angle,
        power: power,
        expectedStep: table.step,
      );
    } on FirebaseFunctionsException catch (e) {
      _localShot = null;
      _animPieces = null;
      _ticker.stop();
      _snack(e.message ?? 'That shot did not go through.');
      if (mounted) setState(() => _busy = false);
      _boardNotifier.tick();
    } catch (_) {
      _localShot = null;
      _animPieces = null;
      _ticker.stop();
      _snack('Could not reach the board. Check your connection and try again.');
      if (mounted) setState(() => _busy = false);
      _boardNotifier.tick();
    } finally {
      if (mounted && _animPieces == null) {
        setState(() => _busy = false);
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Words for the board ---------------------------------------------------

  String _nameOf(int seat) =>
      _session.playerAt(seat)?.displayName ?? 'Player ${seat + 1}';

  @override
  Widget build(BuildContext context) {
    final table = _table ?? CarromTable.fromState(const {});
    final shooting = _canShoot;
    final turnLabel = table.isGameOver
        ? 'Board finished'
        : _animPieces != null
            ? 'Shot in play…'
            : shooting
                ? 'YOUR SHOT'
                : "${_nameOf(table.currentPlayer)}'s shot";

    return Column(
      children: [
        InGameVoiceBar(
          tourId: _session.tourId,
          gameId: _session.id,
          myEmail: widget.myEmail,
          myDisplayName: widget.repository.currentDisplayName,
          myPhotoUrl: widget.repository.currentPhotoUrl,
          myUid: widget.repository.currentUid,
        ),
        _scoreBar(table, turnLabel, shooting),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: (d) => _onPanUpdate(d, size),
                    onPanEnd: (_) => _onPanEnd(size),
                    onPanCancel: _onPanCancel,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Static wooden mahogany frame, Birch surface, mandala, baselines & pockets
                            const RepaintBoundary(
                              child: CustomPaint(
                                painter: _CarromStaticBoardPainter(),
                              ),
                            ),
                            // 2. High-performance dynamic pieces & aiming arrow painter
                            RepaintBoundary(
                              child: ListenableBuilder(
                                listenable: _boardNotifier,
                                builder: (context, _) {
                                  final pieces = _animPieces ??
                                      _board ??
                                      const <CarromPiece>[];
                                  return CustomPaint(
                                    painter: _CarromPiecesPainter(
                                      pieces: pieces,
                                      aimingPlayer: shooting ? _mySeat : null,
                                      strikerX: _strikerX,
                                      dragStart: _dragStart,
                                      dragNow: _dragNow,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        _bottomControlBar(table, shooting),
      ],
    );
  }

  Widget _bottomControlBar(CarromTable table, bool shooting) {
    return ValueListenableBuilder<String?>(
      valueListenable: _aimHintNotifier,
      builder: (context, aimHint, _) {
        final statusText = aimHint ??
            (table.status.isNotEmpty
                ? table.status
                : (shooting
                    ? 'Slide striker along baseline, then drag back anywhere on board to strike'
                    : (_animPieces != null
                        ? 'Strike in motion...'
                        : 'Waiting for ${_nameOf(table.currentPlayer)}...')));

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          decoration: const BoxDecoration(
            color: Color(0xFF14241B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statusText,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: (aimHint != null || shooting)
                      ? Colors.amberAccent
                      : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.swap_horiz,
                    color: shooting ? AppColors.mintGreen : Colors.white30,
                    size: 20,
                  ),
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _strikerXNotifier,
                      builder: (context, strikerX, _) {
                        return Slider(
                          value: strikerX.clamp(
                              CarromBoard.baselineMin, CarromBoard.baselineMax),
                          min: CarromBoard.baselineMin,
                          max: CarromBoard.baselineMax,
                          activeColor:
                              shooting ? AppColors.mintGreen : Colors.white24,
                          inactiveColor: Colors.white12,
                          onChanged: shooting
                              ? (value) {
                                  _strikerX = value;
                                  _strikerXNotifier.value = value;
                                  _boardNotifier.tick();
                                }
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _scoreBar(CarromTable table, String turnLabel, bool myTurn) {
    Widget playerCard(
        int seat, String coinName, Color coinColor, Color borderColor) {
      final isCurrent = table.currentPlayer == seat && !table.isGameOver;
      final name = _nameOf(seat);
      final score = table.pocketedBy(seat);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.midGreen.withValues(alpha: 0.25)
                : const Color(0xFF0A140E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent ? AppColors.mintGreen : Colors.white12,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: coinColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? Colors.white : Colors.white70,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '$score/${CarromGame.coinsPerPlayer} $coinName',
                      style: TextStyle(
                        color: isCurrent ? AppColors.mintGreen : Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
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
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: myTurn ? AppColors.mintGreen : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          playerCard(
              0, 'White', const Color(0xFFF5F0E6), const Color(0xFF8D734B)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: myTurn
                    ? AppColors.mintGreen.withValues(alpha: 0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: myTurn ? AppColors.mintGreen : Colors.white24,
                  width: 1,
                ),
              ),
              child: Text(
                turnLabel,
                style: TextStyle(
                  color: myTurn ? AppColors.mintGreen : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          playerCard(
              1, 'Black', const Color(0xFF222222), const Color(0xFF757575)),
        ],
      ),
    );
  }
}

/// Paints the static wooden frame, plywood surface, tournament mandala,
/// baselines, and pocket brackets. This painter never repaints during gameplay,
/// achieving maximum frame rates.
class _CarromStaticBoardPainter extends CustomPainter {
  const _CarromStaticBoardPainter();

  static const double _frameFraction = 0.07;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final frame = s * _frameFraction;
    final play = s - 2 * frame;
    Offset p(double x, double y) => Offset(frame + x * play, frame + y * play);

    // 1. Rich wooden mahogany frame
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

    // 2. Mitred 45-degree frame corner joint lines
    final joint = Paint()
      ..color = const Color(0x44000000)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset.zero, Offset(frame, frame), joint);
    canvas.drawLine(Offset(s, 0), Offset(s - frame, frame), joint);
    canvas.drawLine(Offset(0, s), Offset(frame, s - frame), joint);
    canvas.drawLine(Offset(s, s), Offset(s - frame, s - frame), joint);

    // 3. Lacquered English Birch plywood playing surface
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

    // 4. Baselines with end circles on all four sides
    for (int side = 0; side < 4; side++) {
      canvas.save();
      canvas.translate(s / 2, s / 2);
      canvas.rotate(side * pi / 2);
      canvas.translate(-s / 2, -s / 2);
      const y = 1 - CarromBoard.baselineInset;
      const half = CarromBoard.coinRadius;

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
      // Corner arrow pointing from pocket toward centre
      canvas.drawLine(p(0.1, 0.9), p(0.27, 0.73), line);
      canvas.drawCircle(p(0.27, 0.73), 0.03 * play, line);
      canvas.restore();
    }

    // 5. Central tournament mandala with 16 rays
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

    // 6. Corner pockets with brass bracket rim and woven string net
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
  }

  @override
  bool shouldRepaint(covariant _CarromStaticBoardPainter oldDelegate) => false;
}

/// Dedicated high-speed painter for dynamic pieces, active baseline highlight,
/// and aiming trajectory.
class _CarromPiecesPainter extends CustomPainter {
  _CarromPiecesPainter({
    required this.pieces,
    required this.aimingPlayer,
    required this.strikerX,
    this.dragStart,
    this.dragNow,
  });

  final List<CarromPiece> pieces;

  /// The seat whose striker is being slid, or null when nobody is aiming here.
  final int? aimingPlayer;
  final double strikerX;
  final Offset? dragStart;
  final Offset? dragNow;

  static const double _frameFraction = 0.07;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final frame = s * _frameFraction;
    final play = s - 2 * frame;
    Offset p(double x, double y) => Offset(frame + x * play, frame + y * play);

    // 1. Highlight active shooting baseline if aiming
    if (aimingPlayer != null) {
      const y = 1 - CarromBoard.baselineInset;
      const half = CarromBoard.coinRadius;
      canvas.save();
      canvas.translate(s / 2, s / 2);
      canvas.rotate(aimingPlayer! * pi);
      canvas.translate(-s / 2, -s / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(
            p(CarromBoard.baselineMin - 0.02, y - half * 1.6),
            p(CarromBoard.baselineMax + 0.02, y + half * 1.6),
          ),
          const Radius.circular(8),
        ),
        Paint()..color = const Color(0x35FFC107),
      );
      canvas.restore();
    }

    // 2. Coins and striker on board
    for (int i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      if (piece.pocketed) continue;
      if (piece.type == CarromPieceType.striker && aimingPlayer != null) {
        continue;
      }
      _drawPiece(canvas, piece, p(piece.x, piece.y), piece.radius * play);
    }

    // 3. Aiming striker and slingshot pull arrow
    if (aimingPlayer != null) {
      final striker = CarromPiece(
        id: 99,
        type: CarromPieceType.striker,
        x: strikerX,
        y: CarromBoard.baselineY(aimingPlayer!),
      );
      final startPos = p(striker.x, striker.y);
      _drawPiece(canvas, striker, startPos, striker.radius * play);

      final start = dragStart;
      final now = dragNow;
      if (start != null && now != null) {
        final diff = start - now;
        if (diff.distance > 8) {
          final dir = diff / diff.distance;
          final maxPull = size.width * 0.35;
          final power = (diff.distance / maxPull).clamp(0.15, 1.0);

          // Faint guide line
          canvas.drawLine(
            startPos,
            startPos + dir * play * 1.2,
            Paint()
              ..color = const Color(0x44FFFFFF)
              ..strokeWidth = 1.2,
          );

          // Arrow tip
          final tip = startPos + dir * play * (0.08 + power * 0.32);
          final arrowColor = Color.lerp(
            Colors.limeAccent.shade400,
            Colors.deepOrangeAccent,
            power,
          )!;
          final arrow = Paint()
            ..color = arrowColor
            ..strokeWidth = 4.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(startPos, tip, arrow);

          final side = Offset(-dir.dy, dir.dx);
          final head = play * 0.028;
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx + dir.dx * head, tip.dy + dir.dy * head)
              ..lineTo(tip.dx + side.dx * head * 0.75,
                  tip.dy + side.dy * head * 0.75)
              ..lineTo(tip.dx - side.dx * head * 0.75,
                  tip.dy - side.dy * head * 0.75)
              ..close(),
            Paint()..color = arrowColor,
          );
        }
      }
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
        ..strokeWidth = max(0.9, r * 0.08),
    );

    // Inner concentric accent
    canvas.drawCircle(
      c,
      r * 0.45,
      Paint()
        ..color = ringColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, r * 0.05),
    );
    canvas.drawCircle(
      c,
      r * 0.12,
      Paint()..color = ringColor.withValues(alpha: 0.6),
    );

    // Extra detail for striker
    if (piece.type == CarromPieceType.striker) {
      final ridge = Paint()
        ..color = const Color(0x331A237E)
        ..strokeWidth = 0.7;
      for (int i = 0; i < 8; i++) {
        final a = i * pi / 4;
        canvas.drawLine(
          c + Offset(cos(a) * r * 0.55, sin(a) * r * 0.55),
          c + Offset(cos(a) * r * 0.85, sin(a) * r * 0.85),
          ridge,
        );
      }
      // Top specular highlight
      canvas.drawCircle(
        c + Offset(-r * 0.28, -r * 0.28),
        r * 0.22,
        Paint()..color = const Color(0x55FFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CarromPiecesPainter oldDelegate) => true;
}
