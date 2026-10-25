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
  final bool isCastling;
  final bool isEnPassant;
  final BoardPosition? enPassantCapturedPos;

  const ChessMove({
    required this.from,
    required this.to,
    this.capturedPiece,
    this.promotion,
    this.isCastling = false,
    this.isEnPassant = false,
    this.enPassantCapturedPos,
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

  // Castling rights tracking
  bool whiteKingMoved = false;
  bool whiteRook0Moved = false;
  bool whiteRook7Moved = false;
  bool blackKingMoved = false;
  bool blackRook0Moved = false;
  bool blackRook7Moved = false;

  // En Passant target square (row, col)
  BoardPosition? enPassantTarget;

  ChessEngine() {
    reset();
  }

  void reset() {
    board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    moveHistory.clear();
    capturedByWhite.clear();
    capturedByBlack.clear();
    currentTurn = PieceColor.white;

    whiteKingMoved = false;
    whiteRook0Moved = false;
    whiteRook7Moved = false;
    blackKingMoved = false;
    blackRook0Moved = false;
    blackRook7Moved = false;
    enPassantTarget = null;

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

  ChessMove? get lastMove => moveHistory.isNotEmpty ? moveHistory.last : null;

  ChessPiece? pieceAt(int row, int col) {
    if (row < 0 || row >= 8 || col < 0 || col >= 8) return null;
    return board[row][col];
  }

  BoardPosition? getKingPosition(PieceColor kingColor) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.type == PieceType.king && p.color == kingColor) {
          return BoardPosition(r, c);
        }
      }
    }
    return null;
  }

  bool isCheck(PieceColor color) => _isKingInCheck(color);

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

    // Handle captures
    final target = move.isEnPassant && move.enPassantCapturedPos != null
        ? board[move.enPassantCapturedPos!.row][move.enPassantCapturedPos!.col]
        : board[move.to.row][move.to.col];

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
        finalPiece = ChessPiece(move.promotion ?? PieceType.queen, piece.color);
      }
    }

    // Castling rook movement
    if (move.isCastling) {
      final r = move.from.row;
      if (move.to.col == 6) {
        // Kingside: Rook moves from 7 to 5
        board[r][5] = board[r][7];
        board[r][7] = null;
      } else if (move.to.col == 2) {
        // Queenside: Rook moves from 0 to 3
        board[r][3] = board[r][0];
        board[r][0] = null;
      }
    }

    // En Passant capture cleanup
    if (move.isEnPassant && move.enPassantCapturedPos != null) {
      board[move.enPassantCapturedPos!.row][move.enPassantCapturedPos!.col] = null;
    }

    board[move.to.row][move.to.col] = finalPiece;
    board[move.from.row][move.from.col] = null;

    // Update castling rights
    if (piece.type == PieceType.king) {
      if (piece.color == PieceColor.white) whiteKingMoved = true;
      if (piece.color == PieceColor.black) blackKingMoved = true;
    } else if (piece.type == PieceType.rook) {
      if (piece.color == PieceColor.white) {
        if (move.from.col == 0) whiteRook0Moved = true;
        if (move.from.col == 7) whiteRook7Moved = true;
      } else {
        if (move.from.col == 0) blackRook0Moved = true;
        if (move.from.col == 7) blackRook7Moved = true;
      }
    }

    // Update En Passant target
    if (piece.type == PieceType.pawn && (move.from.row - move.to.row).abs() == 2) {
      enPassantTarget = BoardPosition((move.from.row + move.to.row) ~/ 2, move.from.col);
    } else {
      enPassantTarget = null;
    }

    moveHistory.add(move);
    currentTurn = currentTurn == PieceColor.white ? PieceColor.black : PieceColor.white;
    return true;
  }

  void undoMove() {
    if (moveHistory.isEmpty) return;
    final move = moveHistory.removeLast();

    final prevTurn = currentTurn == PieceColor.white ? PieceColor.black : PieceColor.white;
    final piece = board[move.to.row][move.to.col];

    // Revert piece
    ChessPiece restoredPiece = piece ?? const ChessPiece(PieceType.pawn, PieceColor.white);
    if (move.promotion != null) {
      restoredPiece = ChessPiece(PieceType.pawn, prevTurn);
    }

    board[move.from.row][move.from.col] = restoredPiece;
    board[move.to.row][move.to.col] = move.isEnPassant ? null : move.capturedPiece;

    if (move.isCastling) {
      final r = move.from.row;
      if (move.to.col == 6) {
        board[r][7] = board[r][5];
        board[r][5] = null;
      } else if (move.to.col == 2) {
        board[r][0] = board[r][3];
        board[r][3] = null;
      }
    }

    if (move.isEnPassant && move.enPassantCapturedPos != null) {
      board[move.enPassantCapturedPos!.row][move.enPassantCapturedPos!.col] = move.capturedPiece;
    }

    // Remove from captured lists
    if (move.capturedPiece != null) {
      if (prevTurn == PieceColor.white) {
        capturedByWhite.remove(move.capturedPiece);
      } else {
        capturedByBlack.remove(move.capturedPiece);
      }
    }

    currentTurn = prevTurn;
  }

  void _applyRawMove(ChessMove move) {
    board[move.to.row][move.to.col] = board[move.from.row][move.from.col];
    board[move.from.row][move.from.col] = null;

    if (move.isCastling) {
      final r = move.from.row;
      if (move.to.col == 6) {
        board[r][5] = board[r][7];
        board[r][7] = null;
      } else if (move.to.col == 2) {
        board[r][3] = board[r][0];
        board[r][0] = null;
      }
    }
  }

  void _undoRawMove(ChessMove move) {
    board[move.from.row][move.from.col] = board[move.to.row][move.to.col];
    board[move.to.row][move.to.col] = move.capturedPiece;

    if (move.isCastling) {
      final r = move.from.row;
      if (move.to.col == 6) {
        board[r][7] = board[r][5];
        board[r][5] = null;
      } else if (move.to.col == 2) {
        board[r][0] = board[r][3];
        board[r][3] = null;
      }
    }
  }

  bool _isKingInCheck(PieceColor kingColor) {
    final kingPos = getKingPosition(kingColor);
    if (kingPos == null) return true; // King missing

    final opponentColor = kingColor == PieceColor.white ? PieceColor.black : PieceColor.white;
    return _isSquareAttacked(kingPos, opponentColor);
  }

  bool _isSquareAttacked(BoardPosition pos, PieceColor byColor) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.color == byColor) {
          final moves = _generatePseudoMoves(BoardPosition(r, c), p, ignoreCastling: true);
          if (moves.any((m) => m.to == pos)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  List<ChessMove> _generatePseudoMoves(BoardPosition pos, ChessPiece piece, {bool ignoreCastling = false}) {
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
            } else if (enPassantTarget != null && capPos == enPassantTarget) {
              // En Passant capture
              final epPawnPos = BoardPosition(r, c + dc);
              final epPawn = board[epPawnPos.row][epPawnPos.col];
              if (epPawn != null && epPawn.color != piece.color) {
                moves.add(ChessMove(
                  from: pos,
                  to: capPos,
                  capturedPiece: epPawn,
                  isEnPassant: true,
                  enPassantCapturedPos: epPawnPos,
                ));
              }
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

        // Castling moves
        if (!ignoreCastling) {
          final isWhite = piece.color == PieceColor.white;
          final kingMoved = isWhite ? whiteKingMoved : blackKingMoved;
          final rk0Moved = isWhite ? whiteRook0Moved : blackRook0Moved;
          final rk7Moved = isWhite ? whiteRook7Moved : blackRook7Moved;
          final oppColor = isWhite ? PieceColor.black : PieceColor.white;

          if (!kingMoved && !_isSquareAttacked(pos, oppColor)) {
            // Kingside castling (col 4 -> 6)
            if (!rk7Moved &&
                board[r][5] == null &&
                board[r][6] == null &&
                !_isSquareAttacked(BoardPosition(r, 5), oppColor) &&
                !_isSquareAttacked(BoardPosition(r, 6), oppColor)) {
              moves.add(ChessMove(from: pos, to: BoardPosition(r, 6), isCastling: true));
            }

            // Queenside castling (col 4 -> 2)
            if (!rk0Moved &&
                board[r][1] == null &&
                board[r][2] == null &&
                board[r][3] == null &&
                !_isSquareAttacked(BoardPosition(r, 3), oppColor) &&
                !_isSquareAttacked(BoardPosition(r, 2), oppColor)) {
              moves.add(ChessMove(from: pos, to: BoardPosition(r, 2), isCastling: true));
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

    moves.shuffle(Random());
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
        return -50000;
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
        break;
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
