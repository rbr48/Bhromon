import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../common/game_zone_portrait_lock.dart';
import 'chess_engine.dart';

/// Keeps the game in progress while the player visits other parts of the app.
class _ChessSession {
  static ChessEngine? engine;
  static int aiDepth = 2;
  static String? gameOverTitle;
  static String? gameOverMessage;
}

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> with GameZonePortraitLock {
  late final ChessEngine _engine;
  BoardPosition? _selectedPosition;
  List<ChessMove> _currentLegalMoves = [];
  bool _isAiThinking = false;
  int _aiGeneration = 0;
  String _statusText = 'Your move (White)';
  final ScrollController _moveListController = ScrollController();

  static const _depthLabels = {
    1: 'Easy / Casual',
    2: 'Medium (Recommended)',
    4: 'Hard'
  };

  bool get _isGameOver => _ChessSession.gameOverTitle != null;

  @override
  void initState() {
    super.initState();
    _engine = _ChessSession.engine ??= ChessEngine();
    if (_isGameOver) {
      _statusText = _ChessSession.gameOverMessage ?? 'Game over';
    } else if (_engine.currentTurn == PieceColor.black) {
      // The AI was still thinking when the player left; resume its move.
      _statusText = 'DeepTravel AI is thinking...';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerAiMove();
      });
    } else {
      _statusText = _engine.isCheck(PieceColor.white)
          ? '⚠️ CHECK! Your King is under attack!'
          : 'Your move (White)';
    }
  }

  @override
  void dispose() {
    _aiGeneration++;
    _moveListController.dispose();
    super.dispose();
  }

  void _onSquareTapped(int row, int col) {
    if (_isAiThinking || _isGameOver) return;
    if (_engine.currentTurn != PieceColor.white) return;

    final tappedPos = BoardPosition(row, col);

    if (_selectedPosition != null) {
      final matchingMoves =
          _currentLegalMoves.where((m) => m.to == tappedPos).toList();
      if (matchingMoves.isNotEmpty) {
        final move = matchingMoves.first;
        if (move.promotion != null) {
          _promptPromotionChoice(move);
          return;
        }
        setState(() {
          _selectedPosition = null;
          _currentLegalMoves = [];
        });
        _executeMove(move);
        return;
      }
    }

    final piece = _engine.pieceAt(row, col);
    if (piece != null && piece.color == PieceColor.white) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedPosition = tappedPos;
        _currentLegalMoves = _engine.getLegalMovesForPosition(tappedPos);
      });
    } else {
      setState(() {
        _selectedPosition = null;
        _currentLegalMoves = [];
      });
    }
  }

  Future<void> _promptPromotionChoice(ChessMove baseMove) async {
    final chosen = await showDialog<PieceType>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2429),
        title: const Text('Promote Pawn',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            _buildPromotionOption(ctx, PieceType.queen, 'Queen'),
            _buildPromotionOption(ctx, PieceType.rook, 'Rook'),
            _buildPromotionOption(ctx, PieceType.bishop, 'Bishop'),
            _buildPromotionOption(ctx, PieceType.knight, 'Knight'),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _selectedPosition = null;
      _currentLegalMoves = [];
    });
    // Dismissing the dialog cancels the move instead of silently picking a queen.
    if (chosen == null) return;
    _executeMove(baseMove.withPromotion(chosen));
  }

  Widget _buildPromotionOption(BuildContext ctx, PieceType type, String label) {
    return Semantics(
      button: true,
      label: 'Promote to $label',
      child: InkWell(
        onTap: () => Navigator.pop(ctx, type),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PieceGlyph(piece: ChessPiece(type, PieceColor.white), size: 44),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  void _executeMove(ChessMove move) {
    if (!_engine.makeMove(move)) return;
    HapticFeedback.lightImpact();
    _scrollMoveListToEnd();

    if (_checkGameEnd()) return;

    setState(() {
      _statusText = _engine.isCheck(PieceColor.black)
          ? 'DeepTravel AI is in CHECK! AI thinking...'
          : 'DeepTravel AI is thinking...';
    });
    _triggerAiMove();
  }

  /// Ends the game if the side to move is mated or an automatic draw applies.
  bool _checkGameEnd() {
    final side = _engine.currentTurn;
    if (_engine.isCheckmate(side)) {
      HapticFeedback.heavyImpact();
      if (side == PieceColor.black) {
        _finishGame('Checkmate! 🏆', 'Congratulations, you defeated the AI!',
            'Checkmate! You win!');
      } else {
        _finishGame('Checkmate!', 'AI won this round. Better luck next time!',
            'Checkmate! DeepTravel AI wins.');
      }
      return true;
    }
    final draw = _engine.drawReason;
    if (draw != null) {
      final reason = _drawReasonText(draw);
      _finishGame('Draw 🤝', reason, 'Draw: $reason');
      return true;
    }
    return false;
  }

  String _drawReasonText(DrawReason reason) {
    switch (reason) {
      case DrawReason.stalemate:
        return 'Stalemate - the side to move has no legal moves.';
      case DrawReason.insufficientMaterial:
        return 'Neither side has enough material to checkmate.';
      case DrawReason.fiftyMoveRule:
        return '50 moves without a capture or pawn move.';
      case DrawReason.threefoldRepetition:
        return 'The same position occurred three times.';
      case DrawReason.agreement:
        return 'Draw agreed.';
    }
  }

  void _finishGame(String title, String message, String status) {
    _ChessSession.gameOverTitle = title;
    _ChessSession.gameOverMessage = status;
    setState(() {
      _isAiThinking = false;
      _statusText = status;
      _selectedPosition = null;
      _currentLegalMoves = [];
    });
    _showGameOverDialog(title, message);
  }

  Future<void> _triggerAiMove() async {
    final generation = ++_aiGeneration;
    setState(() {
      _isAiThinking = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || generation != _aiGeneration) return;

    final request =
        ChessAiRequest(_engine, PieceColor.black, _ChessSession.aiDepth);
    final aiMove = await compute(chessAiWorker, request);
    if (!mounted || generation != _aiGeneration) return;

    setState(() {
      _isAiThinking = false;
    });
    if (aiMove == null || !_engine.makeMove(aiMove)) return;

    HapticFeedback.lightImpact();
    _scrollMoveListToEnd();
    if (_checkGameEnd()) return;
    setState(() {
      _statusText = _engine.isCheck(PieceColor.white)
          ? '⚠️ CHECK! Your King is under attack!'
          : 'Your move (White)';
    });
  }

  void _undoMove() {
    if (_isAiThinking || _engine.moveHistory.isEmpty) return;
    HapticFeedback.selectionClick();

    setState(() {
      // Take back until it is White's turn again: the AI reply plus your move,
      // or just your move if the game ended right after it.
      _engine.undoMove();
      while (_engine.currentTurn == PieceColor.black &&
          _engine.moveHistory.isNotEmpty) {
        _engine.undoMove();
      }
      _ChessSession.gameOverTitle = null;
      _ChessSession.gameOverMessage = null;
      _selectedPosition = null;
      _currentLegalMoves = [];
      _statusText = 'Move taken back. Your move (White)';
    });
    if (_engine.currentTurn == PieceColor.black) _triggerAiMove();
  }

  Future<void> _confirmNewGame() async {
    if (_engine.moveHistory.isNotEmpty && !_isGameOver) {
      final ok = await confirmDiscardGame(
        context,
        title: 'Start a new game?',
        message: 'The current game will be lost.',
      );
      if (!ok || !mounted) return;
    }
    _resetGame();
  }

  void _resetGame() {
    _aiGeneration++;
    _ChessSession.gameOverTitle = null;
    _ChessSession.gameOverMessage = null;
    setState(() {
      _engine.reset();
      _selectedPosition = null;
      _currentLegalMoves = [];
      _isAiThinking = false;
      _statusText = 'New game started. Your move (White)';
    });
  }

  Future<void> _resign() async {
    if (_isGameOver || _engine.moveHistory.isEmpty) return;
    final ok = await confirmDiscardGame(
      context,
      title: 'Resign this game?',
      message: 'DeepTravel AI will be awarded the win.',
      confirmLabel: 'Resign',
    );
    if (!ok || !mounted) return;
    _aiGeneration++;
    _finishGame('You resigned', 'DeepTravel AI wins by resignation.',
        'You resigned. DeepTravel AI wins.');
  }

  void _offerDraw() {
    if (_isGameOver || _isAiThinking || _engine.moveHistory.isEmpty) return;
    // The AI accepts only when its own position is clearly worse.
    final aiAdvantage = _engine.evaluateFor(PieceColor.black);
    if (aiAdvantage <= -150) {
      _finishGame(
          'Draw 🤝', 'DeepTravel AI accepted your draw offer.', 'Draw agreed.');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('DeepTravel AI declines the draw offer.'),
            duration: Duration(seconds: 2)),
      );
    }
  }

  void _showGameOverDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2429),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Review board',
                style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: () {
              Navigator.pop(ctx);
              _resetGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  void _scrollMoveListToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_moveListController.hasClients) {
        _moveListController
            .jumpTo(_moveListController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWhiteInCheck = _engine.isCheck(PieceColor.white);
    final isBlackInCheck = _engine.isCheck(PieceColor.black);
    final canUndo = _engine.moveHistory.isNotEmpty && !_isAiThinking;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2429),
      appBar: AppBar(
        title: const Text('Travel Chess AI',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14181B),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Takeback Move',
            onPressed: canUndo ? _undoMove : null,
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            tooltip: 'Difficulty',
            onSelected: (depth) {
              setState(() {
                _ChessSession.aiDepth = depth;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('AI: ${_depthLabels[depth]}'),
                    duration: const Duration(seconds: 1)),
              );
            },
            itemBuilder: (ctx) => [
              for (final entry in _depthLabels.entries)
                CheckedPopupMenuItem(
                  value: entry.key,
                  checked: _ChessSession.aiDepth == entry.key,
                  child: Text(entry.value),
                ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Game options',
            onSelected: (value) {
              if (value == 'new') _confirmNewGame();
              if (value == 'draw') _offerDraw();
              if (value == 'resign') _resign();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'new', child: Text('New game')),
              PopupMenuItem(
                value: 'draw',
                enabled: !_isGameOver &&
                    !_isAiThinking &&
                    _engine.moveHistory.isNotEmpty,
                child: const Text('Offer draw'),
              ),
              PopupMenuItem(
                value: 'resign',
                enabled: !_isGameOver && _engine.moveHistory.isNotEmpty,
                child: const Text('Resign'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildPlayerBanner(
              name: 'DeepTravel AI (Black)',
              isAi: true,
              isTurn: !_isGameOver && _engine.currentTurn == PieceColor.black,
              inCheck: isBlackInCheck,
              capturedPieces: _engine.capturedByBlack,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: isWhiteInCheck && !_isGameOver
                  ? Colors.red.shade900
                  : const Color(0xFF262D34),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isAiThinking) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.amber),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isWhiteInCheck ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            isWhiteInCheck ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildMoveList(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boardSize =
                      min(constraints.maxWidth - 24, constraints.maxHeight - 16)
                          .clamp(200.0, 520.0);
                  return Center(child: _buildBoard(boardSize));
                },
              ),
            ),
            _buildPlayerBanner(
              name: 'You (White)',
              isAi: false,
              isTurn: !_isGameOver && _engine.currentTurn == PieceColor.white,
              inCheck: isWhiteInCheck,
              capturedPieces: _engine.capturedByWhite,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveList() {
    final notation = _engine.moveNotation;
    final entries = <String>[];
    for (int i = 0; i < notation.length; i += 2) {
      final black = i + 1 < notation.length ? ' ${notation[i + 1]}' : '';
      entries.add('${i ~/ 2 + 1}. ${notation[i]}$black');
    }
    return Container(
      height: 30,
      color: const Color(0xFF181D22),
      child: entries.isEmpty
          ? const Center(
              child: Text('Moves will appear here',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          : ListView.separated(
              controller: _moveListController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => Center(
                child: Text(
                  entries[i],
                  style: TextStyle(
                    color:
                        i == entries.length - 1 ? Colors.amber : Colors.white70,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBoard(double boardSize) {
    final squareSize = boardSize / 8;
    final labelSize = (squareSize * 0.2).clamp(9.0, 12.0);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF2B1D14),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          children: [
            Column(
              children: List.generate(8, (row) {
                return Row(
                    children: List.generate(
                        8, (col) => _buildSquare(row, col, squareSize)));
              }),
            ),
            ...List.generate(8, (r) {
              return Positioned(
                top: r * squareSize + 2,
                left: 2,
                child: IgnorePointer(
                  child: Text(
                    '${8 - r}',
                    style: TextStyle(
                      color: r % 2 == 0
                          ? const Color(0xFF769656)
                          : const Color(0xFFEEEED2),
                      fontSize: labelSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
            ...List.generate(8, (c) {
              const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
              return Positioned(
                bottom: 1,
                left: c * squareSize + squareSize - labelSize - 1,
                child: IgnorePointer(
                  child: Text(
                    files[c],
                    style: TextStyle(
                      color: (7 + c) % 2 == 0
                          ? const Color(0xFF769656)
                          : const Color(0xFFEEEED2),
                      fontSize: labelSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerBanner({
    required String name,
    required bool isAi,
    required bool isTurn,
    required bool inCheck,
    required List<ChessPiece> capturedPieces,
  }) {
    final gained =
        capturedPieces.fold<int>(0, (s, p) => s + p.baseValue) ~/ 100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isTurn ? const Color(0xFF2D3843) : const Color(0xFF181D22),
      child: Row(
        children: [
          Icon(isAi ? Icons.psychology : Icons.person,
              color: isTurn ? Colors.amber : Colors.white60, size: 20),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isTurn ? Colors.white : Colors.white70,
                fontWeight: isTurn ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          if (inCheck) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Text('CHECK',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Semantics(
              label: capturedPieces.isEmpty
                  ? 'No captures'
                  : 'Captured: ${capturedPieces.map((p) => p.type.name).join(', ')}',
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in capturedPieces)
                    _PieceGlyph(piece: p, size: 18),
                  if (gained > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text('+$gained',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSquare(int row, int col, double size) {
    final isLight = (row + col) % 2 == 0;
    Color squareColor =
        isLight ? const Color(0xFFEEEED2) : const Color(0xFF769656);

    final last = _engine.lastMove;
    final isLastMove = last != null &&
        ((last.from.row == row && last.from.col == col) ||
            (last.to.row == row && last.to.col == col));
    if (isLastMove) {
      squareColor = isLight ? const Color(0xFFF7EC7D) : const Color(0xFFBACA44);
    }

    final pos = BoardPosition(row, col);
    final isSelected = _selectedPosition == pos;
    if (isSelected) {
      squareColor = const Color(0xFFBBCE44);
    }

    final isLegalMoveDest = _currentLegalMoves.any((m) => m.to == pos);
    final piece = _engine.pieceAt(row, col);
    final isKingInCheckSquare = piece != null &&
        piece.type == PieceType.king &&
        _engine.isCheck(piece.color);

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${pos.name}, ${piece?.name ?? 'empty'}${isLegalMoveDest ? ', legal move' : ''}',
      child: GestureDetector(
        onTap: () => _onSquareTapped(row, col),
        child: Container(
          width: size,
          height: size,
          color: squareColor,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isKingInCheckSquare)
                Container(
                  width: size * 0.9,
                  height: size * 0.9,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withValues(alpha: 0.45)),
                ),
              if (isLegalMoveDest)
                Container(
                  width: piece == null ? size * 0.32 : size * 0.86,
                  height: piece == null ? size * 0.32 : size * 0.86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: piece == null
                        ? const Color(0x66000000)
                        : Colors.transparent,
                    border: piece != null
                        ? Border.all(color: const Color(0xAAFF0000), width: 3.5)
                        : null,
                  ),
                ),
              if (piece != null) _PieceGlyph(piece: piece, size: size),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a chess piece with a filled glyph and a contrasting outline so white
/// pieces stay visible on the light squares and black pieces on the dark ones.
///
/// Note: Standard Unicode pawn (U+265F) was added to Emoji 11.0, so Android's
/// font fallback can hijack it with NotoColorEmoji (ignoring Paint color and
/// stroke). To ensure pawns are always rendered with pixel-perfect vector
/// clarity and correct side coloring across all devices, pawns are painted
/// via [_ChessPawnPainter].
class _PieceGlyph extends StatelessWidget {
  const _PieceGlyph({required this.piece, required this.size});

  final ChessPiece piece;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isWhite = piece.color == PieceColor.white;
    if (piece.type == PieceType.pawn) {
      return ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            size: Size(size, size),
            painter: _ChessPawnPainter(
              isWhite: isWhite,
              size: size,
            ),
          ),
        ),
      );
    }

    final fontSize = size * 0.74;
    return ExcludeSemantics(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            piece.solidSymbol,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = max(1.2, size * 0.055)
                ..strokeJoin = StrokeJoin.round
                ..color =
                    isWhite ? const Color(0xFF1B1B1B) : const Color(0xFFF2F2F2),
            ),
          ),
          Text(
            piece.solidSymbol,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              color: isWhite ? Colors.white : const Color(0xFF1B1B1B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChessPawnPainter extends CustomPainter {
  final bool isWhite;
  final double size;

  const _ChessPawnPainter({required this.isWhite, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final s = canvasSize.width;
    final strokeWidth = max(1.2, s * 0.055);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isWhite ? Colors.white : const Color(0xFF1B1B1B);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = isWhite ? const Color(0xFF1B1B1B) : const Color(0xFFF2F2F2);

    final cx = s * 0.5;

    // Body & Base: continuous symmetrical Staunton silhouette
    final body = Path();
    body.moveTo(cx - s * 0.22, s * 0.81);
    body.lineTo(cx + s * 0.22, s * 0.81);
    body.quadraticBezierTo(cx + s * 0.22, s * 0.75, cx + s * 0.17, s * 0.74);
    body.lineTo(cx + s * 0.15, s * 0.70);
    body.quadraticBezierTo(cx + s * 0.08, s * 0.57, cx + s * 0.07, s * 0.49);
    body.lineTo(cx + s * 0.12, s * 0.47);
    body.quadraticBezierTo(cx + s * 0.12, s * 0.44, cx + s * 0.08, s * 0.44);
    body.lineTo(cx - s * 0.08, s * 0.44);
    body.quadraticBezierTo(cx - s * 0.12, s * 0.44, cx - s * 0.12, s * 0.47);
    body.lineTo(cx - s * 0.07, s * 0.49);
    body.quadraticBezierTo(cx - s * 0.08, s * 0.57, cx - s * 0.15, s * 0.70);
    body.lineTo(cx - s * 0.17, s * 0.74);
    body.quadraticBezierTo(cx - s * 0.22, s * 0.75, cx - s * 0.22, s * 0.81);
    body.close();

    // Head: spherical round top
    final headCenter = Offset(cx, s * 0.33);
    final headRadius = s * 0.12;

    canvas.drawPath(body, fillPaint);
    canvas.drawPath(body, strokePaint);

    canvas.drawCircle(headCenter, headRadius, fillPaint);
    canvas.drawCircle(headCenter, headRadius, strokePaint);

    // Collar detail ring
    final collar = Path()
      ..moveTo(cx - s * 0.11, s * 0.46)
      ..lineTo(cx + s * 0.11, s * 0.46);
    canvas.drawPath(collar, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _ChessPawnPainter oldDelegate) =>
      oldDelegate.isWhite != isWhite || oldDelegate.size != size;
}
