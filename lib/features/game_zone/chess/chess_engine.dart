import 'dart:math';

enum PieceType { pawn, knight, bishop, rook, queen, king }

enum PieceColor { white, black }

class ChessPiece {
  final PieceType type;
  final PieceColor color;

  const ChessPiece(this.type, this.color);

  String get symbol {
    switch (type) {
      case PieceType.king:
        return color == PieceColor.white ? '♔' : '♚';
      case PieceType.queen:
        return color == PieceColor.white ? '♕' : '♛';
      case PieceType.rook:
        return color == PieceColor.white ? '♖' : '♜';
      case PieceType.bishop:
        return color == PieceColor.white ? '♗' : '♝';
      case PieceType.knight:
        return color == PieceColor.white ? '♘' : '♞';
      case PieceType.pawn:
        return color == PieceColor.white ? '♙' : '♟';
    }
  }

  int get baseValue {
    switch (type) {
      case PieceType.pawn:
        return 100;
      case PieceType.knight:
        return 320;
      case PieceType.bishop:
        return 330;
      case PieceType.rook:
        return 500;
      case PieceType.queen:
        return 900;
      case PieceType.king:
        return 20000;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessPiece &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          color == other.color;

  @override
  int get hashCode => type.hashCode ^ color.hashCode;
}

class BoardPosition {
  final int row;
  final int col;

  const BoardPosition(this.row, this.col);

  bool get isValid => row >= 0 && row < 8 && col >= 0 && col < 8;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardPosition &&
          runtimeType == other.runtimeType &&
          row == other.row &&
          col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;

  @override
  String toString() => '($row, $col)';
}

class ChessMove {
  final BoardPosition from;
  final BoardPosition to;
  final ChessPiece? capturedPiece;
  final PieceType? promotion;

  const ChessMove({
    required this.from,
    required this.to,
    this.capturedPiece,
    this.promotion,
  });

  @override
  String toString() => '$from -> $to';
}

class ChessEngine {
  late List<List<ChessPiece?>> board;
  PieceColor currentTurn = PieceColor.white;
  final List<ChessMove> moveHistory = [];
  final List<ChessPiece> capturedByWhite = [];
  final List<ChessPiece> capturedByBlack = [];

  ChessEngine() {
    reset();
  }

  void reset() {
    board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    moveHistory.clear();
    capturedByWhite.clear();
    capturedByBlack.clear();
    currentTurn = PieceColor.white;

    // Black pieces (row 0 & 1)
    board[0][0] = const ChessPiece(PieceType.rook, PieceColor.black);
    board[0][1] = const ChessPiece(PieceType.knight, PieceColor.black);
    board[0][2] = const ChessPiece(PieceType.bishop, PieceColor.black);
    board[0][3] = const ChessPiece(PieceType.queen, PieceColor.black);
    board[0][4] = const ChessPiece(PieceType.king, PieceColor.black);
    board[0][5] = const ChessPiece(PieceType.bishop, PieceColor.black);
    board[0][6] = const ChessPiece(PieceType.knight, PieceColor.black);
    board[0][7] = const ChessPiece(PieceType.rook, PieceColor.black);
    for (int c = 0; c < 8; c++) {
      board[1][c] = const ChessPiece(PieceType.pawn, PieceColor.black);
    }

    // White pieces (row 6 & 7)
    for (int c = 0; c < 8; c++) {
      board[6][c] = const ChessPiece(PieceType.pawn, PieceColor.white);
    }
    board[7][0] = const ChessPiece(PieceType.rook, PieceColor.white);
    board[7][1] = const ChessPiece(PieceType.knight, PieceColor.white);
    board[7][2] = const ChessPiece(PieceType.bishop, PieceColor.white);
    board[7][3] = const ChessPiece(PieceType.queen, PieceColor.white);
    board[7][4] = const ChessPiece(PieceType.king, PieceColor.white);
    board[7][5] = const ChessPiece(PieceType.bishop, PieceColor.white);
    board[7][6] = const ChessPiece(PieceType.knight, PieceColor.white);
    board[7][7] = const ChessPiece(PieceType.rook, PieceColor.white);
  }

  ChessPiece? pieceAt(int row, int col) {
    if (row < 0 || row >= 8 || col < 0 || col >= 8) return null;
    return board[row][col];
  }

  List<ChessMove> getLegalMovesForPosition(BoardPosition pos) {
    final piece = pieceAt(pos.row, pos.col);
    if (piece == null || piece.color != currentTurn) return [];

    final pseudoMoves = _generatePseudoMoves(pos, piece);
    final legalMoves = <ChessMove>[];

    for (final move in pseudoMoves) {
      _applyRawMove(move);
      if (!_isKingInCheck(piece.color)) {
        legalMoves.add(move);
      }
      _undoRawMove(move);
    }

    return legalMoves;
  }

  List<ChessMove> getAllLegalMoves(PieceColor color) {
    final moves = <ChessMove>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && piece.color == color) {
          final pos = BoardPosition(r, c);
          final pseudoMoves = _generatePseudoMoves(pos, piece);
          for (final move in pseudoMoves) {
            _applyRawMove(move);
            if (!_isKingInCheck(color)) {
              moves.add(move);
            }
            _undoRawMove(move);
          }
        }
      }
    }
    return moves;
  }

  bool isCheckmate(PieceColor color) {
    return _isKingInCheck(color) && getAllLegalMoves(color).isEmpty;
  }

  bool isStalemate(PieceColor color) {
    return !_isKingInCheck(color) && getAllLegalMoves(color).isEmpty;
  }

  bool makeMove(ChessMove move) {
    final piece = board[move.from.row][move.from.col];
    if (piece == null || piece.color != currentTurn) return false;

    final target = board[move.to.row][move.to.col];
    if (target != null) {
      if (currentTurn == PieceColor.white) {
        capturedByWhite.add(target);
      } else {
        capturedByBlack.add(target);
      }
    }

    // Pawn promotion
    ChessPiece finalPiece = piece;
    if (piece.type == PieceType.pawn) {
      if ((piece.color == PieceColor.white && move.to.row == 0) ||
          (piece.color == PieceColor.black && move.to.row == 7)) {
        finalPiece = ChessPiece(PieceType.queen, piece.color);
      }
    }

    board[move.to.row][move.to.col] = finalPiece;
    board[move.from.row][move.from.col] = null;
    moveHistory.add(move);

    currentTurn = currentTurn == PieceColor.white ? PieceColor.black : PieceColor.white;
    return true;
  }

  void _applyRawMove(ChessMove move) {
    board[move.to.row][move.to.col] = board[move.from.row][move.from.col];
    board[move.from.row][move.from.col] = null;
  }

  void _undoRawMove(ChessMove move) {
    board[move.from.row][move.from.col] = board[move.to.row][move.to.col];
    board[move.to.row][move.to.col] = move.capturedPiece;
  }

  bool _isKingInCheck(PieceColor kingColor) {
    BoardPosition? kingPos;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.type == PieceType.king && p.color == kingColor) {
          kingPos = BoardPosition(r, c);
          break;
        }
      }
      if (kingPos != null) break;
    }

    if (kingPos == null) return true; // King missing

    final opponentColor = kingColor == PieceColor.white ? PieceColor.black : PieceColor.white;

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.color == opponentColor) {
          final moves = _generatePseudoMoves(BoardPosition(r, c), p);
          if (moves.any((m) => m.to == kingPos)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  List<ChessMove> _generatePseudoMoves(BoardPosition pos, ChessPiece piece) {
    final moves = <ChessMove>[];
    final r = pos.row;
    final c = pos.col;

    switch (piece.type) {
      case PieceType.pawn:
        final dir = piece.color == PieceColor.white ? -1 : 1;
        final startRow = piece.color == PieceColor.white ? 6 : 1;

        // 1 step forward
        final oneStep = BoardPosition(r + dir, c);
        if (oneStep.isValid && board[oneStep.row][oneStep.col] == null) {
          moves.add(ChessMove(from: pos, to: oneStep));

          // 2 steps forward from start
          final twoStep = BoardPosition(r + 2 * dir, c);
          if (r == startRow && board[twoStep.row][twoStep.col] == null) {
            moves.add(ChessMove(from: pos, to: twoStep));
          }
        }

        // Diagonal captures
        for (final dc in [-1, 1]) {
          final capPos = BoardPosition(r + dir, c + dc);
          if (capPos.isValid) {
            final target = board[capPos.row][capPos.col];
            if (target != null && target.color != piece.color) {
              moves.add(ChessMove(from: pos, to: capPos, capturedPiece: target));
            }
          }
        }
        break;

      case PieceType.knight:
        const deltas = [
          [-2, -1], [-2, 1], [-1, -2], [-1, 2],
          [1, -2], [1, 2], [2, -1], [2, 1]
        ];
        for (final d in deltas) {
          final next = BoardPosition(r + d[0], c + d[1]);
          if (next.isValid) {
            final target = board[next.row][next.col];
            if (target == null || target.color != piece.color) {
              moves.add(ChessMove(from: pos, to: next, capturedPiece: target));
            }
          }
        }
        break;

      case PieceType.bishop:
        _addRayMoves(pos, piece, [[-1, -1], [-1, 1], [1, -1], [1, 1]], moves);
        break;

      case PieceType.rook:
        _addRayMoves(pos, piece, [[-1, 0], [1, 0], [0, -1], [0, 1]], moves);
        break;

      case PieceType.queen:
        _addRayMoves(pos, piece, [
          [-1, -1], [-1, 1], [1, -1], [1, 1],
          [-1, 0], [1, 0], [0, -1], [0, 1]
        ], moves);
        break;

      case PieceType.king:
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final next = BoardPosition(r + dr, c + dc);
            if (next.isValid) {
              final target = board[next.row][next.col];
              if (target == null || target.color != piece.color) {
                moves.add(ChessMove(from: pos, to: next, capturedPiece: target));
              }
            }
          }
        }
        break;
    }

    return moves;
  }

  void _addRayMoves(BoardPosition pos, ChessPiece piece, List<List<int>> directions, List<ChessMove> outMoves) {
    for (final dir in directions) {
      int currR = pos.row + dir[0];
      int currC = pos.col + dir[1];
      while (currR >= 0 && currR < 8 && currC >= 0 && currC < 8) {
        final target = board[currR][currC];
        final nextPos = BoardPosition(currR, currC);
        if (target == null) {
          outMoves.add(ChessMove(from: pos, to: nextPos));
        } else {
          if (target.color != piece.color) {
            outMoves.add(ChessMove(from: pos, to: nextPos, capturedPiece: target));
          }
          break; // Hit a piece, stop ray
        }
        currR += dir[0];
        currC += dir[1];
      }
    }
  }

  // --- MINIMAX AI EVALUATION ---
  ChessMove? findBestMoveForAI(PieceColor aiColor, {int depth = 2}) {
    final moves = getAllLegalMoves(aiColor);
    if (moves.isEmpty) return null;

    moves.shuffle(Random()); // Non-deterministic equal moves
    ChessMove? bestMove;
    int bestVal = -999999;

    for (final move in moves) {
      _applyRawMove(move);
      final score = -_minimax(depth - 1, -1000000, 1000000, aiColor == PieceColor.white ? PieceColor.black : PieceColor.white);
      _undoRawMove(move);

      if (score > bestVal) {
        bestVal = score;
        bestMove = move;
      }
    }

    return bestMove;
  }

  int _minimax(int depth, int alpha, int beta, PieceColor turn) {
    if (depth <= 0) {
      return _evaluateBoard(turn);
    }

    final moves = getAllLegalMoves(turn);
    if (moves.isEmpty) {
      if (_isKingInCheck(turn)) {
        return -50000; // Checkmate loss
      }
      return 0; // Stalemate
    }

    int maxScore = -999999;
    for (final move in moves) {
      _applyRawMove(move);
      final score = -_minimax(depth - 1, -beta, -alpha, turn == PieceColor.white ? PieceColor.black : PieceColor.white);
      _undoRawMove(move);

      if (score > maxScore) {
        maxScore = score;
      }
      if (maxScore > alpha) {
        alpha = maxScore;
      }
      if (alpha >= beta) {
        break; // Alpha-beta cutoff
      }
    }
    return maxScore;
  }

  int _evaluateBoard(PieceColor perspective) {
    int score = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null) {
          int val = p.baseValue;
          // Center bonus
          if ((r == 3 || r == 4) && (c == 3 || c == 4)) {
            val += 20;
          }
          if (p.color == perspective) {
            score += val;
          } else {
            score -= val;
          }
        }
      }
    }
    return score;
  }
}
