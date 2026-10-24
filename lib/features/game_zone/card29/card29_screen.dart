import 'dart:async';
import 'package:flutter/material.dart';
import 'card29_engine.dart';

enum GamePhase {
  bidding,
  trumpSelection,
  playing,
  roundOver,
}

class Card29Screen extends StatefulWidget {
  const Card29Screen({super.key});

  @override
  State<Card29Screen> createState() => _Card29ScreenState();
}

class _Card29ScreenState extends State<Card29Screen> {
  // Game state
  GamePhase _phase = GamePhase.bidding;
  int _currentTurn = 0; // 0: South (User), 1: East, 2: North, 3: West
  
  // Hands
  final List<List<Card29>> _hands = [[], [], [], []];
  final List<Card29> _fullDeck = [];
  
  // Bidding
  int _highestBid = 15;
  int _highestBidder = -1;
  int _consecutivePasses = 0;
  
  // Trump
  CardSuit? _trumpSuit;
  bool _isTrumpRevealed = false;
  
  // Current trick
  final List<PlayedCard> _currentTrick = [];
  CardSuit? _currentLeadSuit;
  
  // Points & Trumps
  int _team1Points = 0; // South (0) + North (2)
  int _team2Points = 0; // East (1) + West (3)
  int _team1GamesWon = 0;
  int _team2GamesWon = 0;
  int _trickCount = 0;
  
  String _statusMessage = 'Welcome to 29! Dealing cards...';
  bool _isBotThinking = false;

  final List<String> _playerNames = ['You (South)', 'East (Bot)', 'North (Partner)', 'West (Bot)'];

  @override
  void initState() {
    super.initState();
    _startNewRound();
  }

  void _startNewRound() {
    final deck = Card29Engine.createDeck();
    _fullDeck.clear();
    _fullDeck.addAll(deck);

    for (int i = 0; i < 4; i++) {
      _hands[i].clear();
      // First deal: 4 cards each
      _hands[i].addAll(_fullDeck.sublist(i * 4, (i + 1) * 4));
      _sortHand(_hands[i]);
    }

    setState(() {
      _phase = GamePhase.bidding;
      _highestBid = 15;
      _highestBidder = -1;
      _consecutivePasses = 0;
      _currentTurn = 0;
      _trumpSuit = null;
      _isTrumpRevealed = false;
      _currentTrick.clear();
      _currentLeadSuit = null;
      _team1Points = 0;
      _team2Points = 0;
      _trickCount = 0;
      _statusMessage = 'Place your bid (16-28) or Pass';
    });
  }

  void _sortHand(List<Card29> hand) {
    hand.sort((a, b) {
      if (a.suit != b.suit) {
        return a.suit.index.compareTo(b.suit.index);
      }
      return b.power.compareTo(a.power);
    });
  }

  // --- BIDDING LOGIC ---
  void _submitBid(int bid) {
    if (bid <= _highestBid || bid > Card29Engine.maxBid) return;

    setState(() {
      _highestBid = bid;
      _highestBidder = _currentTurn;
      _consecutivePasses = 0;
      _statusMessage = '${_playerNames[_currentTurn]} bids $bid!';
    });

    _advanceBidding();
  }

  void _submitPass() {
    setState(() {
      _consecutivePasses++;
      _statusMessage = '${_playerNames[_currentTurn]} passes.';
    });

    _advanceBidding();
  }

  void _advanceBidding() {
    // If 3 consecutive passes occur after at least 1 bid, bidding ends
    if (_highestBidder != -1 && _consecutivePasses >= 3) {
      _endBidding();
      return;
    }

    // If 4 consecutive passes with no bids, default to South bid 16
    if (_highestBidder == -1 && _consecutivePasses >= 4) {
      setState(() {
        _highestBid = 16;
        _highestBidder = 0;
        _statusMessage = 'All passed. You must play for 16!';
      });
      _endBidding();
      return;
    }

    setState(() {
      _currentTurn = (_currentTurn + 1) % 4;
    });

    if (_currentTurn != 0) {
      _triggerBotBid();
    }
  }

  void _triggerBotBid() {
    _isBotThinking = true;
    Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _isBotThinking = false;
      
      final botHand = _hands[_currentTurn];
      // Simple heuristic: count Jack and Nines in bot's hand
      int highPoints = 0;
      for (final c in botHand) {
        if (c.rank == CardRank.jack) highPoints += 3;
        if (c.rank == CardRank.nine) highPoints += 2;
        if (c.rank == CardRank.ace) highPoints += 1;
      }

      int maxBotBid = 15;
      if (highPoints >= 7) {
        maxBotBid = 19;
      } else if (highPoints >= 5) {
        maxBotBid = 17;
      } else if (highPoints >= 4) {
        maxBotBid = 16;
      }

      if (maxBotBid > _highestBid && maxBotBid <= 20) {
        _submitBid(_highestBid + 1);
      } else {
        _submitPass();
      }
    });
  }

  void _endBidding() {
    if (_highestBidder == 0) {
      setState(() {
        _phase = GamePhase.trumpSelection;
        _statusMessage = 'You won the bid at $_highestBid! Select a Trump suit.';
      });
    } else {
      // Bot chooses trump
      final botHand = _hands[_highestBidder];
      final suitCounts = <CardSuit, int>{};
      for (final c in botHand) {
        suitCounts[c.suit] = (suitCounts[c.suit] ?? 0) + 1;
      }
      CardSuit bestSuit = CardSuit.spades;
      int maxCount = 0;
      suitCounts.forEach((suit, count) {
        if (count > maxCount) {
          maxCount = count;
          bestSuit = suit;
        }
      });

      _trumpSuit = bestSuit;

      setState(() {
        _statusMessage = '${_playerNames[_highestBidder]} won at $_highestBid and set the trump card.';
      });

      _dealSecondBatch();
    }
  }

  void _selectTrump(CardSuit suit) {
    _trumpSuit = suit;

    _dealSecondBatch();
  }

  void _dealSecondBatch() {
    // Deal next 4 cards to each player
    for (int i = 0; i < 4; i++) {
      _hands[i].addAll(_fullDeck.sublist(16 + i * 4, 16 + (i + 1) * 4));
      _sortHand(_hands[i]);
    }

    setState(() {
      _phase = GamePhase.playing;
      _currentTurn = _highestBidder;
      _statusMessage = 'Game starts! ${_playerNames[_currentTurn]} leads the first trick.';
    });

    if (_currentTurn != 0) {
      _triggerBotPlay();
    }
  }

  // --- PLAY LOGIC ---
  void _playCard(int playerIdx, Card29 card) {
    setState(() {
      _hands[playerIdx].remove(card);
      _currentTrick.add(PlayedCard(playerIndex: playerIdx, card: card));
      _currentLeadSuit ??= card.suit;
    });

    if (_currentTrick.length == 4) {
      _resolveTrick();
    } else {
      setState(() {
        _currentTurn = (_currentTurn + 1) % 4;
      });
      if (_currentTurn != 0) {
        _triggerBotPlay();
      }
    }
  }

  void _resolveTrick() {
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;

      final winnerPlay = Card29Engine.determineTrickWinner(
        trickCards: _currentTrick,
        trumpSuit: _trumpSuit,
        isTrumpRevealed: _isTrumpRevealed,
      );

      int trickPts = 0;
      for (final p in _currentTrick) {
        trickPts += p.card.points;
      }

      final winner = winnerPlay.playerIndex;
      final isTeam1 = (winner == 0 || winner == 2);
      
      _trickCount++;
      // Last trick gets +1 bonus point
      if (_trickCount == 8) {
        trickPts += 1;
      }

      setState(() {
        if (isTeam1) {
          _team1Points += trickPts;
        } else {
          _team2Points += trickPts;
        }

        _statusMessage = '${_playerNames[winner]} won the trick (+$trickPts pts)!';
        _currentTrick.clear();
        _currentLeadSuit = null;
        _currentTurn = winner;
      });

      if (_trickCount == 8) {
        _evaluateRoundOutcome();
      } else {
        if (_currentTurn != 0) {
          _triggerBotPlay();
        }
      }
    });
  }

  void _evaluateRoundOutcome() {
    final bidderIsTeam1 = (_highestBidder == 0 || _highestBidder == 2);
    final bidderScore = bidderIsTeam1 ? _team1Points : _team2Points;
    final target = _highestBid;

    bool bidderWon = bidderScore >= target;

    setState(() {
      _phase = GamePhase.roundOver;
      if (bidderWon) {
        if (bidderIsTeam1) {
          _team1GamesWon++;
          _statusMessage = 'Victory! Team 1 made the bid ($bidderScore/$_highestBid). +1 Game Point!';
        } else {
          _team2GamesWon++;
          _statusMessage = 'Team 2 made the bid ($bidderScore/$_highestBid). +1 Game Point to opponents!';
        }
      } else {
        if (bidderIsTeam1) {
          _team2GamesWon++;
          _statusMessage = 'Set! Team 1 failed bid ($bidderScore/$_highestBid). +1 Point to opponents!';
        } else {
          _team1GamesWon++;
          _statusMessage = 'Opponents set! Team 2 failed bid ($bidderScore/$_highestBid). +1 Point to you!';
        }
      }
    });
  }

  void _revealTrump() {
    if (_isTrumpRevealed || _trumpSuit == null) return;

    setState(() {
      _isTrumpRevealed = true;
      _statusMessage = '${_playerNames[_currentTurn]} revealed Trump: ${_trumpSuit!.name} (${_trumpSuit!.symbol})!';
    });
  }

  void _triggerBotPlay() {
    if (_phase != GamePhase.playing) return;
    _isBotThinking = true;

    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _isBotThinking = false;

      final botHand = _hands[_currentTurn];
      if (botHand.isEmpty) return;

      // Check if bot can follow suit
      final legalCards = botHand.where((c) {
        return Card29Engine.isCardLegal(
          card: c,
          hand: botHand,
          leadSuit: _currentLeadSuit,
          isTrumpRevealed: _isTrumpRevealed,
        );
      }).toList();

      // If cannot follow suit and trump not revealed, bot reveals trump
      if (_currentLeadSuit != null && 
          !_isTrumpRevealed && 
          !botHand.any((c) => c.suit == _currentLeadSuit)) {
        _revealTrump();
      }

      // Pick best legal card
      Card29 chosenCard = legalCards.first;
      if (legalCards.length > 1) {
        // Simple strategy: play lowest power unless partner can't win
        legalCards.sort((a, b) => a.power.compareTo(b.power));
        chosenCard = legalCards.first;
      }

      _playCard(_currentTurn, chosenCard);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F381E), // Emerald casino felt
      appBar: AppBar(
        title: const Text('29 Card Game (টুয়েন্টি নাইন)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF092614),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New Round',
            onPressed: _startNewRound,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '29 Rules',
            onPressed: _showRulesDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Score & Round Info
            _buildScoreHeader(),

            // Table Felt Canvas
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // North (Partner) Seat
                  Positioned(
                    top: 12,
                    child: _buildPlayerSeat(
                      playerIdx: 2,
                      name: 'North (Partner)',
                      cardCount: _hands[2].length,
                      isTurn: _currentTurn == 2,
                    ),
                  ),

                  // West Seat
                  Positioned(
                    left: 12,
                    child: _buildPlayerSeat(
                      playerIdx: 3,
                      name: 'West',
                      cardCount: _hands[3].length,
                      isTurn: _currentTurn == 3,
                    ),
                  ),

                  // East Seat
                  Positioned(
                    right: 12,
                    child: _buildPlayerSeat(
                      playerIdx: 1,
                      name: 'East',
                      cardCount: _hands[1].length,
                      isTurn: _currentTurn == 1,
                    ),
                  ),

                  // Center Felt Table: Trick Area + Trump Indicator
                  _buildCenterTable(),

                  // Bottom: Trump Reveal Button & Bidding Controls
                  if (_phase == GamePhase.bidding && _currentTurn == 0)
                    Positioned(
                      bottom: 120,
                      child: _buildBiddingControls(),
                    ),

                  if (_phase == GamePhase.trumpSelection && _highestBidder == 0)
                    Positioned(
                      bottom: 110,
                      child: _buildTrumpSelector(),
                    ),

                  if (_phase == GamePhase.roundOver)
                    Positioned(
                      bottom: 110,
                      child: _buildRoundOverBanner(),
                    ),
                ],
              ),
            ),

            // User's Hand (South)
            _buildUserHand(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF092614),
        border: Border(bottom: BorderSide(color: Color(0x33FFFFFF))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Team 1 (You & North)
              Row(
                children: [
                  const Icon(Icons.shield, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'You & North: $_team1Points pts ($_team1GamesWon wins)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              // Target Bid
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _highestBidder != -1
                      ? 'Bid: $_highestBid by ${_playerNames[_highestBidder].split(' ').first}'
                      : 'Bidding...',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              // Team 2 (East & West)
              Row(
                children: [
                  Text(
                    'Opponents: $_team2Points pts ($_team2GamesWon wins)',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.local_fire_department, color: Colors.redAccent, size: 18),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Status Notification Banner
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSeat({
    required int playerIdx,
    required String name,
    required int cardCount,
    required bool isTurn,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isTurn ? Colors.amber : const Color(0x66000000),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTurn ? Colors.white : Colors.white24,
              width: isTurn ? 2 : 1,
            ),
            boxShadow: isTurn
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                playerIdx == 0 || playerIdx == 2 ? Icons.person : Icons.smart_toy,
                size: 14,
                color: isTurn ? Colors.black87 : Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                name,
                style: TextStyle(
                  color: isTurn ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Mini Card Backs
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            cardCount,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 10,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.white70, width: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCenterTable() {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF134526),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x44FFFFFF), width: 3),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Trump Suit Box
          Positioned(
            top: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x88000000),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Trump: ', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  if (_isTrumpRevealed && _trumpSuit != null)
                    Text(
                      '${_trumpSuit!.symbol} ${_trumpSuit!.name}',
                      style: TextStyle(
                        color: (_trumpSuit == CardSuit.hearts || _trumpSuit == CardSuit.diamonds)
                            ? Colors.redAccent
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    )
                  else
                    const Text('🔒 Hidden', style: TextStyle(color: Colors.amber, fontSize: 10)),
                ],
              ),
            ),
          ),

          // Played cards in current trick
          if (_currentTrick.isEmpty)
            Text(
              _phase == GamePhase.playing ? 'Trick #${_trickCount + 1}' : '29',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 28, fontWeight: FontWeight.bold),
            )
          else
            ..._currentTrick.map((play) {
              // Offset card based on who played it
              Offset offset = Offset.zero;
              if (play.playerIndex == 0) offset = const Offset(0, 36); // South
              if (play.playerIndex == 1) offset = const Offset(36, 0); // East
              if (play.playerIndex == 2) offset = const Offset(0, -36); // North
              if (play.playerIndex == 3) offset = const Offset(-36, 0); // West

              return Transform.translate(
                offset: offset,
                child: _buildCardView(play.card, width: 44, height: 64, isInteractive: false),
              );
            }),

          // Trump Reveal Action Button (during play when user turn and not revealed)
          if (_phase == GamePhase.playing &&
              !_isTrumpRevealed &&
              _currentTurn == 0 &&
              _currentLeadSuit != null &&
              !_hands[0].any((c) => c.suit == _currentLeadSuit))
            Positioned(
              bottom: 24,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.lock_open, size: 14),
                label: const Text('Ask Trump', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: _revealTrump,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBiddingControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEE092614),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Your Bid:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _submitPass,
                child: const Text('Pass'),
              ),
              const SizedBox(width: 8),
              ...[16, 17, 18, 19, 20].where((b) => b > _highestBid).take(3).map((b) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _submitBid(b),
                    child: Text('$b', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrumpSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEE092614),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select Trump Suit:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: CardSuit.values.map((s) {
              final isRed = (s == CardSuit.hearts || s == CardSuit.diamonds);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: isRed ? Colors.red : Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () => _selectTrump(s),
                  child: Text('${s.symbol} ${s.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundOverBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xEE092614),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Next Deal', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: _startNewRound,
          ),
        ],
      ),
    );
  }

  Widget _buildUserHand() {
    final userHand = _hands[0];
    final isUserTurn = (_phase == GamePhase.playing && _currentTurn == 0 && !_isBotThinking);

    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF092614),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isUserTurn ? 'YOUR TURN - Play a card' : 'Your Cards (South)',
                style: TextStyle(
                  color: isUserTurn ? Colors.amber : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (isUserTurn) ...[
                const SizedBox(width: 6),
                const Icon(Icons.touch_app, size: 14, color: Colors.amber),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: userHand.map((card) {
                  final isLegal = isUserTurn &&
                      Card29Engine.isCardLegal(
                        card: card,
                        hand: userHand,
                        leadSuit: _currentLeadSuit,
                        isTrumpRevealed: _isTrumpRevealed,
                      );

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: (isUserTurn && isLegal) ? () => _playCard(0, card) : null,
                      child: Opacity(
                        opacity: (isUserTurn && !isLegal) ? 0.4 : 1.0,
                        child: _buildCardView(card, width: 48, height: 72, isInteractive: isLegal),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardView(Card29 card, {required double width, required double height, bool isInteractive = false}) {
    final isRed = (card.suit == CardSuit.hearts || card.suit == CardSuit.diamonds);
    final color = isRed ? Colors.red.shade700 : Colors.black87;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isInteractive ? Colors.amber : const Color(0x66000000),
          width: isInteractive ? 1.5 : 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                '${card.rank.code}\n${card.suit.symbol}',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  height: 0.9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              card.suit.symbol,
              style: TextStyle(color: color, fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2, right: 4),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Text(
                card.rank.code,
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRulesDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rules of 29 (টুয়েন্টি নাইন)'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Point Values:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• Jack (J) = 3 points\n• Nine (9) = 2 points\n• Ace (A) = 1 point\n• Ten (10) = 1 point\n• K, Q, 8, 7 = 0 points\n• Last trick bonus = 1 point\nTotal = 29 points'),
              SizedBox(height: 12),
              Text(
                'Gameplay:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('1. Bidding starts at 16 up to 28.\n2. Highest bidder picks a trump suit card (kept hidden).\n3. Players must follow the lead suit if they possess it.\n4. If unable to follow suit, players can reveal the trump card.\n5. Trumps beat all non-trump cards.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
