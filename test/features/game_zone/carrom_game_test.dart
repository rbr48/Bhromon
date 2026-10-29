import 'dart:math';

import 'package:bhromon/features/game_zone/carrom/carrom_engine.dart';
import 'package:bhromon/features/game_zone/carrom/carrom_game.dart';
import 'package:flutter_test/flutter_test.dart';

CarromPiece _coin(int id, CarromPieceType type, double x, double y) =>
    CarromPiece(id: id, type: type, x: x, y: y);

/// A game with only the given coins on the board (the rest already pocketed).
CarromGame _gameWith(List<CarromPiece> onBoard) {
  final g = CarromGame(random: Random(1));
  for (final c in g.coins) {
    c.pocketed = true;
  }
  g.coins = [
    ...onBoard,
    ...g.coins
        .where((c) => !onBoard.any((o) => o.type == c.type && o.id == c.id)),
  ];
  return g;
}

void main() {
  group('CarromBoard physics', () {
    test('Friction brings a sliding coin to rest', () {
      final c = _coin(1, CarromPieceType.white, 0.5, 0.5)..vx = 0.8;
      CarromBoard.simulateToRest([c]);
      expect(c.isMoving, isFalse);
      expect(c.x, greaterThan(0.6));
      expect(c.pocketed, isFalse);
    });

    test('A coin too fast for the pocket rattles out', () {
      // Heading straight into the bottom-right pocket at full pace.
      final c = _coin(1, CarromPieceType.white, 0.9, 0.9)
        ..vx = 3.0
        ..vy = 3.0;
      final dropped = <CarromPiece>[];
      for (int i = 0; i < 12; i++) {
        dropped.addAll(CarromBoard.step([c]));
      }
      expect(dropped, isEmpty, reason: 'too fast on the first pass');
    });

    test('The striker contact records the first coin it hits', () {
      final striker =
          CarromPiece(id: 99, type: CarromPieceType.striker, x: 0.5, y: 0.8)
            ..vy = -1.5;
      final coin = _coin(3, CarromPieceType.black, 0.5, 0.6);
      final contact = StrikerContact();
      CarromBoard.simulateToRest([coin, striker], contact: contact);
      expect(contact.firstCoinId, 3);
      expect(contact.cushionFirst, isFalse);
    });

    test('A coin bounces off the cushion', () {
      final c = _coin(1, CarromPieceType.white, 0.5, 0.5)..vx = 2.0;
      for (int i = 0; i < 200; i++) {
        CarromBoard.step([c]);
      }
      expect(c.vx, lessThan(0));
      expect(c.x, lessThanOrEqualTo(1 - CarromBoard.coinRadius));
    });

    test('A straight shot sends a coin into the pocket', () {
      final c = _coin(1, CarromPieceType.white, 0.85, 0.85);
      final s =
          CarromPiece(id: 99, type: CarromPieceType.striker, x: 0.6, y: 0.6);
      const speed = 1.2;
      s
        ..vx = speed / sqrt2
        ..vy = speed / sqrt2;
      final dropped = CarromBoard.simulateToRest([c, s]);
      expect(dropped, contains(c));
    });

    test('Head-on hit hands most of the striker momentum to the coin', () {
      final c = _coin(1, CarromPieceType.white, 0.5, 0.4);
      // Striker just short of touching, so the next step is the collision.
      final gap = c.radius + CarromBoard.strikerRadius + 0.001;
      final s = CarromPiece(
          id: 99, type: CarromPieceType.striker, x: 0.5, y: 0.4 + gap)
        ..vy = -1.0;
      final before = s.vy * s.mass;
      CarromBoard.step([c, s]);
      expect(c.vy, lessThan(0));
      expect(c.vy.abs(), greaterThan(s.vy.abs()));
      final after = c.vy * c.mass + s.vy * s.mass;
      expect(after, closeTo(before, 0.02));
    });
  });

  group('CarromGame rules', () {
    test('Initial board has 9 white, 9 black and the queen, none overlapping',
        () {
      final g = CarromGame(random: Random(1));
      expect(g.coins.where((c) => c.type == CarromPieceType.white).length, 9);
      expect(g.coins.where((c) => c.type == CarromPieceType.black).length, 9);
      expect(g.coins.where((c) => c.type == CarromPieceType.queen).length, 1);
      for (int i = 0; i < g.coins.length; i++) {
        for (int j = i + 1; j < g.coins.length; j++) {
          final a = g.coins[i];
          final b = g.coins[j];
          expect(sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)),
              greaterThanOrEqualTo(a.radius + b.radius));
        }
      }
      expect(g.strikerPlacementValid, isTrue);
    });

    test('Pocketing your own coin earns another shot', () {
      final g = CarromGame(random: Random(1));
      final white = g.coins.firstWhere((c) => c.type == CarromPieceType.white)
        ..pocketed = true;
      g.scoreShot([white]);
      expect(g.currentPlayer, 0);
      expect(g.pocketed[0], [white]);
    });

    test('Pocketing only an opponent coin ends the turn and counts for them',
        () {
      final g = CarromGame(random: Random(1));
      final black = g.coins.firstWhere((c) => c.type == CarromPieceType.black)
        ..pocketed = true;
      g.scoreShot([black]);
      expect(g.currentPlayer, 1);
      expect(g.pocketed[1], [black]);
    });

    test('Striker foul returns that shot\'s coins plus a penalty coin', () {
      final g = CarromGame(random: Random(1));
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      whites[0].pocketed = true;
      g.scoreShot([whites[0]]);
      expect(g.pocketed[0].length, 1);

      whites[1].pocketed = true;
      g.striker.pocketed = true;
      g.scoreShot([whites[1], g.striker]);
      expect(g.pocketed[0], isEmpty);
      expect(whites[0].pocketed, isFalse);
      expect(whites[1].pocketed, isFalse);
      expect(g.currentPlayer, 1);
      expect(g.striker.pocketed, isFalse);
    });

    test('Queen needs an own coin first, and must be covered on the next shot',
        () {
      final g = CarromGame(random: Random(1));
      g.queen.pocketed = true;
      g.scoreShot([g.queen]);
      expect(g.queen.pocketed, isFalse, reason: 'no own coin yet');
      expect(g.currentPlayer, 1);

      final g2 = CarromGame(random: Random(2));
      final whites =
          g2.coins.where((c) => c.type == CarromPieceType.white).toList();
      whites[0].pocketed = true;
      g2.scoreShot([whites[0]]);
      g2.queen.pocketed = true;
      g2.scoreShot([g2.queen]);
      expect(g2.queenPendingFor, 0);
      expect(g2.currentPlayer, 0, reason: 'you get the cover shot');
      g2.scoreShot([]); // missed the cover
      expect(g2.queen.pocketed, isFalse);
      expect(g2.queenCoveredBy, isNull);
      expect(g2.currentPlayer, 1);

      final g3 = CarromGame(random: Random(3));
      final w3 =
          g3.coins.where((c) => c.type == CarromPieceType.white).toList();
      w3[0].pocketed = true;
      g3.scoreShot([w3[0]]);
      g3.queen.pocketed = true;
      w3[1].pocketed = true;
      g3.scoreShot([g3.queen, w3[1]]);
      expect(g3.queenCoveredBy, 0);
    });

    test('ICF: pocketing your last coin before the Queen is covered is a foul',
        () {
      final g = CarromGame(random: Random(1));
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      // Eight coins down legally.
      for (final w in whites.take(8)) {
        w.pocketed = true;
      }
      g.scoreShot(whites.take(8).toList());
      expect(g.pocketed[0].length, 8);
      expect(g.currentPlayer, 0);

      // The ninth goes down with the Queen still on the board: foul.
      whites[8].pocketed = true;
      g.scoreShot([whites[8]]);
      expect(whites[8].pocketed, isFalse, reason: 'last coin returned');
      expect(g.pocketed[0].length, 7, reason: 'plus one penalty coin');
      expect(g.currentPlayer, 1);
      expect(g.winner, isNull);
    });

    test('ICF: covering the Queen with your last coin in one shot wins', () {
      final g = CarromGame(random: Random(2));
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      for (final w in whites.take(8)) {
        w.pocketed = true;
      }
      g.scoreShot(whites.take(8).toList());
      whites[8].pocketed = true;
      g.queen.pocketed = true;
      g.scoreShot([g.queen, whites[8]]);
      expect(g.boardWinner, 0);
      expect(g.boardPoints, 9 + 3);
      expect(g.matchScore, [12, 0]);
    });

    test('ICF: your last coin may cover the Queen on the next shot', () {
      final g = CarromGame(random: Random(2));
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      for (final w in whites.take(8)) {
        w.pocketed = true;
      }
      g.scoreShot(whites.take(8).toList());
      g.queen.pocketed = true;
      g.scoreShot([g.queen]);
      expect(g.queenPendingFor, 0);
      expect(g.currentPlayer, 0, reason: 'shoots again to cover her');
      whites[8].pocketed = true;
      g.scoreShot([whites[8]]);
      expect(g.boardWinner, 0);
      expect(g.boardPoints, 12);
    });

    test('ICF: hitting a coin behind your baseline directly is a foul', () {
      // A white coin sits behind player 0's baseline; the striker is fired
      // straight back at it.
      final behind = _coin(1, CarromPieceType.white, 0.5, 0.93);
      final g = _gameWith([behind]);
      g.placeStriker(0.5);
      expect(g.shoot(pi / 2, 0.4), isTrue);
      g.simulateToRest();
      expect(g.status, contains('behind the baseline'));
      expect(g.currentPlayer, 1);
      expect(g.penaltyDue[0], 1);
    });

    test('A coin behind the baseline may be reached off a cushion', () {
      final behind = _coin(1, CarromPieceType.white, 0.5, 0.93);
      final g = _gameWith([behind]);
      g.placeStriker(0.3);
      // Up into the top cushion, well clear of the coin on the way.
      expect(g.shoot(-pi / 2, 0.9), isTrue);
      g.simulateToRest();
      expect(g.status, isNot(contains('behind the baseline')));
    });

    test('ICF: pocketing the opponent\'s last coin is a foul', () {
      final g = CarromGame(random: Random(3));
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      final blacks =
          g.coins.where((c) => c.type == CarromPieceType.black).toList();
      whites[0].pocketed = true;
      g.scoreShot([whites[0]]); // you have one coin to pay penalties with
      g.pocketed[1].addAll(blacks.take(8));
      for (final b in blacks.take(8)) {
        b.pocketed = true;
      }
      blacks[8].pocketed = true;
      g.scoreShot([blacks[8]]);
      expect(blacks[8].pocketed, isFalse,
          reason: 'opponent last coin returned');
      expect(g.remaining(1), 1);
      expect(g.pocketed[0], isEmpty, reason: 'penalty coin paid');
      expect(g.currentPlayer, 1);
    });

    test('ICF: a penalty with nothing to pay is due from the next coin', () {
      final g = CarromGame(random: Random(4));
      g.striker.pocketed = true;
      g.scoreShot([g.striker]);
      expect(g.penaltyDue[0], 1);
      expect(g.currentPlayer, 1);

      g.currentPlayer = 0;
      final white = g.coins.firstWhere((c) => c.type == CarromPieceType.white)
        ..pocketed = true;
      g.scoreShot([white]);
      expect(g.penaltyDue[0], 0);
      expect(white.pocketed, isFalse, reason: 'paid as the due penalty');
      expect(g.pocketed[0], isEmpty);
      expect(g.currentPlayer, 0, reason: 'a legal pocket still shoots again');
    });

    test('After covering the Queen, the last coin wins the board', () {
      final g = CarromGame(random: Random(5));
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      for (final w in whites.take(7)) {
        w.pocketed = true;
      }
      g.scoreShot(whites.take(7).toList());
      g.queen.pocketed = true;
      whites[7].pocketed = true;
      g.scoreShot([g.queen, whites[7]]);
      expect(g.queenCoveredBy, 0);
      whites[8].pocketed = true;
      g.scoreShot([whites[8]]);
      expect(g.boardWinner, 0);
      expect(g.boardPoints, 9 + 3);
      expect(g.matchScore, [12, 0]);
      // The match carries on: a fresh board, and the other player breaks.
      expect(g.phase, CarromPhase.aiming);
      expect(g.board, 2);
      expect(g.currentPlayer, 1);
      expect(g.remaining(0), 9);
      expect(g.winner, isNull);
    });

    test('The Queen\'s points stop counting at 22, and 25 wins the match', () {
      final g = CarromGame(random: Random(6));
      void winBoardWithQueen() {
        final p = g.currentPlayer = 0;
        final whites = g.coins
            .where((c) => c.type == CarromGame.colorOf(p) && !c.pocketed)
            .toList();
        for (final w in whites.take(whites.length - 1)) {
          w.pocketed = true;
        }
        g.scoreShot(whites.take(whites.length - 1).toList());
        g.queen.pocketed = true;
        whites.last.pocketed = true;
        g.scoreShot([g.queen, whites.last]);
      }

      g.matchScore[0] = 21;
      winBoardWithQueen();
      expect(g.boardPoints, 12, reason: 'under 22: the Queen counts');
      expect(g.phase, CarromPhase.gameOver);
      expect(g.winner, 0);
      expect(g.winnerPoints, 33);

      g.reset();
      g.matchScore[0] = 22;
      winBoardWithQueen();
      expect(g.boardPoints, 9, reason: 'at 22 the Queen no longer counts');
    });

    test('The match ends with the leader after eight boards', () {
      final g = CarromGame(random: Random(7));
      g.board = 8;
      g.matchScore[1] = 10;
      final whites =
          g.coins.where((c) => c.type == CarromPieceType.white).toList();
      for (final w in whites.take(8)) {
        w.pocketed = true;
      }
      g.scoreShot(whites.take(8).toList());
      g.queen.pocketed = true;
      whites[8].pocketed = true;
      g.scoreShot([g.queen, whites[8]]);
      expect(g.matchScore, [12, 10]);
      expect(g.phase, CarromPhase.gameOver);
      expect(g.winner, 0);
    });

    test('The striker cannot be placed on top of a coin', () {
      final g = _gameWith(
          [_coin(1, CarromPieceType.white, 0.5, CarromBoard.baselineY(0))]);
      expect(g.canPlaceStriker(0.5), isFalse);
      expect(g.canPlaceStriker(0.7), isTrue);
      g.placeStriker(0.5);
      expect(g.shoot(-pi / 2, 0.5), isFalse);
    });

    test('A full shot plays out and is scored', () {
      final g = CarromGame(random: Random(5));
      expect(g.shoot(-pi / 2, 1.0), isTrue);
      g.simulateToRest();
      expect(g.phase, isNot(CarromPhase.moving));
      expect(CarromBoard.isSettled(g.allPieces), isTrue);
    });
  });

  group('CarromBot', () {
    test('Bot sinks an easy coin and avoids fouls', () {
      final g = _gameWith([
        _coin(1, CarromPieceType.black, 0.8,
            0.8), // between the bot and the bottom-right pocket
        _coin(2, CarromPieceType.white, 0.3, 0.5),
      ])
        ..currentPlayer = 1
        ..queenCoveredBy = 0; // so this last black coin may legally drop
      g.placeStriker(0.5);
      final shot = CarromBot.chooseShot(g.botRequest(aimNoise: 0));
      g.placeStriker(shot.x);
      expect(g.shoot(shot.angle, shot.power), isTrue);
      g.simulateToRest();
      expect(g.boardWinner, 1);
    });

    test('Bot covers a pending Queen with its last coin', () {
      final g = _gameWith([
        _coin(1, CarromPieceType.black, 0.8, 0.8),
        _coin(2, CarromPieceType.white, 0.3, 0.5),
      ])
        ..currentPlayer = 1
        ..queenPendingFor = 1;
      g.queen.pocketed = true;
      g.pocketed[1].add(g.coins
          .firstWhere((c) => c.type == CarromPieceType.black && c.pocketed));
      g.placeStriker(0.5);
      final shot = CarromBot.chooseShot(g.botRequest(aimNoise: 0));
      g.placeStriker(shot.x);
      expect(g.shoot(shot.angle, shot.power), isTrue);
      g.simulateToRest();
      expect(g.boardWinner, 1);
    });

    test('Bot plays a whole board against itself to a finish', () {
      final g = CarromGame(random: Random(11))..vsBot = true;
      var shots = 0;
      while (g.boardWinner == null && shots < 400) {
        final shot = CarromBot.chooseShot(g.botRequest(aimNoise: 0.004));
        g.placeStriker(shot.x);
        if (!g.shoot(shot.angle, shot.power)) {
          g.placeStriker(0.5);
          g.shoot(g.currentPlayer == 0 ? -pi / 2 : pi / 2, 0.5);
        }
        g.simulateToRest();
        shots++;
      }
      expect(g.boardWinner, isNotNull, reason: 'after $shots shots');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
