import '../../carrom/carrom_engine.dart';

/// Whether the server is waiting for a shot, or the board is finished.
enum CarromTablePhase { aiming, gameOver }

/// The last shot the server played, so the phones can animate it.
class CarromShotRecord {
  const CarromShotRecord({
    required this.shooter,
    required this.x,
    required this.angle,
    required this.power,
  });

  final int shooter;
  final double x;
  final double angle;
  final double power;
}

/// The public board, read from the server's state. Every piece is in it: the
/// coins on the board, the coins in a pocket, and the striker.
class CarromTable {
  const CarromTable({
    required this.step,
    required this.phase,
    required this.currentPlayer,
    required this.winner,
    required this.winnerPoints,
    required this.queenCoveredBy,
    required this.queenPendingFor,
    required this.penaltyDue,
    required this.pocketed,
    required this.strikerX,
    required this.pieces,
    required this.status,
    required this.lastShot,
    required this.turnDeadline,
  });

  factory CarromTable.fromState(Map<String, dynamic> state) {
    final rawPieces =
        state['pieces'] is List ? state['pieces'] as List : const <Object?>[];
    final rawPocketed = state['pocketed'] is Map
        ? state['pocketed'] as Map
        : const <Object?, Object?>{};
    final rawPenalty = state['penaltyDue'] is List
        ? state['penaltyDue'] as List
        : const <Object?>[0, 0];
    final last = state['lastShot'] is Map ? state['lastShot'] as Map : null;
    final deadline = state['turnDeadline'];
    return CarromTable(
      step: _intOf(state['step']),
      phase: state['phase'] == 'gameOver'
          ? CarromTablePhase.gameOver
          : CarromTablePhase.aiming,
      currentPlayer: _intOf(state['currentPlayer']),
      winner: _optionalInt(state['winner']),
      winnerPoints: _intOf(state['winnerPoints']),
      queenCoveredBy: _optionalInt(state['queenCoveredBy']),
      queenPendingFor: _optionalInt(state['queenPendingFor']),
      penaltyDue: [for (final v in rawPenalty) _intOf(v)],
      pocketed: [
        for (final key in const ['0', '1'])
          [
            for (final id in (rawPocketed[key] as List? ?? const <Object?>[]))
              _intOf(id),
          ],
      ],
      strikerX: _doubleOf(state['strikerX'], 0.5),
      pieces: [
        for (final raw in rawPieces) _pieceOf(raw as Map<Object?, Object?>),
      ],
      status: state['status'] as String? ?? '',
      lastShot: last == null
          ? null
          : CarromShotRecord(
              shooter: _intOf(last['shooter']),
              x: _doubleOf(last['x'], 0.5),
              angle: _doubleOf(last['angle'], 0),
              power: _doubleOf(last['power'], 0),
            ),
      turnDeadline: deadline is num
          ? DateTime.fromMillisecondsSinceEpoch(deadline.toInt())
          : null,
    );
  }

  final int step;
  final CarromTablePhase phase;
  final int currentPlayer;
  final int? winner;
  final int winnerPoints;
  final int? queenCoveredBy;

  /// The player who pocketed the queen and still has to cover her.
  final int? queenPendingFor;

  /// Penalty coins each player owes.
  final List<int> penaltyDue;

  /// Coin ids each player has pocketed, in the order they went down.
  final List<List<int>> pocketed;
  final double strikerX;
  final List<CarromPiece> pieces;
  final String status;
  final CarromShotRecord? lastShot;

  /// When the seat to shoot runs out of time. Null for bots and once the board is finished.
  final DateTime? turnDeadline;

  bool get isGameOver => phase == CarromTablePhase.gameOver;

  int pocketedBy(int player) => pocketed[player].length;

  /// The striker, which sits on the shooter's baseline.
  CarromPiece get striker =>
      pieces.firstWhere((p) => p.type == CarromPieceType.striker);

  /// The coins, without the striker.
  List<CarromPiece> get coins =>
      pieces.where((p) => p.type != CarromPieceType.striker).toList();
}

CarromPiece _pieceOf(Map<Object?, Object?> raw) {
  final type = CarromPieceType.values.byName(raw['type'] as String);
  final piece = CarromPiece(
    id: _intOf(raw['id']),
    type: type,
    x: _doubleOf(raw['x'], 0.5),
    y: _doubleOf(raw['y'], 0.5),
  );
  piece.pocketed = raw['pocketed'] == true;
  return piece;
}

int _intOf(Object? value) => value is num ? value.toInt() : 0;

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;

double _doubleOf(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;
