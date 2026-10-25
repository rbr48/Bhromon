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
      final moves =
          engine.getLegalMovesForPosition(const BoardPosition(6, 4)); // e2 pawn
      expect(moves.length, equals(2));
      expect(moves.any((m) => m.to == const BoardPosition(5, 4)), isTrue);
      expect(moves.any((m) => m.to == const BoardPosition(4, 4)), isTrue);
    });

    test('Knight can jump over pieces', () {
      final moves = engine
          .getLegalMovesForPosition(const BoardPosition(7, 1)); // b1 Knight
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

    test('Kingside Castling executes and moves both King and Rook', () {
      // Clear path for white kingside castling: clear f1 (7,5) and g1 (7,6)
      engine.board[7][5] = null;
      engine.board[7][6] = null;

      final kingMoves =
          engine.getLegalMovesForPosition(const BoardPosition(7, 4));
      final castleMove = kingMoves
          .where((m) => m.isCastling && m.to == const BoardPosition(7, 6))
          .toList();
      expect(castleMove.isNotEmpty, isTrue);

      final success = engine.makeMove(castleMove.first);
      expect(success, isTrue);
      expect(engine.pieceAt(7, 6)?.type, equals(PieceType.king));
      expect(engine.pieceAt(7, 5)?.type, equals(PieceType.rook));
      expect(engine.pieceAt(7, 4), isNull);
      expect(engine.pieceAt(7, 7), isNull);
    });

    test('Takeback undoMove reverts game state cleanly', () {
      const e4Move =
          ChessMove(from: BoardPosition(6, 4), to: BoardPosition(4, 4));
      engine.makeMove(e4Move);
      expect(engine.currentTurn, equals(PieceColor.black));
      expect(engine.pieceAt(4, 4)?.type, equals(PieceType.pawn));

      engine.undoMove();
      expect(engine.currentTurn, equals(PieceColor.white));
      expect(engine.pieceAt(4, 4), isNull);
      expect(engine.pieceAt(6, 4)?.type, equals(PieceType.pawn));
    });
  });

  group('ChessEngine rules', () {
    ChessEngine emptyBoard() {
      final e = ChessEngine();
      e.board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
      e.currentTurn = PieceColor.white;
      return e;
    }

    void put(ChessEngine e, String square, PieceType type, PieceColor color) {
      final col = 'abcdefgh'.indexOf(square[0]);
      final row = 8 - int.parse(square[1]);
      e.board[row][col] = ChessPiece(type, color);
    }

    BoardPosition sq(String s) =>
        BoardPosition(8 - int.parse(s[1]), 'abcdefgh'.indexOf(s[0]));

    int count(ChessEngine e, PieceType t, PieceColor c) => e.board
        .expand((r) => r)
        .where((p) => p != null && p.type == t && p.color == c)
        .length;

    test('Generating en passant moves never duplicates the captured pawn', () {
      final e = emptyBoard();
      put(e, 'a1', PieceType.king, PieceColor.white);
      put(e, 'h8', PieceType.king, PieceColor.black);
      put(e, 'e2', PieceType.pawn, PieceColor.white);
      put(e, 'd4', PieceType.pawn, PieceColor.black);
      expect(e.makeMove(ChessMove(from: sq('e2'), to: sq('e4'))), isTrue);

      final moves = e.getLegalMovesForPosition(sq('d4'));
      e.getAllLegalMoves(PieceColor.black);
      expect(moves.any((m) => m.isEnPassant && m.to == sq('e3')), isTrue);
      expect(count(e, PieceType.pawn, PieceColor.white), 1);
      expect(e.pieceAt(5, 4), isNull);

      expect(e.makeMove(moves.firstWhere((m) => m.isEnPassant)), isTrue);
      expect(count(e, PieceType.pawn, PieceColor.white), 0);
      e.undoMove();
      expect(count(e, PieceType.pawn, PieceColor.white), 1);
      expect(e.pieceAt(4, 4)?.color, PieceColor.white);
    });

    test('Castling requires the rook to still be on its corner', () {
      final e = emptyBoard();
      put(e, 'e1', PieceType.king, PieceColor.white);
      put(e, 'a8', PieceType.king, PieceColor.black);
      expect(e.getLegalMovesForPosition(sq('e1')).where((m) => m.isCastling),
          isEmpty);

      put(e, 'h1', PieceType.rook, PieceColor.black);
      expect(e.getLegalMovesForPosition(sq('e1')).where((m) => m.isCastling),
          isEmpty);
    });

    test('Cannot castle through a square attacked by a pawn', () {
      final e = emptyBoard();
      put(e, 'e1', PieceType.king, PieceColor.white);
      put(e, 'h1', PieceType.rook, PieceColor.white);
      put(e, 'a8', PieceType.king, PieceColor.black);
      put(e, 'e2', PieceType.pawn, PieceColor.black); // attacks d1 and f1
      expect(e.getLegalMovesForPosition(sq('e1')).where((m) => m.isCastling),
          isEmpty);
    });

    test('Capturing a rook on its corner removes that castling right', () {
      final e = emptyBoard();
      put(e, 'e1', PieceType.king, PieceColor.white);
      put(e, 'h1', PieceType.rook, PieceColor.white);
      put(e, 'e8', PieceType.king, PieceColor.black);
      put(e, 'h8', PieceType.rook, PieceColor.black);
      expect(e.makeMove(ChessMove(from: sq('h1'), to: sq('h8'))), isTrue);
      expect(e.blackRook7Moved, isTrue);
      e.board[0][7] =
          const ChessPiece(PieceType.rook, PieceColor.black); // put a rook back
      expect(e.getAllLegalMoves(PieceColor.black).where((m) => m.isCastling),
          isEmpty);
    });

    test('Takeback restores castling rights and en passant target', () {
      final e = emptyBoard();
      put(e, 'e1', PieceType.king, PieceColor.white);
      put(e, 'h1', PieceType.rook, PieceColor.white);
      put(e, 'e8', PieceType.king, PieceColor.black);
      e.makeMove(ChessMove(from: sq('e1'), to: sq('e2')));
      e.makeMove(ChessMove(from: sq('e8'), to: sq('d8')));
      e.makeMove(ChessMove(from: sq('e2'), to: sq('e1')));
      e.undoMove();
      e.undoMove();
      e.undoMove();
      expect(e.whiteKingMoved, isFalse);
      expect(e.getLegalMovesForPosition(sq('e1')).any((m) => m.isCastling),
          isTrue);

      final ep = emptyBoard();
      put(ep, 'a1', PieceType.king, PieceColor.white);
      put(ep, 'h8', PieceType.king, PieceColor.black);
      put(ep, 'e2', PieceType.pawn, PieceColor.white);
      put(ep, 'd4', PieceType.pawn, PieceColor.black);
      ep.makeMove(ChessMove(from: sq('e2'), to: sq('e4')));
      ep.makeMove(ChessMove(from: sq('h8'), to: sq('g8')));
      ep.undoMove();
      expect(ep.enPassantTarget, sq('e3'));
      expect(ep.getLegalMovesForPosition(sq('d4')).any((m) => m.isEnPassant),
          isTrue);
    });

    test('Promotion honours the chosen piece and undo restores the pawn', () {
      final e = emptyBoard();
      put(e, 'a1', PieceType.king, PieceColor.white);
      put(e, 'h1', PieceType.king, PieceColor.black);
      put(e, 'b7', PieceType.pawn, PieceColor.white);
      expect(
          e.makeMove(ChessMove(
              from: sq('b7'), to: sq('b8'), promotion: PieceType.knight)),
          isTrue);
      expect(e.pieceAt(0, 1)?.type, PieceType.knight);
      expect(e.moveNotation.last, 'b8=N');
      e.undoMove();
      expect(e.pieceAt(1, 1)?.type, PieceType.pawn);
    });

    test('Illegal moves are rejected', () {
      final e = ChessEngine();
      expect(e.makeMove(ChessMove(from: sq('e2'), to: sq('e5'))), isFalse);
      expect(e.makeMove(ChessMove(from: sq('e7'), to: sq('e5'))), isFalse);
    });

    test('Notation, check and mate suffixes', () {
      final e = ChessEngine();
      for (final m in [
        ['f2', 'f3'],
        ['e7', 'e5'],
        ['g2', 'g4'],
        ['d8', 'h4']
      ]) {
        expect(e.makeMove(ChessMove(from: sq(m[0]), to: sq(m[1]))), isTrue);
      }
      expect(e.moveNotation, ['f3', 'e5', 'g4', 'Qh4#']);
      expect(e.isCheckmate(PieceColor.white), isTrue);
    });

    test('Draw rules: insufficient material, fifty moves, threefold repetition',
        () {
      final kk = emptyBoard();
      put(kk, 'e1', PieceType.king, PieceColor.white);
      put(kk, 'e8', PieceType.king, PieceColor.black);
      put(kk, 'c1', PieceType.bishop, PieceColor.white);
      expect(kk.drawReason, DrawReason.insufficientMaterial);

      final fifty = emptyBoard();
      put(fifty, 'e1', PieceType.king, PieceColor.white);
      put(fifty, 'e8', PieceType.king, PieceColor.black);
      put(fifty, 'a1', PieceType.rook, PieceColor.white);
      fifty.halfmoveClock = 100;
      expect(fifty.drawReason, DrawReason.fiftyMoveRule);

      final rep = ChessEngine();
      for (int i = 0; i < 2; i++) {
        rep.makeMove(ChessMove(from: sq('g1'), to: sq('f3')));
        rep.makeMove(ChessMove(from: sq('g8'), to: sq('f6')));
        rep.makeMove(ChessMove(from: sq('f3'), to: sq('g1')));
        rep.makeMove(ChessMove(from: sq('f6'), to: sq('g8')));
      }
      expect(rep.drawReason, DrawReason.threefoldRepetition);
    });

    test('AI finds a mate in one', () {
      final e = emptyBoard();
      put(e, 'g1', PieceType.king, PieceColor.white);
      put(e, 'a1', PieceType.rook, PieceColor.white);
      put(e, 'h8', PieceType.king, PieceColor.black);
      put(e, 'g7', PieceType.pawn, PieceColor.black);
      put(e, 'h7', PieceType.pawn, PieceColor.black);
      final move = e.findBestMoveForAI(PieceColor.white, depth: 2);
      expect(move?.from, sq('a1'));
      expect(move?.to, sq('a8'));
    });

    test('AI worker searches a copy and leaves the game untouched', () {
      final e = ChessEngine();
      e.makeMove(ChessMove(from: sq('e2'), to: sq('e4')));
      final move = chessAiWorker(ChessAiRequest(e, PieceColor.black, 2));
      expect(move, isNotNull);
      expect(e.currentTurn, PieceColor.black);
      expect(e.moveHistory.length, 1);
      expect(e.makeMove(move!), isTrue);
    });
  });
}
