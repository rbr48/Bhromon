import 'package:bhromon/features/game_zone/carrom/carrom_engine.dart';
import 'package:bhromon/features/game_zone/domain/models/carrom_table.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _piece(int id, String type, double x, double y,
        {bool pocketed = false}) =>
    {'id': id, 'type': type, 'x': x, 'y': y, 'pocketed': pocketed};

Map<String, dynamic> _state({
  String phase = 'aiming',
  int currentPlayer = 0,
  List<Map<String, dynamic>>? pieces,
  Map<String, dynamic>? pocketed,
  Map<String, dynamic>? lastShot,
  String status = '',
  Object? turnDeadline = 1700000060000,
}) =>
    {
      'step': 4,
      'phase': phase,
      'currentPlayer': currentPlayer,
      'winner': null,
      'winnerPoints': 0,
      'queenCoveredBy': null,
      'queenPendingFor': null,
      'penaltyDue': [0, 0],
      'pocketed': pocketed ?? {'0': <int>[], '1': <int>[]},
      'strikerX': 0.5,
      'pieces': pieces ??
          [
            _piece(0, 'queen', 0.5, 0.5),
            _piece(1, 'white', 0.4, 0.4),
            _piece(2, 'black', 0.6, 0.6, pocketed: true),
            _piece(99, 'striker', 0.5, 0.845),
          ],
      'status': status,
      'lastShot': lastShot,
      'turnDeadline': turnDeadline,
    };

void main() {
  group('the public board', () {
    test('reads every piece with its type and whether it is in a pocket', () {
      final table = CarromTable.fromState(_state());
      expect(table.pieces, hasLength(4));
      expect(table.pieces.first.type, CarromPieceType.queen);
      expect(table.striker.type, CarromPieceType.striker);
      expect(table.coins, hasLength(3));
      expect(table.pieces[2].pocketed, isTrue);
      expect(table.pieces[1].pocketed, isFalse);
    });

    test('counts each player’s pocketed coins from the map', () {
      final table = CarromTable.fromState(_state(pocketed: {
        '0': [1, 5, 7],
        '1': [2],
      }));
      expect(table.pocketedBy(0), 3);
      expect(table.pocketedBy(1), 1);
    });

    test('reads the last shot the server played, so the phones can animate it',
        () {
      final table = CarromTable.fromState(_state(lastShot: {
        'shooter': 1,
        'x': 0.42,
        'angle': -1.2,
        'power': 0.7,
      }));
      final shot = table.lastShot!;
      expect(shot.shooter, 1);
      expect(shot.x, 0.42);
      expect(shot.angle, -1.2);
      expect(shot.power, 0.7);
    });

    test('a finished board is game over, and the turn has no deadline', () {
      final table = CarromTable.fromState(_state(
        phase: 'gameOver',
        turnDeadline: null,
      ));
      expect(table.isGameOver, isTrue);
      expect(table.turnDeadline, isNull);
    });

    test('a shot to be timed reads its deadline', () {
      final table = CarromTable.fromState(_state());
      expect(table.turnDeadline,
          DateTime.fromMillisecondsSinceEpoch(1700000060000));
    });

    test('an empty state reads as a board waiting to be laid out', () {
      final table = CarromTable.fromState(const {});
      expect(table.pieces, isEmpty);
      expect(table.lastShot, isNull);
      expect(table.isGameOver, isFalse);
    });
  });
}
