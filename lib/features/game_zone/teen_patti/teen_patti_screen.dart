import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'teen_patti_engine.dart';

class TeenPattiPlayer {
  final int id;
  final String name;
  final bool isUser;
  List<TeenPattiCard> hand;
  bool isSeen;
  bool isFolded;
  int chips;
  int blindTurns;

  TeenPattiPlayer({
    required this.id,
    required this.name,
    required this.isUser,
    required this.hand,
    this.isSeen = false,
    this.isFolded = false,
    this.chips = 500,
    this.blindTurns = 0,
  });
}

class TeenPattiScreen extends StatefulWidget {
  const TeenPattiScreen({super.key});

  @override
  State<TeenPattiScreen> createState() => _TeenPattiScreenState();
}

class _TeenPattiScreenState extends State<TeenPattiScreen> {
  final List<TeenPattiPlayer> _players = [];
  int _currentTurn = 0;
  int _pot = 0;
  int _currentBet = 10;
  bool _isRoundOver = false;
  String _statusMessage = 'Welcome to 3 Patti (তিন পাত্তি)! Place boot.';
  bool _isBotThinking = false;

  Timer? _botTimer;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }

  void _initGame() {
    _players.clear();
    _players.addAll([
      TeenPattiPlayer(id: 0, name: 'You (South)', isUser: true, hand: []),
      TeenPattiPlayer(id: 1, name: 'East (Bot)', isUser: false, hand: []),
      TeenPattiPlayer(id: 2, name: 'North (Bot)', isUser: false, hand: []),
      TeenPattiPlayer(id: 3, name: 'West (Bot)', isUser: false, hand: []),
    ]);

    _startNewRound();
  }

  void _startNewRound() {
    _botTimer?.cancel();

    // Check if user needs rebuy
    if (_players[0].chips < 10) {
      _players[0].chips = 500;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rebuy! Added +500 chips to your balance.')),
      );
    }

    final deck = TeenPattiEngine.createDeck();

    for (int i = 0; i < 4; i++) {
      _players[i].hand = deck.sublist(i * 3, (i + 1) * 3);
      _players[i].isFolded = false;
      _players[i].isSeen = false;
      _players[i].blindTurns = 0;

      // Rebuy bots if broke
      if (_players[i].chips < 10) {
        _players[i].chips = 500;
      }
    }

    // Collect boot of 10 from each
    const boot = 10;
    _pot = 0;
    for (final p in _players) {
      p.chips -= boot;
      _pot += boot;
    }

    setState(() {
      _currentTurn = 0;
      _currentBet = 10;
      _isRoundOver = false;
      _isBotThinking = false;
      _statusMessage = 'Boot collected (40 chips). Your turn (Blind / See Cards).';
    });
  }

  void _userSeeCards() {
    HapticFeedback.selectionClick();
    setState(() {
      _players[0].isSeen = true;
      _statusMessage = 'You saw your cards! Current chaal is ${_currentBet * 2}.';
    });
  }

  void _userBet() {
    HapticFeedback.lightImpact();
    final player = _players[0];
    final cost = player.isSeen ? _currentBet * 2 : _currentBet;

    if (player.chips < cost) {
      _userFold();
      return;
    }

    if (!player.isSeen) {
      player.blindTurns++;
      if (player.blindTurns >= 4) {
        player.isSeen = true; // Auto see cards after 4 blinds
      }
    }

    setState(() {
      player.chips -= cost;
      _pot += cost;
      _statusMessage = 'You played ${player.isSeen ? "Chaal" : "Blind"} ($cost chips).';
    });

    _advanceTurn();
  }

  void _userRaiseBet() {
    HapticFeedback.mediumImpact();
    if (_currentBet >= 40) return; // Cap at 40 (chaal 80)

    setState(() {
      _currentBet *= 2;
      _statusMessage = 'Stakes raised! Base bet is now $_currentBet chips.';
    });

    _userBet();
  }

  void _userFold() {
    HapticFeedback.lightImpact();
    setState(() {
      _players[0].isFolded = true;
      _statusMessage = 'You packed (folded).';
    });

    _checkRoundState();
  }

  void _userSideshow() {
    HapticFeedback.mediumImpact();
    final previousPlayer = _getPreviousActivePlayer();
    if (previousPlayer == null || !previousPlayer.isSeen || !_players[0].isSeen) return;

    final cost = _currentBet * 2;
    _players[0].chips -= cost;
    _pot += cost;

    // Private compare
    final cmp = TeenPattiEngine.compareHands(_players[0].hand, previousPlayer.hand);

    setState(() {
      if (cmp >= 0) {
        previousPlayer.isFolded = true;
        _statusMessage = 'Sideshow won! ${previousPlayer.name} was packed.';
      } else {
        _players[0].isFolded = true;
        _statusMessage = 'Sideshow lost! You had weaker cards and were packed.';
      }
    });

    _checkRoundState();
  }

  TeenPattiPlayer? _getPreviousActivePlayer() {
    int idx = (_currentTurn + 3) % 4;
    while (_players[idx].isFolded) {
      idx = (idx + 3) % 4;
      if (idx == _currentTurn) return null;
    }
    return _players[idx];
  }

  void _userShow() {
    HapticFeedback.heavyImpact();
    final active = _players.where((p) => !p.isFolded).toList();
    if (active.length != 2) return;

    final cost = _players[0].isSeen ? _currentBet * 2 : _currentBet;
    _players[0].chips -= cost;
    _pot += cost;

    _resolveShowdown();
  }

  void _advanceTurn() {
    final active = _players.where((p) => !p.isFolded).toList();
    if (active.length <= 1) {
      _resolveLastStandingWinner();
      return;
    }

    do {
      _currentTurn = (_currentTurn + 1) % 4;
    } while (_players[_currentTurn].isFolded);

    setState(() {});

    if (!_players[_currentTurn].isUser) {
      _runBotTurn();
    }
  }

  void _runBotTurn() {
    _isBotThinking = true;
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      _isBotThinking = false;

      final bot = _players[_currentTurn];
      final eval = TeenPattiEngine.evaluateHand(bot.hand);

      // Bot sees cards after 2 blinds or high pot
      if (!bot.isSeen && (_pot > 80 || bot.blindTurns >= 2)) {
        bot.isSeen = true;
      }

      if (!bot.isSeen) {
        bot.blindTurns++;
      }

      final active = _players.where((p) => !p.isFolded).toList();

      // Bot asks for show if only 2 players left and hand is high
      if (active.length == 2 && eval.handType.score >= 2 && _pot > 120) {
        final cost = bot.isSeen ? _currentBet * 2 : _currentBet;
        bot.chips -= cost;
        _pot += cost;
        setState(() {
          _statusMessage = '${bot.name} asked for a Show!';
        });
        _resolveShowdown();
        return;
      }

      // Fold if weak hand and seen
      if (bot.isSeen && eval.handType == TeenPattiHandType.highCard && eval.primaryValue < 11 && _pot > 90) {
        setState(() {
          bot.isFolded = true;
          _statusMessage = '${bot.name} packed (folded).';
        });
        _checkRoundState();
        return;
      }

      // Otherwise bot bets
      final cost = bot.isSeen ? _currentBet * 2 : _currentBet;
      bot.chips -= cost;
      _pot += cost;

      setState(() {
        _statusMessage = '${bot.name} played ${bot.isSeen ? "Chaal" : "Blind"} ($cost chips).';
      });

      _advanceTurn();
    });
  }

  void _checkRoundState() {
    final active = _players.where((p) => !p.isFolded).toList();
    if (active.length <= 1) {
      _resolveLastStandingWinner();
    } else {
      _advanceTurn();
    }
  }

  void _resolveLastStandingWinner() {
    final winner = _players.firstWhere((p) => !p.isFolded);
    winner.chips += _pot;

    setState(() {
      _isRoundOver = true;
      _statusMessage = '${winner.name} won the pot of $_pot chips!';
    });

    _showResultDialog(winner.name, 'All opponents folded. You claim the pot of $_pot chips!');
  }

  void _resolveShowdown() {
    final active = _players.where((p) => !p.isFolded).toList();

    // Check tie or best
    TeenPattiPlayer best = active.first;
    bool isTie = false;
    for (int i = 1; i < active.length; i++) {
      final cmp = TeenPattiEngine.compareHands(active[i].hand, best.hand);
      if (cmp > 0) {
        best = active[i];
        isTie = false;
      } else if (cmp == 0) {
        isTie = true;
      }
    }

    if (isTie) {
      // Split pot
      final split = _pot ~/ active.length;
      for (final p in active) {
        p.chips += split;
      }
      setState(() {
        _isRoundOver = true;
        for (final p in _players) {
          p.isSeen = true;
        }
        _statusMessage = 'Showdown Tie! Pot of $_pot chips was split evenly.';
      });
      _showResultDialog('Split Pot', 'Equal hands! Pot was split evenly ($split chips each).');
    } else {
      best.chips += _pot;
      final bestEval = TeenPattiEngine.evaluateHand(best.hand);

      setState(() {
        _isRoundOver = true;
        for (final p in _players) {
          p.isSeen = true;
        }
        _statusMessage = '${best.name} wins with ${bestEval.handType.banglaName}!';
      });

      _showResultDialog(best.name, '${best.name} won the pot of $_pot chips with ${bestEval.handType.banglaName}!');
    }
  }

  void _showResultDialog(String winnerName, String detail) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF092614),
        title: Text('🏆 $winnerName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(detail, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: () {
              Navigator.pop(ctx);
              _startNewRound();
            },
            child: const Text('Next Deal'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeRemaining = _players.where((p) => !p.isFolded).length;
    final isUserTurn = _currentTurn == 0 && !_players[0].isFolded && !_isBotThinking && !_isRoundOver;
    final prevPlayer = _getPreviousActivePlayer();
    final canSideshow = isUserTurn &&
        _players[0].isSeen &&
        prevPlayer != null &&
        prevPlayer.isSeen &&
        activeRemaining > 2;

    return Scaffold(
      backgroundColor: const Color(0xFF0F381E), // Emerald casino felt
      appBar: AppBar(
        title: const Text('Teen Patti (৩ পাত্তি)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF092614),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New Hand',
            onPressed: _startNewRound,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Pot & Info Bar
            _buildPotHeader(),

            // Table Felt Canvas
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // North Seat
                      Positioned(
                        top: 10,
                        child: _buildPlayerSeat(_players[2]),
                      ),
                      // West Seat
                      Positioned(
                        left: 6,
                        child: _buildPlayerSeat(_players[3]),
                      ),
                      // East Seat
                      Positioned(
                        right: 6,
                        child: _buildPlayerSeat(_players[1]),
                      ),

                      // Center Pot & Chips Mat
                      _buildCenterPot(constraints.maxWidth),
                    ],
                  );
                },
              ),
            ),

            // User Cards & Controls (South)
            _buildUserControls(isUserTurn, activeRemaining, canSideshow),
          ],
        ),
      ),
    );
  }

  Widget _buildPotHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF092614),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your Chips: ${_players[0].chips}',
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Pot: $_pot chips',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Text('Base Bet: $_currentBet',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Text(_statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildPlayerSeat(TeenPattiPlayer player) {
    final isTurn = _currentTurn == player.id && !player.isFolded && !_isRoundOver;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isTurn ? Colors.amber : const Color(0x66000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isTurn ? Colors.white : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy, size: 12, color: isTurn ? Colors.black87 : Colors.white),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  '${player.name} (${player.chips})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isTurn ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (player.isFolded)
          const Text('PACKED', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold))
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: player.hand.map((c) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: player.isSeen || _isRoundOver
                    ? _buildMiniCard(c)
                    : Container(
                        width: 22,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.red.shade900,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white70, width: 0.5),
                        ),
                      ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildCenterPot(double maxWidth) {
    final potSize = (maxWidth * 0.28).clamp(90.0, 125.0);
    return Container(
      width: potSize,
      height: potSize,
      decoration: BoxDecoration(
        color: const Color(0xFF134526),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, color: Colors.amber, size: 26),
            const SizedBox(height: 2),
            Text('$_pot', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const Text('CHIPS', style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }

  Widget _buildUserControls(bool isUserTurn, int activeRemaining, bool canSideshow) {
    final user = _players[0];
    final userEval = user.isSeen ? TeenPattiEngine.evaluateHand(user.hand) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF092614),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hand rank indicator when seen
            if (userEval != null && !user.isFolded)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Your Hand: ${userEval.handType.banglaName}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),

            // Hand cards
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: user.hand.map((c) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: user.isSeen || _isRoundOver
                      ? _buildFullCard(c)
                      : GestureDetector(
                          onTap: _userSeeCards,
                          child: Container(
                            width: 52,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.red.shade900,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Center(
                              child: Text('👀 SEE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Action Buttons
            if (isUserTurn && !user.isFolded)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _userFold,
                    child: const Text('Pack (Fold)'),
                  ),
                  if (!user.isSeen)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: _userSeeCards,
                      child: const Text('See Cards'),
                    ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _userBet,
                    child: Text(user.isSeen ? 'Chaal (${_currentBet * 2})' : 'Blind ($_currentBet)'),
                  ),
                  if (_currentBet < 40)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber,
                        side: const BorderSide(color: Colors.amber),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: _userRaiseBet,
                      child: const Text('Raise (2x)'),
                    ),
                  if (canSideshow)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: _userSideshow,
                      child: const Text('Sideshow'),
                    ),
                  if (activeRemaining == 2)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: _userShow,
                      child: const Text('Show'),
                    ),
                ],
              )
            else if (_isRoundOver)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black87),
                onPressed: _startNewRound,
                child: const Text('Deal Next Hand'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniCard(TeenPattiCard c) {
    final isRed = c.suit == 'H' || c.suit == 'D';
    return Container(
      width: 22,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black38, width: 0.5),
      ),
      child: Center(
        child: Text(
          '${c.rank}${c.suitSymbol}',
          style: TextStyle(
            color: isRed ? Colors.red : Colors.black,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFullCard(TeenPattiCard c) {
    final isRed = c.suit == 'H' || c.suit == 'D';
    final color = isRed ? Colors.red.shade700 : Colors.black87;

    return Container(
      width: 52,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                '${c.rank}\n${c.suitSymbol}',
                style: TextStyle(color: color, fontSize: 11, height: 0.9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Text(c.suitSymbol, style: TextStyle(color: color, fontSize: 18)),
          Padding(
            padding: const EdgeInsets.only(bottom: 2, right: 4),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Text(c.rank, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
