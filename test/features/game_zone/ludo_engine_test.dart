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
        expect(engine.tokens[color]?.every((t) => t.state == TokenState.inYard), isTrue);
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
  });
}
