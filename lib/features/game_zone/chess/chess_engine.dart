import 'dart:math';

enum PieceType { pawn, knight, bishop, rook, queen, king }

enum PieceColor { white, black }

extension PieceColorOpponent on PieceColor {
  PieceColor get opponent => this == PieceColor.white ? PieceColor.black : PieceColor.white;
}

/// Why a game ended in a draw.
enum DrawReason { stalemate, insufficientMaterial, fiftyMoveRule, threefoldRepetition, agreement }

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

  /// Filled glyph for this piece type, forced to text presentation (U+FE0E) so
  /// the pawn never renders as a colour emoji. The board paints it in the
  /// piece's colour with a contrasting outline.
  String get solidSymbol {
    switch (type) {
      case PieceType.king:
        return '♚︎';
      case PieceType.queen:
        return '♛︎';
      case PieceType.rook:
        return '♜︎';
      case PieceType.bishop:
        return '♝︎';
      case PieceType.knight:
        return '♞︎';
      case PieceType.pawn:
        return '♟︎';
    }
  }

  /// Standard algebraic notation letter ('' for pawns).
  String get letter {
    switch (type) {
      case PieceType.king:
        return 'K';
      case PieceType.queen:
        return 'Q';
      case PieceType.rook:
        return 'R';
      case PieceType.bishop:
        return 'B';
      case PieceType.knight:
        return 'N';
      case PieceType.pawn:
        return '';
    }
  }

  String get name => '${color.name} ${type.name}';

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

  /// Square name such as "e4".
  String get name => '${'abcdefgh'[col]}${8 - row}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardPosition &&
          runtimeType == other.runtimeType &&
          row == other.row &&
          col == other.col;

  @override
  int get hashCode => row * 8 + col;

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

  ChessMove withPromotion(PieceType type) => ChessMove(
        from: from,
        to: to,
        capturedPiece: capturedPiece,
        promotion: type,
        isCastling: isCastling,
        isEnPassant: isEnPassant,
        enPassantCapturedPos: enPassantCapturedPos,
      );

  @override
  String toString() => '$from -> $to';
}

/// Everything needed to restore the position after a move.
class _UndoRecord {
  _UndoRecord({
    required this.move,
    required this.moved,
    required this.captured,
    required this.capturedAt,
    required this.castled,
    required this.whiteKingMoved,
    required this.whiteRook0Moved,
    required this.whiteRook7Moved,
    required this.blackKingMoved,
    required this.blackRook0Moved,
    required this.blackRook7Moved,
    required this.enPassantTarget,
    required this.halfmoveClock,
  });

  final ChessMove move;
  final ChessPiece moved;
  final ChessPiece? captured;
  final BoardPosition? capturedAt;
  final bool castled;
  final bool whiteKingMoved;
  final bool whiteRook0Moved;
  final bool whiteRook7Moved;
  final bool blackKingMoved;
  final bool blackRook0Moved;
  final bool blackRook7Moved;
  final BoardPosition? enPassantTarget;
  final int halfmoveClock;
}

/// Plain data copy of a position, used to run the AI search in another isolate.
class ChessAiRequest {
  ChessAiRequest(ChessEngine engine, this.aiColor, this.depth)
      : board = [for (final row in engine.board) List<ChessPiece?>.of(row)],
        currentTurn = engine.currentTurn,
        castling = [
          engine.whiteKingMoved,
          engine.whiteRook0Moved,
          engine.whiteRook7Moved,
          engine.blackKingMoved,
          engine.blackRook0Moved,
          engine.blackRook7Moved,
        ],
        enPassantTarget = engine.enPassantTarget,
        halfmoveClock = engine.halfmoveClock;

  final List<List<ChessPiece?>> board;
  final PieceColor currentTurn;
  final List<bool> castling;
  final BoardPosition? enPassantTarget;
  final int halfmoveClock;
  final PieceColor aiColor;
  final int depth;
}

/// Top-level entry point for `compute`: searches a copy of the position.
ChessMove? chessAiWorker(ChessAiRequest request) {
  final engine = ChessEngine()
    ..board = [for (final row in request.board) List<ChessPiece?>.of(row)]
    ..currentTurn = request.currentTurn
    ..whiteKingMoved = request.castling[0]
    ..whiteRook0Moved = request.castling[1]
    ..whiteRook7Moved = request.castling[2]
    ..blackKingMoved = request.castling[3]
    ..blackRook0Moved = request.castling[4]
    ..blackRook7Moved = request.castling[5]
    ..enPassantTarget = request.enPassantTarget
    ..halfmoveClock = request.halfmoveClock;
  return engine.findBestMoveForAI(request.aiColor, depth: request.depth);
}

class ChessEngine {
  late List<List<ChessPiece?>> board;
  PieceColor currentTurn = PieceColor.white;
  final List<ChessMove> moveHistory = [];
  final List<String> moveNotation = [];
  final List<ChessPiece> capturedByWhite = [];
  final List<ChessPiece> capturedByBlack = [];

  // Castling rights tracking (true once the right is lost)
  bool whiteKingMoved = false;
  bool whiteRook0Moved = false;
  bool whiteRook7Moved = false;
  bool blackKingMoved = false;
  bool blackRook0Moved = false;
  bool blackRook7Moved = false;

  // En Passant target square (row, col)
  BoardPosition? enPassantTarget;

  /// Plies since the last capture or pawn move (for the 50-move rule).
  int halfmoveClock = 0;

  final List<_UndoRecord> _history = [];
  final List<String> _positionKeys = [];
  final Random _random;

  ChessEngine({Random? random}) : _random = random ?? Random() {
    reset();
  }

  void reset() {
    board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    moveHistory.clear();
    moveNotation.clear();
    capturedByWhite.clear();
    capturedByBlack.clear();
    _history.clear();
    _positionKeys.clear();
    currentTurn = PieceColor.white;

    whiteKingMoved = false;
    whiteRook0Moved = false;
    whiteRook7Moved = false;
    blackKingMoved = false;
    blackRook0Moved = false;
    blackRook7Moved = false;
    enPassantTarget = null;
    halfmoveClock = 0;

    const backRank = [
      PieceType.rook,
      PieceType.knight,
      PieceType.bishop,
      PieceType.queen,
      PieceType.king,
      PieceType.bishop,
      PieceType.knight,
      PieceType.rook,
    ];
    for (int c = 0; c < 8; c++) {
      board[0][c] = ChessPiece(backRank[c], PieceColor.black);
      board[1][c] = const ChessPiece(PieceType.pawn, PieceColor.black);
      board[6][c] = const ChessPiece(PieceType.pawn, PieceColor.white);
      board[7][c] = ChessPiece(backRank[c], PieceColor.white);
    }
    _positionKeys.add(_positionKey());
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
    return _legalMovesFrom(pos, piece);
  }

  List<ChessMove> getAllLegalMoves(PieceColor color) {
    final moves = <ChessMove>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece != null && piece.color == color) {
          moves.addAll(_legalMovesFrom(BoardPosition(r, c), piece));
        }
      }
    }
    return moves;
  }

  List<ChessMove> _legalMovesFrom(BoardPosition pos, ChessPiece piece) {
    final legal = <ChessMove>[];
    for (final move in _generatePseudoMoves(pos, piece)) {
      final record = _doMove(move);
      final leavesKingSafe = !_isKingInCheck(piece.color);
      _undoRecord(record);
      if (leavesKingSafe) legal.add(move);
    }
    return legal;
  }

  bool isCheckmate(PieceColor color) {
    return _isKingInCheck(color) && getAllLegalMoves(color).isEmpty;
  }

  bool isStalemate(PieceColor color) {
    return !_isKingInCheck(color) && getAllLegalMoves(color).isEmpty;
  }

  /// Neither side has enough material to deliver mate (K v K, K+minor v K,
  /// or only bishops that all stand on the same square colour).
  bool get isInsufficientMaterial {
    final others = <(ChessPiece, int, int)>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.type != PieceType.king) others.add((p, r, c));
      }
    }
    if (others.isEmpty) return true;
    if (others.length == 1) {
      final t = others.first.$1.type;
      return t == PieceType.bishop || t == PieceType.knight;
    }
    if (others.every((o) => o.$1.type == PieceType.bishop)) {
      final squareColor = (others.first.$2 + others.first.$3) % 2;
      return others.every((o) => (o.$2 + o.$3) % 2 == squareColor);
    }
    return false;
  }

  bool get isFiftyMoveRule => halfmoveClock >= 100;

  bool get isThreefoldRepetition {
    if (_positionKeys.isEmpty) return false;
    final current = _positionKeys.last;
    return _positionKeys.where((k) => k == current).length >= 3;
  }

  /// The automatic draw that applies to the side to move, if any.
  DrawReason? get drawReason {
    if (isStalemate(currentTurn)) return DrawReason.stalemate;
    if (isInsufficientMaterial) return DrawReason.insufficientMaterial;
    if (isFiftyMoveRule) return DrawReason.fiftyMoveRule;
    if (isThreefoldRepetition) return DrawReason.threefoldRepetition;
    return null;
  }

  /// Plays a legal move for the side to move. Returns false for illegal moves.
  bool makeMove(ChessMove move) {
    final piece = pieceAt(move.from.row, move.from.col);
    if (piece == null || piece.color != currentTurn) return false;

    final candidates = _legalMovesFrom(move.from, piece).where((m) => m.to == move.to).toList();
    if (candidates.isEmpty) return false;
    final wantedPromotion = move.promotion ?? PieceType.queen;
    final chosen = candidates.firstWhere(
      (m) => m.promotion == null || m.promotion == wantedPromotion,
      orElse: () => candidates.first,
    );

    final notation = _notationFor(chosen, piece);
    final record = _doMove(chosen);
    _history.add(record);

    if (record.captured != null) {
      (piece.color == PieceColor.white ? capturedByWhite : capturedByBlack).add(record.captured!);
    }

    moveHistory.add(ChessMove(
      from: chosen.from,
      to: chosen.to,
      capturedPiece: record.captured,
      promotion: chosen.promotion,
      isCastling: record.castled,
      isEnPassant: chosen.isEnPassant,
      enPassantCapturedPos: chosen.enPassantCapturedPos,
    ));

    final suffix = isCheckmate(currentTurn) ? '#' : (isCheck(currentTurn) ? '+' : '');
    moveNotation.add('$notation$suffix');
    _positionKeys.add(_positionKey());
    return true;
  }

  /// Takes back the last move, restoring castling rights, en passant and clocks.
  void undoMove() {
    if (_history.isEmpty) return;
    final record = _history.removeLast();
    _undoRecord(record);
    moveHistory.removeLast();
    if (moveNotation.isNotEmpty) moveNotation.removeLast();
    if (_positionKeys.length > 1) _positionKeys.removeLast();

    if (record.captured != null) {
      final list = record.moved.color == PieceColor.white ? capturedByWhite : capturedByBlack;
      final idx = list.lastIndexOf(record.captured!);
      if (idx >= 0) list.removeAt(idx);
    }
  }

  _UndoRecord _doMove(ChessMove move) {
    final moved = board[move.from.row][move.from.col]!;
    final isPawn = moved.type == PieceType.pawn;

    BoardPosition? capturedAt;
    ChessPiece? captured;
    final isEnPassant = isPawn &&
        (move.isEnPassant ||
            (move.from.col != move.to.col &&
                board[move.to.row][move.to.col] == null &&
                enPassantTarget == move.to));
    if (isEnPassant) {
      capturedAt = move.enPassantCapturedPos ?? BoardPosition(move.from.row, move.to.col);
      captured = board[capturedAt.row][capturedAt.col];
      board[capturedAt.row][capturedAt.col] = null;
    } else if (board[move.to.row][move.to.col] != null) {
      capturedAt = move.to;
      captured = board[move.to.row][move.to.col];
    }

    final castled = moved.type == PieceType.king && (move.to.col - move.from.col).abs() == 2;

    final record = _UndoRecord(
      move: move,
      moved: moved,
      captured: captured,
      capturedAt: capturedAt,
      castled: castled,
      whiteKingMoved: whiteKingMoved,
      whiteRook0Moved: whiteRook0Moved,
      whiteRook7Moved: whiteRook7Moved,
      blackKingMoved: blackKingMoved,
      blackRook0Moved: blackRook0Moved,
      blackRook7Moved: blackRook7Moved,
      enPassantTarget: enPassantTarget,
      halfmoveClock: halfmoveClock,
    );

    board[move.from.row][move.from.col] = null;
    var placed = moved;
    if (isPawn && (move.to.row == 0 || move.to.row == 7)) {
      placed = ChessPiece(move.promotion ?? PieceType.queen, moved.color);
    }
    board[move.to.row][move.to.col] = placed;

    if (castled) {
      final r = move.from.row;
      if (move.to.col == 6) {
        board[r][5] = board[r][7];
        board[r][7] = null;
      } else {
        board[r][3] = board[r][0];
        board[r][0] = null;
      }
    }

    if (moved.type == PieceType.king) {
      if (moved.color == PieceColor.white) {
        whiteKingMoved = true;
      } else {
        blackKingMoved = true;
      }
    }
    _revokeCornerRight(move.from);
    if (capturedAt != null) _revokeCornerRight(capturedAt);

    enPassantTarget = (isPawn && (move.from.row - move.to.row).abs() == 2)
        ? BoardPosition((move.from.row + move.to.row) ~/ 2, move.from.col)
        : null;
    halfmoveClock = (isPawn || captured != null) ? 0 : halfmoveClock + 1;
    currentTurn = moved.color.opponent;
    return record;
  }

  void _undoRecord(_UndoRecord record) {
    final move = record.move;
    board[move.from.row][move.from.col] = record.moved;
    board[move.to.row][move.to.col] = null;

    if (record.castled) {
      final r = move.from.row;
      if (move.to.col == 6) {
        board[r][7] = board[r][5];
        board[r][5] = null;
      } else {
        board[r][0] = board[r][3];
        board[r][3] = null;
      }
    }

    if (record.capturedAt != null) {
      board[record.capturedAt!.row][record.capturedAt!.col] = record.captured;
    }

    whiteKingMoved = record.whiteKingMoved;
    whiteRook0Moved = record.whiteRook0Moved;
    whiteRook7Moved = record.whiteRook7Moved;
    blackKingMoved = record.blackKingMoved;
    blackRook0Moved = record.blackRook0Moved;
    blackRook7Moved = record.blackRook7Moved;
    enPassantTarget = record.enPassantTarget;
    halfmoveClock = record.halfmoveClock;
    currentTurn = record.moved.color;
  }

  /// A piece leaving or being captured on a rook's home corner ends that castling right.
  void _revokeCornerRight(BoardPosition p) {
    if (p.row == 7 && p.col == 0) whiteRook0Moved = true;
    if (p.row == 7 && p.col == 7) whiteRook7Moved = true;
    if (p.row == 0 && p.col == 0) blackRook0Moved = true;
    if (p.row == 0 && p.col == 7) blackRook7Moved = true;
  }

  bool _isKingInCheck(PieceColor kingColor) {
    final kingPos = getKingPosition(kingColor);
    if (kingPos == null) return true; // King missing
    return _isSquareAttacked(kingPos, kingColor.opponent);
  }

  static const List<List<int>> _knightDeltas = [
    [-2, -1], [-2, 1], [-1, -2], [-1, 2],
    [1, -2], [1, 2], [2, -1], [2, 1],
  ];
  static const List<List<int>> _diagonals = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
  static const List<List<int>> _orthogonals = [[-1, 0], [1, 0], [0, -1], [0, 1]];

  /// True when [byColor] attacks [pos], whether or not the square is occupied.
  bool _isSquareAttacked(BoardPosition pos, PieceColor byColor) {
    final r = pos.row;
    final c = pos.col;

    // Pawns attack diagonally forward only.
    final pawnRow = byColor == PieceColor.white ? r + 1 : r - 1;
    for (final dc in const [-1, 1]) {
      final p = pieceAt(pawnRow, c + dc);
      if (p != null && p.color == byColor && p.type == PieceType.pawn) return true;
    }

    for (final d in _knightDeltas) {
      final p = pieceAt(r + d[0], c + d[1]);
      if (p != null && p.color == byColor && p.type == PieceType.knight) return true;
    }

    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final p = pieceAt(r + dr, c + dc);
        if (p != null && p.color == byColor && p.type == PieceType.king) return true;
      }
    }

    bool rayHits(List<List<int>> dirs, PieceType slider) {
      for (final d in dirs) {
        int rr = r + d[0];
        int cc = c + d[1];
        while (rr >= 0 && rr < 8 && cc >= 0 && cc < 8) {
          final p = board[rr][cc];
          if (p != null) {
            if (p.color == byColor && (p.type == slider || p.type == PieceType.queen)) return true;
            break;
          }
          rr += d[0];
          cc += d[1];
        }
      }
      return false;
    }

    return rayHits(_diagonals, PieceType.bishop) || rayHits(_orthogonals, PieceType.rook);
  }

  List<ChessMove> _generatePseudoMoves(BoardPosition pos, ChessPiece piece) {
    final moves = <ChessMove>[];
    final r = pos.row;
    final c = pos.col;

    switch (piece.type) {
      case PieceType.pawn:
        final dir = piece.color == PieceColor.white ? -1 : 1;
        final startRow = piece.color == PieceColor.white ? 6 : 1;
        final lastRow = piece.color == PieceColor.white ? 0 : 7;

        void addPawnMove(BoardPosition to, {ChessPiece? captured}) {
          if (to.row == lastRow) {
            for (final t in const [PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight]) {
              moves.add(ChessMove(from: pos, to: to, capturedPiece: captured, promotion: t));
            }
          } else {
            moves.add(ChessMove(from: pos, to: to, capturedPiece: captured));
          }
        }

        final oneStep = BoardPosition(r + dir, c);
        if (oneStep.isValid && board[oneStep.row][oneStep.col] == null) {
          addPawnMove(oneStep);
          final twoStep = BoardPosition(r + 2 * dir, c);
          if (r == startRow && board[twoStep.row][twoStep.col] == null) {
            moves.add(ChessMove(from: pos, to: twoStep));
          }
        }

        for (final dc in const [-1, 1]) {
          final capPos = BoardPosition(r + dir, c + dc);
          if (!capPos.isValid) continue;
          final target = board[capPos.row][capPos.col];
          if (target != null && target.color != piece.color) {
            addPawnMove(capPos, captured: target);
          } else if (target == null && enPassantTarget != null && capPos == enPassantTarget) {
            final epPawnPos = BoardPosition(r, c + dc);
            final epPawn = board[epPawnPos.row][epPawnPos.col];
            if (epPawn != null && epPawn.type == PieceType.pawn && epPawn.color != piece.color) {
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
        break;

      case PieceType.knight:
        for (final d in _knightDeltas) {
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
        _addRayMoves(pos, piece, _diagonals, moves);
        break;

      case PieceType.rook:
        _addRayMoves(pos, piece, _orthogonals, moves);
        break;

      case PieceType.queen:
        _addRayMoves(pos, piece, _diagonals, moves);
        _addRayMoves(pos, piece, _orthogonals, moves);
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
        _addCastlingMoves(pos, piece, moves);
        break;
    }

    return moves;
  }

  void _addCastlingMoves(BoardPosition pos, ChessPiece king, List<ChessMove> moves) {
    final isWhite = king.color == PieceColor.white;
    final homeRow = isWhite ? 7 : 0;
    if (pos.row != homeRow || pos.col != 4) return;
    if (isWhite ? whiteKingMoved : blackKingMoved) return;

    final opp = king.color.opponent;
    if (_isSquareAttacked(pos, opp)) return;

    bool ownRookAt(int col) {
      final p = board[homeRow][col];
      return p != null && p.type == PieceType.rook && p.color == king.color;
    }

    final kingsideLost = isWhite ? whiteRook7Moved : blackRook7Moved;
    if (!kingsideLost &&
        ownRookAt(7) &&
        board[homeRow][5] == null &&
        board[homeRow][6] == null &&
        !_isSquareAttacked(BoardPosition(homeRow, 5), opp) &&
        !_isSquareAttacked(BoardPosition(homeRow, 6), opp)) {
      moves.add(ChessMove(from: pos, to: BoardPosition(homeRow, 6), isCastling: true));
    }

    final queensideLost = isWhite ? whiteRook0Moved : blackRook0Moved;
    if (!queensideLost &&
        ownRookAt(0) &&
        board[homeRow][1] == null &&
        board[homeRow][2] == null &&
        board[homeRow][3] == null &&
        !_isSquareAttacked(BoardPosition(homeRow, 3), opp) &&
        !_isSquareAttacked(BoardPosition(homeRow, 2), opp)) {
      moves.add(ChessMove(from: pos, to: BoardPosition(homeRow, 2), isCastling: true));
    }
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

  // --- NOTATION & POSITION KEYS ---

  String _notationFor(ChessMove move, ChessPiece piece) {
    if (piece.type == PieceType.king && (move.to.col - move.from.col).abs() == 2) {
      return move.to.col == 6 ? 'O-O' : 'O-O-O';
    }
    final isCapture = board[move.to.row][move.to.col] != null || move.isEnPassant;
    final dest = move.to.name;
    if (piece.type == PieceType.pawn) {
      final promo = move.promotion != null ? '=${ChessPiece(move.promotion!, piece.color).letter}' : '';
      return '${isCapture ? '${'abcdefgh'[move.from.col]}x' : ''}$dest$promo';
    }

    final rivals = <BoardPosition>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final other = board[r][c];
        if (other == null || other != piece || (r == move.from.row && c == move.from.col)) continue;
        final from = BoardPosition(r, c);
        if (_legalMovesFrom(from, other).any((m) => m.to == move.to)) rivals.add(from);
      }
    }
    var disambiguation = '';
    if (rivals.isNotEmpty) {
      final file = 'abcdefgh'[move.from.col];
      final rank = '${8 - move.from.row}';
      if (rivals.every((p) => p.col != move.from.col)) {
        disambiguation = file;
      } else if (rivals.every((p) => p.row != move.from.row)) {
        disambiguation = rank;
      } else {
        disambiguation = '$file$rank';
      }
    }
    return '${piece.letter}$disambiguation${isCapture ? 'x' : ''}$dest';
  }

  String _positionKey() {
    final buffer = StringBuffer();
    for (final row in board) {
      for (final p in row) {
        if (p == null) {
          buffer.write('.');
        } else {
          final l = p.type == PieceType.pawn ? 'p' : p.letter.toLowerCase();
          buffer.write(p.color == PieceColor.white ? l.toUpperCase() : l);
        }
      }
    }
    buffer
      ..write(currentTurn == PieceColor.white ? 'w' : 'b')
      ..write(whiteKingMoved || whiteRook7Moved ? '-' : 'K')
      ..write(whiteKingMoved || whiteRook0Moved ? '-' : 'Q')
      ..write(blackKingMoved || blackRook7Moved ? '-' : 'k')
      ..write(blackKingMoved || blackRook0Moved ? '-' : 'q');
    // Only an en passant square that can actually be used changes the position.
    final ep = enPassantTarget;
    if (ep != null) {
      final capturerRow = currentTurn == PieceColor.white ? ep.row + 1 : ep.row - 1;
      final usable = [ep.col - 1, ep.col + 1].any((col) {
        final p = pieceAt(capturerRow, col);
        return p != null && p.type == PieceType.pawn && p.color == currentTurn;
      });
      if (usable) buffer.write(ep.name);
    }
    return buffer.toString();
  }

  // --- AI SEARCH (negamax + alpha-beta + quiescence) ---

  static const int _mateScore = 1000000;
  static const int _infinity = 1 << 30;

  /// Best move for [aiColor]. Depth 1 is casual (adds a little randomness),
  /// 2 is medium and 3 is hard; all depths extend captures with quiescence.
  ChessMove? findBestMoveForAI(PieceColor aiColor, {int depth = 2}) {
    final moves = getAllLegalMoves(aiColor);
    if (moves.isEmpty) return null;

    moves.shuffle(_random);
    _orderMoves(moves);

    ChessMove? bestMove;
    int bestVal = -_infinity;
    int alpha = -_infinity;
    for (final move in moves) {
      final record = _doMove(move);
      var score = -_negamax(depth - 1, -_infinity, -alpha, aiColor.opponent, 1);
      _undoRecord(record);
      if (depth <= 1) score += _random.nextInt(41) - 20;

      if (score > bestVal) {
        bestVal = score;
        bestMove = move;
      }
      if (bestVal > alpha) alpha = bestVal;
    }
    return bestMove;
  }

  int _negamax(int depth, int alpha, int beta, PieceColor turn, int ply) {
    if (depth <= 0) return _quiescence(alpha, beta, turn, 0);

    final moves = getAllLegalMoves(turn);
    if (moves.isEmpty) {
      return _isKingInCheck(turn) ? -(_mateScore - ply) : 0;
    }
    _orderMoves(moves);

    int best = -_infinity;
    for (final move in moves) {
      final record = _doMove(move);
      final score = -_negamax(depth - 1, -beta, -alpha, turn.opponent, ply + 1);
      _undoRecord(record);
      if (score > best) best = score;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  }

  int _quiescence(int alpha, int beta, PieceColor turn, int qDepth) {
    final standPat = _evaluateBoard(turn);
    if (standPat >= beta) return standPat;
    if (standPat > alpha) alpha = standPat;
    if (qDepth >= 4) return standPat;

    final captures = <ChessMove>[];
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece == null || piece.color != turn) continue;
        for (final m in _generatePseudoMoves(BoardPosition(r, c), piece)) {
          if (m.capturedPiece == null && m.promotion == null) continue;
          final record = _doMove(m);
          final ok = !_isKingInCheck(turn);
          _undoRecord(record);
          if (ok) captures.add(m);
        }
      }
    }
    _orderMoves(captures);

    for (final move in captures) {
      final record = _doMove(move);
      final score = -_quiescence(-beta, -alpha, turn.opponent, qDepth + 1);
      _undoRecord(record);
      if (score >= beta) return score;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }

  void _orderMoves(List<ChessMove> moves) {
    int scoreOf(ChessMove m) {
      var s = 0;
      final victim = m.capturedPiece;
      if (victim != null) {
        final attacker = board[m.from.row][m.from.col];
        s += victim.baseValue * 10 - (attacker?.baseValue ?? 0) ~/ 10;
      }
      if (m.promotion == PieceType.queen) s += 8000;
      return s;
    }

    moves.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
  }

  // Piece-square tables from White's point of view (row 0 = rank 8).
  static const List<List<int>> _pawnTable = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [50, 50, 50, 50, 50, 50, 50, 50],
    [10, 10, 20, 30, 30, 20, 10, 10],
    [5, 5, 10, 25, 25, 10, 5, 5],
    [0, 0, 0, 20, 20, 0, 0, 0],
    [5, -5, -10, 0, 0, -10, -5, 5],
    [5, 10, 10, -20, -20, 10, 10, 5],
    [0, 0, 0, 0, 0, 0, 0, 0],
  ];
  static const List<List<int>> _knightTable = [
    [-50, -40, -30, -30, -30, -30, -40, -50],
    [-40, -20, 0, 0, 0, 0, -20, -40],
    [-30, 0, 10, 15, 15, 10, 0, -30],
    [-30, 5, 15, 20, 20, 15, 5, -30],
    [-30, 0, 15, 20, 20, 15, 0, -30],
    [-30, 5, 10, 15, 15, 10, 5, -30],
    [-40, -20, 0, 5, 5, 0, -20, -40],
    [-50, -40, -30, -30, -30, -30, -40, -50],
  ];
  static const List<List<int>> _bishopTable = [
    [-20, -10, -10, -10, -10, -10, -10, -20],
    [-10, 0, 0, 0, 0, 0, 0, -10],
    [-10, 0, 5, 10, 10, 5, 0, -10],
    [-10, 5, 5, 10, 10, 5, 5, -10],
    [-10, 0, 10, 10, 10, 10, 0, -10],
    [-10, 10, 10, 10, 10, 10, 10, -10],
    [-10, 5, 0, 0, 0, 0, 5, -10],
    [-20, -10, -10, -10, -10, -10, -10, -20],
  ];
  static const List<List<int>> _rookTable = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [5, 10, 10, 10, 10, 10, 10, 5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [-5, 0, 0, 0, 0, 0, 0, -5],
    [0, 0, 0, 5, 5, 0, 0, 0],
  ];
  static const List<List<int>> _kingTable = [
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-30, -40, -40, -50, -50, -40, -40, -30],
    [-20, -30, -30, -40, -40, -30, -30, -20],
    [-10, -20, -20, -20, -20, -20, -20, -10],
    [20, 20, 0, 0, 0, 0, 20, 20],
    [20, 30, 10, 0, 0, 10, 30, 20],
  ];

  /// Static evaluation in centipawns from [color]'s point of view.
  int evaluateFor(PieceColor color) => _evaluateBoard(color);

  int _evaluateBoard(PieceColor perspective) {
    int score = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p == null) continue;
        final tr = p.color == PieceColor.white ? r : 7 - r;
        int val = p.baseValue;
        switch (p.type) {
          case PieceType.pawn:
            val += _pawnTable[tr][c];
            break;
          case PieceType.knight:
            val += _knightTable[tr][c];
            break;
          case PieceType.bishop:
            val += _bishopTable[tr][c];
            break;
          case PieceType.rook:
            val += _rookTable[tr][c];
            break;
          case PieceType.queen:
            val += _bishopTable[tr][c] ~/ 2;
            break;
          case PieceType.king:
            val += _kingTable[tr][c];
            break;
        }
        score += p.color == perspective ? val : -val;
      }
    }
    return score;
  }
}
