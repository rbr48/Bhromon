import 'dart:async';
import 'package:flutter/material.dart';
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
      final matchingMove = _currentLegalMoves.firstWhere(
        (m) => m.to == tappedPos,
        orElse: () => const ChessMove(from: BoardPosition(-1, -1), to: BoardPosition(-1, -1)),
      );

      if (matchingMove.from.isValid) {
        // Execute move
        _executeMove(matchingMove);
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

  void _executeMove(ChessMove move) {
    _engine.makeMove(move);

    if (_engine.isCheckmate(PieceColor.black)) {
      setState(() {
        _statusText = 'Checkmate! You win!';
      });
      _showGameOverDialog('Checkmate!', 'Congratulations, you defeated the AI!');
      return;
    } else if (_engine.isStalemate(PieceColor.black)) {
      setState(() {
        _statusText = 'Stalemate! Game is a draw.';
      });
      _showGameOverDialog('Stalemate', 'Draw game - no legal moves remain.');
      return;
    }

    setState(() {
      _statusText = 'DeepTravel AI is thinking...';
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
        _engine.makeMove(aiMove);

        if (_engine.isCheckmate(PieceColor.white)) {
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
            _statusText = 'Your move (White)';
          });
        }
      }
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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          ElevatedButton(
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
    final boardSize = screenWidth.clamp(280.0, 480.0);
    final squareSize = boardSize / 8;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2429),
      appBar: AppBar(
        title: const Text('Travel Chess AI', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF14181B),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
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
              capturedPieces: _engine.capturedByBlack,
            ),

            // Status message
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: const Color(0xFF262D34),
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
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // 8x8 Chess Board Canvas
            Center(
              child: Container(
                width: boardSize,
                height: boardSize,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF3E2723), width: 4),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: List.generate(8, (row) {
                    return Row(
                      children: List.generate(8, (col) {
                        return _buildSquare(row, col, squareSize);
                      }),
                    );
                  }),
                ),
              ),
            ),

            const Spacer(),

            // White (User) Player Banner
            _buildPlayerBanner(
              name: 'You (White)',
              isAi: false,
              isTurn: _engine.currentTurn == PieceColor.white,
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
    required List<ChessPiece> capturedPieces,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isTurn ? const Color(0xFF2D3843) : const Color(0xFF181D22),
      child: Row(
        children: [
          Icon(
            isAi ? Icons.psychology : Icons.person,
            color: isTurn ? Colors.amber : Colors.white60,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: isTurn ? Colors.white : Colors.white70,
              fontWeight: isTurn ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          // Captured pieces
          Row(
            children: capturedPieces.take(8).map((p) {
              return Text(
                p.symbol,
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSquare(int row, int col, double size) {
    final isLight = (row + col) % 2 == 0;
    final squareColor = isLight ? const Color(0xFFEEEED2) : const Color(0xFF769656);

    final isSelected = _selectedPosition != null &&
        _selectedPosition!.row == row &&
        _selectedPosition!.col == col;

    final isLegalMoveDest = _currentLegalMoves.any((m) => m.to.row == row && m.to.col == col);
    final piece = _engine.pieceAt(row, col);

    return GestureDetector(
      onTap: () => _onSquareTapped(row, col),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFBBCE44) : squareColor,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Legal move dot or capture ring
            if (isLegalMoveDest)
              Container(
                width: piece == null ? size * 0.3 : size * 0.85,
                height: piece == null ? size * 0.3 : size * 0.85,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: piece == null
                      ? const Color(0x66000000)
                      : Colors.transparent,
                  border: piece != null
                      ? Border.all(color: const Color(0x88FF0000), width: 3)
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
                      ? const [Shadow(blurRadius: 3, color: Colors.black45, offset: Offset(1, 1))]
                      : const [Shadow(blurRadius: 2, color: Colors.white24, offset: Offset(-1, -1))],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
