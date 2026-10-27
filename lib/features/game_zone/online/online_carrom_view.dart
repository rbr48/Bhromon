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
/// The host's phone paces the bots, so they are not played twice as fast.
const Duration _botPaceHost = Duration(milliseconds: 900);
const Duration _botPaceOther = Duration(milliseconds: 1800);

/// Extra time after a person's deadline, to allow for clock differences.
const Duration _deadlineGrace = Duration(seconds: 2);
const Duration _retryAfter = Duration(seconds: 3);

/// Failed advances in a row before this phone stops asking for the same step.
/// Reopening the table starts again, and another member's phone can still move it.
const int _maxAdvanceFailures = 5;

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

  /// Where this person has slid the striker before shooting.
  double _strikerX = 0.5;
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
    _strikerX = table.strikerX;

    final shot = table.lastShot;
    if (shot != null && previous != null && previous.isNotEmpty) {
      _animTarget = table;
      _animPieces = _piecesForShot(previous, shot);
      _animSeconds = 0;
      _lastTick = Duration.zero;
      if (!_ticker.isActive) _ticker.start();
    } else {
      _board = table.pieces;
      _animPieces = null;
      _animTarget = null;
    }

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
    if (settled) _finishAnimation();
    if (mounted) setState(() {});
  }

  /// Snaps to the board the server stored, and lets the next step be scheduled.
  void _finishAnimation() {
    _ticker.stop();
    final target = _animTarget;
    _animPieces = null;
    _animTarget = null;
    if (target != null) _board = target.pieces;
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

  void _onPanStart(DragStartDetails details) {
    if (!_canShoot) return;
    setState(() {
      _dragStart = details.localPosition;
      _dragNow = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null) return;
    setState(() => _dragNow = details.localPosition);
  }

  void _onPanEnd(Size boardSize) {
    final start = _dragStart;
    final now = _dragNow;
    setState(() {
      _dragStart = null;
      _dragNow = null;
    });
    if (!_canShoot || start == null || now == null) return;

    final diff = start - now;
    if (diff.distance < 12) return;
    final angle = atan2(diff.dy, diff.dx);
    final maxPull = boardSize.width * 0.35;
    final power = (diff.distance / maxPull).clamp(0.15, 1.0).toDouble();
    _shoot(angle, power);
  }

  Future<void> _shoot(double angle, double power) async {
    final table = _table;
    if (table == null || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
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
      _snack(e.message ?? 'That shot did not go through.');
    } catch (_) {
      _snack('Could not reach the board. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
                  final pieces = _animPieces ?? _board ?? const <CarromPiece>[];
                  return GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: (_) => _onPanEnd(size),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDC99B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF5D4037), width: 14),
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
                          pieces: pieces,
                          aimingPlayer: shooting ? _mySeat : null,
                          strikerX: _strikerX,
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
        if (shooting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.arrow_back_rounded,
                    color: Colors.white70, size: 16),
                Expanded(
                  child: Slider(
                    value: _strikerX,
                    min: CarromBoard.baselineMin,
                    max: CarromBoard.baselineMax,
                    activeColor: AppColors.mintGreen,
                    inactiveColor: Colors.white24,
                    onChanged: (value) => setState(() => _strikerX = value),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white70, size: 16),
              ],
            ),
          ),
        if (table.status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Text(
              table.status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _scoreBar(CarromTable table, String turnLabel, bool myTurn) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: myTurn ? AppColors.mintGreen : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_nameOf(0)} (White): ${table.pocketedBy(0)}/${CarromGame.coinsPerPlayer}',
            style: TextStyle(
              color: table.currentPlayer == 0
                  ? AppColors.mintGreen
                  : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            turnLabel,
            style: TextStyle(
              color: myTurn ? AppColors.mintGreen : Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${_nameOf(1)} (Black): ${table.pocketedBy(1)}/${CarromGame.coinsPerPlayer}',
            style: TextStyle(
              color: table.currentPlayer == 1
                  ? AppColors.mintGreen
                  : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarromBoardPainter extends CustomPainter {
  _CarromBoardPainter({
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

  @override
  void paint(Canvas canvas, Size size) {
    final pocketPaint = Paint()..color = const Color(0xFF1E1E1E);
    final pr = size.width * CarromBoard.pocketRadius;
    for (final centre in [
      Offset(pr, pr),
      Offset(size.width - pr, pr),
      Offset(pr, size.height - pr),
      Offset(size.width - pr, size.height - pr),
    ]) {
      canvas.drawCircle(centre, pr, pocketPaint);
    }

    for (final piece in pieces) {
      if (piece.pocketed) continue;
      if (piece.type == CarromPieceType.striker && aimingPlayer != null) {
        continue;
      }
      _drawPiece(canvas, size, piece);
    }

    if (aimingPlayer != null) {
      final striker = CarromPiece(
        id: 99,
        type: CarromPieceType.striker,
        x: strikerX,
        y: CarromBoard.baselineY(aimingPlayer!),
      );
      _drawPiece(canvas, size, striker);
      final start = dragStart;
      final now = dragNow;
      if (start != null && now != null) {
        final pull = start - now;
        final end =
            Offset(striker.x * size.width, striker.y * size.height) + pull;
        canvas.drawLine(
          Offset(striker.x * size.width, striker.y * size.height),
          end,
          Paint()
            ..color = AppColors.mintGreen
            ..strokeWidth = 3,
        );
      }
    }
  }

  void _drawPiece(Canvas canvas, Size size, CarromPiece piece) {
    final centre = Offset(piece.x * size.width, piece.y * size.height);
    final radius = piece.radius * size.width;
    final color = switch (piece.type) {
      CarromPieceType.white => const Color(0xFFF5F0E6),
      CarromPieceType.black => const Color(0xFF222222),
      CarromPieceType.queen => const Color(0xFFC62828),
      CarromPieceType.striker => const Color(0xFFD7CCC8),
    };
    canvas.drawCircle(centre, radius, Paint()..color = color);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CarromBoardPainter oldDelegate) => true;
}
