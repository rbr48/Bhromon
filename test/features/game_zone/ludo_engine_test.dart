import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/game_zone/ludo/ludo_engine.dart';

void main() {
  group('LudoEngine', () {
    late LudoEngine engine;

    setUp(() {
      engine = LudoEngine();
    });

    test('Initial tokens all in yard and Red starts', () {
      expect(engine.currentTurn, equals(LudoColor.red));
      for (final color in LudoColor.values) {
        expect(engine.tokens[color]?.length, equals(4));
        expect(engine.tokens[color]?.every((t) => t.state == TokenState.inYard),
            isTrue);
      }
    });

    test('Cannot move token out of yard without a 6', () {
      engine.currentDice = 5;
      engine.hasRolled = true;
      expect(engine.getMovableTokens(), isEmpty);
    });

    test('Rolling 6 allows token to leave yard onto track', () {
      engine.currentDice = 6;
      engine.hasRolled = true;
      final movable = engine.getMovableTokens();
      expect(movable.isNotEmpty, isTrue);

      final tokenToMove = movable.first;
      final extraTurn = engine.moveToken(tokenToMove);
      expect(tokenToMove.state, equals(TokenState.onTrack));
      expect(tokenToMove.boardIndex, equals(LudoColor.red.startIndex));
      expect(extraTurn, isTrue); // 6 gives extra turn
    });

    test('Safe square prevents token capture', () {
      // Place Red token at index 0 (safe start square)
      final redToken = engine.tokens[LudoColor.red]![0];
      redToken.state = TokenState.onTrack;
      redToken.stepCount = 0; // index 0 is safe

      // Move a Blue token to index 0
      final blueToken = engine.tokens[LudoColor.blue]![0];
      blueToken.state = TokenState.onTrack;
      blueToken.stepCount = 13; // Blue starts at 39, +13 = 52 % 52 = 0
      expect(blueToken.boardIndex, equals(0));

      engine.currentTurn = LudoColor.blue;
      engine.currentDice = 1;
      blueToken.stepCount = 12; // so +1 lands on 0

      engine.moveToken(blueToken);
      // Red token should NOT be captured because 0 is safe
      expect(redToken.state, equals(TokenState.onTrack));
    });
    test('A new turn starts with a fresh six counter', () {
      engine.consecutiveSixes = 2;
      engine.hasRolled = true;
      engine.currentDice = 6;
      engine.passTurn();
      expect(engine.currentTurn, LudoColor.green);
      expect(engine.consecutiveSixes, 0);
      expect(engine.hasRolled, isFalse);
      expect(engine.currentDice, isNull);
    });

    test('Third six in a row forfeits and resets for the next player', () {
      final seeded = LudoEngine(random: _SixesRandom());
      seeded.rollDice();
      seeded.hasRolled = false;
      seeded.rollDice();
      seeded.hasRolled = false;
      expect(seeded.rollDice(), -1);
      expect(seeded.currentTurn, LudoColor.green);
      expect(seeded.consecutiveSixes, 0);
      expect(seeded.rollDice(), 6);
      expect(seeded.consecutiveSixes, 1);
    });

    test('Bot captures when it can and avoids stepping into danger', () {
      final bot = LudoEngine(random: Random(1));
      bot.currentTurn = LudoColor.green;
      final capturer = bot.tokens[LudoColor.green]![0]
        ..state = TokenState.onTrack
        ..stepCount = 2; // index 15
      final other = bot.tokens[LudoColor.green]![1]
        ..state = TokenState.onTrack
        ..stepCount = 20; // index 33
      bot.tokens[LudoColor.red]![0]
        ..state = TokenState.onTrack
        ..stepCount = 18; // index 18, three squares ahead of the capturer
      bot.currentDice = 3;
      bot.hasRolled = true;
      expect(bot.getBestBotMove(), same(capturer));

      // Without a capture, prefer the move that does not land just ahead of an opponent.
      bot.tokens[LudoColor.red]![0]
        ..state = TokenState.onTrack
        ..stepCount =
            16; // index 16: green token 0 moving to 18 lands 2 ahead of it
      bot.tokens[LudoColor.yellow]![0]
        ..state = TokenState.onTrack
        ..stepCount =
            4; // index 30: green token 1 at 33 is 3 ahead (threatened now)
      expect(bot.isThreatened(18, LudoColor.green), isTrue);
      expect(bot.getBestBotMove(), same(other));
    });
  });
}

class _SixesRandom implements Random {
  @override
  int nextInt(int max) => 5;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}
