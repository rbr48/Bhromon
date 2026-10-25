import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/game_zone/chess/chess_engine.dart';

void main() {
  group('ChessEngine', () {
    late ChessEngine engine;

    setUp(() {
      engine = ChessEngine();
    });

    test('Initial board setup has 32 pieces and correct piece placements', () {
      expect(engine.pieceAt(7, 4)?.type, equals(PieceType.king));
      expect(engine.pieceAt(7, 4)?.color, equals(PieceColor.white));
      expect(engine.pieceAt(0, 4)?.type, equals(PieceType.king));
      expect(engine.pieceAt(0, 4)?.color, equals(PieceColor.black));

      int pieceCount = 0;
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          if (engine.pieceAt(r, c) != null) pieceCount++;
        }
      }
      expect(pieceCount, equals(32));
    });

    test('White Pawn initial moves allow 1 or 2 steps forward', () {
      final moves = engine.getLegalMovesForPosition(const BoardPosition(6, 4)); // e2 pawn
      expect(moves.length, equals(2));
      expect(moves.any((m) => m.to == const BoardPosition(5, 4)), isTrue);
      expect(moves.any((m) => m.to == const BoardPosition(4, 4)), isTrue);
    });

    test('Knight can jump over pieces', () {
      final moves = engine.getLegalMovesForPosition(const BoardPosition(7, 1)); // b1 Knight
      expect(moves.length, equals(2));
      expect(moves.any((m) => m.to == const BoardPosition(5, 0)), isTrue); // a3
      expect(moves.any((m) => m.to == const BoardPosition(5, 2)), isTrue); // c3
    });

    test('Pawn advance and AI can generate legal response', () {
      // Play 1. e4 (6,4 -> 4,4)
      const e4Move = ChessMove(
        from: BoardPosition(6, 4),
        to: BoardPosition(4, 4),
      );
      final success = engine.makeMove(e4Move);
      expect(success, isTrue);
      expect(engine.currentTurn, equals(PieceColor.black));

      // AI finds a move for Black
      final aiMove = engine.findBestMoveForAI(PieceColor.black, depth: 1);
      expect(aiMove, isNotNull);
      expect(aiMove!.from.isValid, isTrue);
      expect(aiMove.to.isValid, isTrue);
    });
  });
}
