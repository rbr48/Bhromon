import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/colors.dart';
import '../card29/card29_engine.dart';
import '../card29/card29_game.dart';
import '../common/in_game_voice_bar.dart';
import '../common/playing_card_view.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';

class OnlineCard29View extends StatefulWidget {
  final OnlineGameSession session;
  final OnlineGameRepository repository;
  final String myEmail;

  const OnlineCard29View({
    super.key,
    required this.session,
    required this.repository,
    required this.myEmail,
  });

  @override
  State<OnlineCard29View> createState() => _OnlineCard29ViewState();
}

class _OnlineCard29ViewState extends State<OnlineCard29View> {
  late final Card29Game _game;
  int _lastSyncedVersion = -1;

  int get _mySeatIndex =>
      widget.session.playerByEmail(widget.myEmail)?.seatIndex ?? 0;

  bool get _isMyTurn => widget.session.currentTurn == _mySeatIndex;

  bool get _isHost => widget.session.hostEmail == widget.myEmail;

  @override
  void initState() {
    super.initState();
    _game = Card29Game();
    _syncFromSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant OnlineCard29View oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.version != _lastSyncedVersion) {
      _syncFromSession(widget.session);
    }
  }

  void _syncFromSession(OnlineGameSession session) {
    _lastSyncedVersion = session.version;
    final state = session.state;

    final phaseName = state['phase'] as String?;
    if (phaseName != null) {
      _game.phase = Card29Phase.values.firstWhere(
        (p) => p.name == phaseName,
        orElse: () => Card29Phase.bidding,
      );
    }

    _game.highestBid = (state['highestBid'] as num?)?.toInt() ?? 15;
    _game.highestBidder = (state['highestBidder'] as num?)?.toInt() ?? -1;
    _game.currentTurn = (state['currentTurn'] as num?)?.toInt() ?? 0;
    _game.isTrumpRevealed = state['isTrumpRevealed'] == true;

    final trumpSuitName = state['trumpSuit'] as String?;
    if (trumpSuitName != null) {
      _game.trumpSuit = CardSuit.values.firstWhere(
        (s) => s.name == trumpSuitName,
        orElse: () => CardSuit.spades,
      );
    }

    // Check if bot turn & host should act
    final currentPlayer = session.playerAt(_game.currentTurn);
    if (_isHost &&
        currentPlayer != null &&
        currentPlayer.isBot &&
        session.status == GameSessionStatus.inProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleBotAction();
      });
    }

    if (mounted) setState(() {});
  }

  Future<void> _handleBotAction() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || widget.session.version != _lastSyncedVersion) return;

    if (_game.phase == Card29Phase.bidding) {
      _game.pass(_game.currentTurn);
      await _commitGameState();
    } else if (_game.phase == Card29Phase.trumpSelection) {
      _game.selectTrump(CardSuit.hearts);
      await _commitGameState();
    } else if (_game.phase == Card29Phase.playing) {
      final legal = _game.legalCards(_game.currentTurn);
      if (legal.isNotEmpty) {
        _game.playCard(_game.currentTurn, legal.first);
        await _commitGameState();
      }
    }
  }

  Future<void> _placeBid(int bid) async {
    if (!_isMyTurn || _game.phase != Card29Phase.bidding) return;

    _game.placeBid(_mySeatIndex, bid);
    await _commitGameState();
  }

  Future<void> _passBid() async {
    if (!_isMyTurn || _game.phase != Card29Phase.bidding) return;

    _game.pass(_mySeatIndex);
    await _commitGameState();
  }

  Future<void> _selectTrump(CardSuit suit) async {
    if (_game.phase != Card29Phase.trumpSelection ||
        _game.highestBidder != _mySeatIndex) {
      return;
    }

    _game.selectTrump(suit);
    await _commitGameState();
  }

  Future<void> _playCard(Card29 card) async {
    if (!_isMyTurn || _game.phase != Card29Phase.playing) return;

    HapticFeedback.lightImpact();
    _game.playCard(_mySeatIndex, card);

    if (_game.currentTrick.length == 4) {
      _game.resolveTrick();
    }

    await _commitGameState();
  }

  Future<void> _commitGameState() async {
    final newState = {
      'phase': _game.phase.name,
      'highestBid': _game.highestBid,
      'highestBidder': _game.highestBidder,
      'currentTurn': _game.currentTurn,
      'isTrumpRevealed': _game.isTrumpRevealed,
      'trumpSuit': _game.trumpSuit?.name,
    };

    final isFinished = _game.phase == Card29Phase.matchOver;

    await widget.repository.commitAction(
      tourId: widget.session.tourId,
      gameId: widget.session.id,
      action: {'type': 'card_state_update'},
      newState: newState,
      nextTurn: _game.currentTurn,
      isFinished: isFinished,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myCards = _game.hands[_mySeatIndex];
    final activePlayer = widget.session.playerAt(_game.currentTurn);

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

        // Game Status Header
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF14241B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isMyTurn ? AppColors.mintGreen : Colors.white12,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Highest Bid: ${_game.highestBid > 15 ? '${_game.highestBid} by Seat ${_game.highestBidder + 1}' : 'No bids yet'}',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isMyTurn
                      ? AppColors.mintGreen.withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isMyTurn
                      ? 'YOUR TURN'
                      : "${activePlayer?.displayName ?? 'Seat ${_game.currentTurn + 1}'}'s turn",
                  style: TextStyle(
                    color: _isMyTurn ? AppColors.mintGreen : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Central Card Trick Mat
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B4332), // Felt green table
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2D6A4F), width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Trump indicator if revealed
                if (_game.isTrumpRevealed && _game.trumpSuit != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Trump: ${_game.trumpSuit!.name.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Played trick cards
                if (_game.currentTrick.isEmpty)
                  const Text(
                    '29 FELT MAT',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  )
                else
                  Wrap(
                    spacing: 12,
                    children: _game.currentTrick.map((tc) {
                      return PlayingCardView(
                        rank: tc.card.rank.code,
                        suitSymbol: tc.card.suit.symbol,
                        isRed: tc.card.suit == CardSuit.hearts ||
                            tc.card.suit == CardSuit.diamonds,
                        width: 54,
                        height: 78,
                      );
                    }).toList(),
                  ),

                // Trump Selection Modal
                if (_game.phase == Card29Phase.trumpSelection &&
                    _game.highestBidder == _mySeatIndex)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1E14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.mintGreen),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Pick Secret Trump Suit',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: CardSuit.values.map((suit) {
                            return IconButton(
                              icon: Icon(
                                suit == CardSuit.spades
                                    ? Icons.eco
                                    : (suit == CardSuit.hearts
                                        ? Icons.favorite
                                        : (suit == CardSuit.diamonds
                                            ? Icons.diamond
                                            : Icons.park)),
                                color: (suit == CardSuit.hearts ||
                                        suit == CardSuit.diamonds)
                                    ? Colors.redAccent
                                    : Colors.white,
                                size: 28,
                              ),
                              onPressed: () => _selectTrump(suit),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bidding Action Controls
        if (_isMyTurn && _game.phase == Card29Phase.bidding)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _placeBid(_game.highestBid + 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: Colors.black87,
                    ),
                    child: Text('Bid ${_game.highestBid + 1}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _passBid,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Pass'),
                  ),
                ),
              ],
            ),
          ),

        // My Cards Tray
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          color: const Color(0xFF0F1E14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: myCards.map((card) {
                final isLegal = _isMyTurn &&
                    _game.phase == Card29Phase.playing &&
                    _game.legalCards(_mySeatIndex).contains(card);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: isLegal ? () => _playCard(card) : null,
                    child: PlayingCardView(
                      rank: card.rank.code,
                      suitSymbol: card.suit.symbol,
                      isRed: card.suit == CardSuit.hearts ||
                          card.suit == CardSuit.diamonds,
                      width: 52,
                      height: 74,
                      highlighted: isLegal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
