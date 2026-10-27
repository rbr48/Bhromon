import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../chess/chess_engine.dart';
import '../chess/chess_piece_painter.dart';
import '../common/in_game_voice_bar.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';

class OnlineChessView extends StatefulWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  const OnlineChessView({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  @override
  State<OnlineChessView> createState() => _OnlineChessViewState();
}

class _OnlineChessViewState extends State<OnlineChessView> {
  late final ChessEngine _engine;
  BoardPosition? _selectedPosition;
  List<ChessMove> _currentLegalMoves = [];
  int _lastSyncedVersion = -1;

  OnlinePlayer? get _whitePlayer => widget.session.playerAt(0);
  OnlinePlayer? get _blackPlayer => widget.session.playerAt(1);

  bool get _isMyTurn => widget.session.isMyTurn(widget.myEmail);

  bool get _amWhite =>
      widget.session.playerByEmail(widget.myEmail)?.seatIndex == 0;

  PieceColor get _myColor =>
      _amWhite ? PieceColor.white : PieceColor.black;

  @override
  void initState() {
    super.initState();
    _engine = ChessEngine();
    _syncFromSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant OnlineChessView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.version != _lastSyncedVersion) {
      _syncFromSession(widget.session);
    }
  }

  void _syncFromSession(OnlineGameSession session) {
    _lastSyncedVersion = session.version;
    final state = session.state;
    final moveHistoryRaw = state['moves'] as List<dynamic>? ?? [];

    // Replay moves to keep engine state synchronized
    _engine.reset();
    for (final raw in moveHistoryRaw) {
      if (raw is Map<String, dynamic>) {
        final move = ChessMove(
          from: BoardPosition(raw['fromRow'] as int, raw['fromCol'] as int),
          to: BoardPosition(raw['toRow'] as int, raw['toCol'] as int),
          promotion: raw['promotion'] != null
              ? PieceType.values.firstWhere(
                  (t) => t.name == raw['promotion'],
                  orElse: () => PieceType.queen,
                )
              : null,
        );
        _engine.makeMove(move);
      }
    }

    if (mounted) setState(() {});
  }

  void _onSquareTapped(int row, int col) {
    if (!_isMyTurn || widget.session.status == GameSessionStatus.finished) {
      return;
    }

    final tappedPos = BoardPosition(row, col);

    // If destination of a legal move was tapped
    for (final move in _currentLegalMoves) {
      if (move.to == tappedPos) {
        _handleMoveAttempt(move);
        return;
      }
    }

    // Otherwise select a piece of the player's own color
    final piece = _engine.pieceAt(row, col);
    if (piece != null && piece.color == _myColor) {
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

  void _handleMoveAttempt(ChessMove move) {
    final movingPiece = _engine.pieceAt(move.from.row, move.from.col);
    final isPawnPromotion = movingPiece?.type == PieceType.pawn &&
        (move.to.row == 0 || move.to.row == 7);

    if (isPawnPromotion && move.promotion == null) {
      _showPromotionDialog(move);
    } else {
      _commitMove(move);
    }
  }

  Future<void> _showPromotionDialog(ChessMove baseMove) async {
    final chosen = await showDialog<PieceType>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2832),
        title: const Text('Promote Pawn', style: TextStyle(color: Colors.white)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPromotionButton(ctx, PieceType.queen, 'Queen'),
            _buildPromotionButton(ctx, PieceType.rook, 'Rook'),
            _buildPromotionButton(ctx, PieceType.bishop, 'Bishop'),
            _buildPromotionButton(ctx, PieceType.knight, 'Knight'),
          ],
        ),
      ),
    );

    if (chosen != null) {
      _commitMove(baseMove.withPromotion(chosen));
    }
  }

  Widget _buildPromotionButton(BuildContext ctx, PieceType type, String label) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, type),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ChessPiece(type, _myColor).symbol,
              style: TextStyle(
                fontSize: 32,
                color: _myColor == PieceColor.white
                    ? Colors.white
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _commitMove(ChessMove move) async {
    if (!_engine.makeMove(move)) return;

    HapticFeedback.lightImpact();

    setState(() {
      _selectedPosition = null;
      _currentLegalMoves = [];
    });

    final currentMoves = (widget.session.state['moves'] as List<dynamic>?) ?? [];
    final updatedMoves = [
      ...currentMoves,
      {
        'fromRow': move.from.row,
        'fromCol': move.from.col,
        'toRow': move.to.row,
        'toCol': move.to.col,
        'promotion': move.promotion?.name,
        'color': _myColor.name,
      }
    ];

    final isCheck = _engine.isCheck(_myColor.opponent);
    final isCheckmate = _engine.isCheckmate(_myColor.opponent);
    final isDraw = _engine.drawReason != null;

    final nextSeat = _amWhite ? 1 : 0;
    final isFinished = isCheckmate || isDraw;
    final winnerSeat = isCheckmate ? (_amWhite ? 0 : 1) : null;

    final newState = {
      'moves': updatedMoves,
      'isCheck': isCheck,
      'isCheckmate': isCheckmate,
      'isDraw': isDraw,
      'turn': _myColor.opponent.name,
    };

    final action = {
      'type': 'move',
      'player': widget.myEmail,
      'move': {
        'from': '${move.from.col},${move.from.row}',
        'to': '${move.to.col},${move.to.row}',
      },
    };

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: action,
      newState: newState,
      nextTurn: nextSeat,
      winnerSeat: winnerSeat,
      isFinished: isFinished,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Voice Bar
        InGameVoiceBar(
          tourId: widget.session.tourId,
          gameId: widget.session.id,
          myEmail: widget.myEmail,
          myDisplayName: widget.repository.currentDisplayName,
          myPhotoUrl: widget.repository.currentPhotoUrl,
          myUid: widget.repository.currentUid,
        ),

        // Opponent Player Banner
        _buildPlayerBanner(_amWhite ? _blackPlayer : _whitePlayer, isTop: true),

        // Chessboard
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildBoardGrid(),
              ),
            ),
          ),
        ),

        // My Player Banner
        _buildPlayerBanner(_amWhite ? _whitePlayer : _blackPlayer, isTop: false),
      ],
    );
  }

  Widget _buildPlayerBanner(OnlinePlayer? player, {required bool isTop}) {
    final isPlayerTurn = player != null &&
        widget.session.currentTurn == player.seatIndex &&
        widget.session.status == GameSessionStatus.inProgress;
    final isWhite = player?.seatIndex == 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isPlayerTurn
            ? AppColors.mintGreen.withValues(alpha: 0.15)
            : const Color(0xFF14241B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPlayerTurn ? AppColors.mintGreen : Colors.white12,
          width: isPlayerTurn ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isWhite ? Colors.white : Colors.black87,
            child: Icon(
              Icons.shield_rounded,
              color: isWhite ? Colors.black : Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player?.displayName ?? 'Opponent',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${isWhite ? 'White Pieces' : 'Black Pieces'}${isPlayerTurn ? ' • Thinking...' : ''}',
                  style: TextStyle(
                    color: isPlayerTurn ? AppColors.mintGreen : Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (isPlayerTurn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.mintGreen.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'TURN',
                style: TextStyle(
                  color: AppColors.mintGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoardGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final squareSize = constraints.maxWidth / 8;

        return Table(
          children: List.generate(8, (r) {
            // Flip board rows if playing as black
            final row = _amWhite ? r : 7 - r;

            return TableRow(
              children: List.generate(8, (c) {
                final col = _amWhite ? c : 7 - c;
                final isLight = (row + col) % 2 == 0;
                final pos = BoardPosition(row, col);
                final piece = _engine.pieceAt(row, col);

                final isSelected = _selectedPosition == pos;
                final isLegalDest =
                    _currentLegalMoves.any((m) => m.to == pos);

                return GestureDetector(
                  onTap: () => _onSquareTapped(row, col),
                  child: Container(
                    width: squareSize,
                    height: squareSize,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.amber.shade300
                          : (isLight
                              ? const Color(0xFFEEEED2)
                              : const Color(0xFF769656)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (piece != null)
                          CustomPaint(
                            size: Size(squareSize * 0.8, squareSize * 0.8),
                            painter: ChessPiecePainter(
                              type: piece.type,
                              isWhite: piece.color == PieceColor.white,
                              size: squareSize * 0.8,
                            ),
                          ),
                        if (isLegalDest)
                          Container(
                            width: piece == null ? 14 : squareSize * 0.75,
                            height: piece == null ? 14 : squareSize * 0.75,
                            decoration: BoxDecoration(
                              color: piece == null
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : null,
                              shape: BoxShape.circle,
                              border: piece != null
                                  ? Border.all(
                                      color: Colors.redAccent.withValues(alpha: 0.7),
                                      width: 3.5,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            );
          }),
        );
      },
    );
  }
}
