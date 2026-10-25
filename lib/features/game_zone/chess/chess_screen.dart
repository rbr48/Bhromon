import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chess_engine.dart';

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  final ChessEngine _engine = ChessEngine();
  BoardPosition? _selectedPosition;
  List<ChessMove> _currentLegalMoves = [];
  bool _isAiThinking = false;
  int _aiDepth = 2; // Default Medium
  String _statusText = 'Your move (White)';

  @override
  void initState() {
    super.initState();
  }

  void _onSquareTapped(int row, int col) {
    if (_isAiThinking) return;
    if (_engine.currentTurn != PieceColor.white) return;

    final tappedPos = BoardPosition(row, col);

    // If a square was already selected
    if (_selectedPosition != null) {
      final matchingMoves = _currentLegalMoves.where((m) => m.to == tappedPos).toList();

      if (matchingMoves.isNotEmpty) {
        final move = matchingMoves.first;

        // Check if pawn promotion
        final movingPiece = _engine.pieceAt(_selectedPosition!.row, _selectedPosition!.col);
        if (movingPiece != null && movingPiece.type == PieceType.pawn && tappedPos.row == 0) {
          _promptPromotionChoice(move);
          return;
        }

        // Execute regular move
        _executeMove(move);
        setState(() {
          _selectedPosition = null;
          _currentLegalMoves = [];
        });
        return;
      }
    }

    // Select piece at tapped position
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

  void _promptPromotionChoice(ChessMove baseMove) {
    showDialog<PieceType>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2429),
        title: const Text('Promote Pawn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPromotionOption(ctx, PieceType.queen, '♕ Queen'),
            _buildPromotionOption(ctx, PieceType.rook, '♖ Rook'),
            _buildPromotionOption(ctx, PieceType.bishop, '♗ Bishop'),
            _buildPromotionOption(ctx, PieceType.knight, '♘ Knight'),
          ],
        ),
      ),
    ).then((chosen) {
      final promoType = chosen ?? PieceType.queen;
      final promoMove = ChessMove(
        from: baseMove.from,
        to: baseMove.to,
        capturedPiece: baseMove.capturedPiece,
        promotion: promoType,
      );
      _executeMove(promoMove);
      setState(() {
        _selectedPosition = null;
        _currentLegalMoves = [];
      });
    });
  }

  Widget _buildPromotionOption(BuildContext ctx, PieceType type, String label) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, type),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ChessPiece(type, PieceColor.white).symbol,
              style: const TextStyle(fontSize: 32, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(label.split(' ').last, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _executeMove(ChessMove move) {
    HapticFeedback.lightImpact();
    _engine.makeMove(move);

    if (_engine.isCheckmate(PieceColor.black)) {
      HapticFeedback.heavyImpact();
      setState(() {
        _statusText = 'Checkmate! You win!';
      });
      _showGameOverDialog('Checkmate! 🏆', 'Congratulations, you defeated the AI!');
      return;
    } else if (_engine.isStalemate(PieceColor.black)) {
      setState(() {
        _statusText = 'Stalemate! Game is a draw.';
      });
      _showGameOverDialog('Stalemate 🤝', 'Draw game - no legal moves remain.');
      return;
    }

    setState(() {
      _statusText = _engine.isCheck(PieceColor.black)
          ? 'DeepTravel AI is in CHECK! AI thinking...'
          : 'DeepTravel AI is thinking...';
    });

    _triggerAiMove();
  }

  void _triggerAiMove() {
    setState(() {
      _isAiThinking = true;
    });

    Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;

      final aiMove = _engine.findBestMoveForAI(PieceColor.black, depth: _aiDepth);

      setState(() {
        _isAiThinking = false;
      });

      if (aiMove != null) {
        HapticFeedback.lightImpact();
        _engine.makeMove(aiMove);

        if (_engine.isCheckmate(PieceColor.white)) {
          HapticFeedback.heavyImpact();
          setState(() {
            _statusText = 'Checkmate! DeepTravel AI wins.';
          });
          _showGameOverDialog('Checkmate!', 'AI won this round. Better luck next time!');
        } else if (_engine.isStalemate(PieceColor.white)) {
          setState(() {
            _statusText = 'Stalemate! Game is a draw.';
          });
          _showGameOverDialog('Stalemate', 'Draw game.');
        } else {
          setState(() {
            _statusText = _engine.isCheck(PieceColor.white)
                ? '⚠️ CHECK! Your King is under attack!'
                : 'Your move (White)';
          });
        }
      }
    });
  }

  void _undoMove() {
    if (_isAiThinking || _engine.moveHistory.length < 2) return;
    HapticFeedback.selectionClick();

    setState(() {
      _engine.undoMove(); // Undo AI move
      _engine.undoMove(); // Undo Player move
      _selectedPosition = null;
      _currentLegalMoves = [];
      _statusText = 'Move taken back. Your move (White)';
    });
  }

  void _resetGame() {
    setState(() {
      _engine.reset();
      _selectedPosition = null;
      _currentLegalMoves = [];
      _isAiThinking = false;
      _statusText = 'New game started. Your move (White)';
    });
  }

  void _showGameOverDialog(String title, String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2429),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87),
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = (screenWidth - 36).clamp(280.0, 440.0);
    final squareSize = boardSize / 8;
    final isWhiteInCheck = _engine.isCheck(PieceColor.white);
    final isBlackInCheck = _engine.isCheck(PieceColor.black);

    return Scaffold(
      backgroundColor: const Color(0xFF1E2429),
      appBar: AppBar(
        title: const Text('Travel Chess AI', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14181B),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Takeback Move',
            onPressed: (_engine.moveHistory.length >= 2 && !_isAiThinking) ? _undoMove : null,
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            tooltip: 'Difficulty',
            onSelected: (depth) {
              setState(() {
                _aiDepth = depth;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    depth == 1 ? 'AI: Casual (Fast)' : (depth == 2 ? 'AI: Medium' : 'AI: Hard (Deep Think)'),
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 1, child: Text('Easy / Casual')),
              const PopupMenuItem(value: 2, child: Text('Medium (Recommended)')),
              const PopupMenuItem(value: 3, child: Text('Hard (Master)')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Board',
            onPressed: _resetGame,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Black (AI) Player Banner
            _buildPlayerBanner(
              name: 'DeepTravel AI (Black)',
              isAi: true,
              isTurn: _engine.currentTurn == PieceColor.black,
              inCheck: isBlackInCheck,
              capturedPieces: _engine.capturedByBlack,
            ),

            // Status message
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: isWhiteInCheck ? Colors.red.shade900 : const Color(0xFF262D34),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isAiThinking) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: isWhiteInCheck ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isWhiteInCheck ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // 8x8 Chess Board with Rank/File Borders
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B1D14),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Board
                    SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: Stack(
                        children: [
                          Column(
                            children: List.generate(8, (row) {
                              return Row(
                                children: List.generate(8, (col) {
                                  return _buildSquare(row, col, squareSize);
                                }),
                              );
                            }),
                          ),
                          // Coordinates along left rank (1-8)
                          ...List.generate(8, (r) {
                            return Positioned(
                              top: r * squareSize + 2,
                              left: 2,
                              child: Text(
                                '${8 - r}',
                                style: TextStyle(
                                  color: r % 2 == 0 ? const Color(0xFF769656) : const Color(0xFFEEEED2),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }),
                          // Coordinates along bottom file (a-h)
                          ...List.generate(8, (c) {
                            const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
                            return Positioned(
                              bottom: 2,
                              left: c * squareSize + squareSize - 9,
                              child: Text(
                                files[c],
                                style: TextStyle(
                                  color: (7 + c) % 2 == 0 ? const Color(0xFF769656) : const Color(0xFFEEEED2),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // White (User) Player Banner
            _buildPlayerBanner(
              name: 'You (White)',
              isAi: false,
              isTurn: _engine.currentTurn == PieceColor.white,
              inCheck: isWhiteInCheck,
              capturedPieces: _engine.capturedByWhite,
            ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isTurn ? const Color(0xFF2D3843) : const Color(0xFF181D22),
      child: Row(
        children: [
          Icon(
            isAi ? Icons.psychology : Icons.person,
            color: isTurn ? Colors.amber : Colors.white60,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: isTurn ? Colors.white : Colors.white70,
              fontWeight: isTurn ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
          if (inCheck) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Text('CHECK', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
          const Spacer(),
          // Captured pieces
          Row(
            children: capturedPieces.map((p) {
              return Text(
                p.symbol,
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSquare(int row, int col, double size) {
    final isLight = (row + col) % 2 == 0;
    Color squareColor = isLight ? const Color(0xFFEEEED2) : const Color(0xFF769656);

    // Highlight last move from & to
    final last = _engine.lastMove;
    final isLastMove = last != null &&
        ((last.from.row == row && last.from.col == col) || (last.to.row == row && last.to.col == col));
    if (isLastMove) {
      squareColor = isLight ? const Color(0xFFF7EC7D) : const Color(0xFFBACA44);
    }

    final isSelected = _selectedPosition != null &&
        _selectedPosition!.row == row &&
        _selectedPosition!.col == col;

    if (isSelected) {
      squareColor = const Color(0xFFBBCE44);
    }

    final isLegalMoveDest = _currentLegalMoves.any((m) => m.to.row == row && m.to.col == col);
    final piece = _engine.pieceAt(row, col);

    // Red highlight if King is in check
    final isKingInCheckSquare = piece != null &&
        piece.type == PieceType.king &&
        _engine.isCheck(piece.color);

    return GestureDetector(
      onTap: () => _onSquareTapped(row, col),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: squareColor,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Check indicator on King
            if (isKingInCheckSquare)
              Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.45),
                ),
              ),

            // Legal move dot or capture ring
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

            // Chess piece
            if (piece != null)
              Text(
                piece.symbol,
                style: TextStyle(
                  fontSize: size * 0.72,
                  height: 1.0,
                  color: piece.color == PieceColor.white ? Colors.white : Colors.black87,
                  shadows: piece.color == PieceColor.white
                      ? const [Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(1, 1))]
                      : const [Shadow(blurRadius: 2, color: Colors.white30, offset: Offset(-1, -1))],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
