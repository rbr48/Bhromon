import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../common/game_zone_portrait_lock.dart';
import '../common/playing_card_view.dart';
import '../data/game_analytics_service.dart';
import '../domain/models/game_analytics_models.dart';
import 'card29_engine.dart';
import 'card29_game.dart';

/// Keeps the match in progress while the player visits other screens.
class _Card29Session {
  static Card29Game? game;
  static bool matchResultRecorded = false;
}

class Card29Screen extends StatefulWidget {
  const Card29Screen({super.key});

  @override
  State<Card29Screen> createState() => _Card29ScreenState();
}

class _Card29ScreenState extends State<Card29Screen> with GameZonePortraitLock {
  late final Card29Game _game;
  Timer? _timer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _game = _Card29Session.game ??= Card29Game();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_game.hasStarted) _game.startRound();
      _afterChange();
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(Duration delay, VoidCallback action) {
    _timer?.cancel();
    final generation = _generation;
    _timer = Timer(delay, () {
      if (!mounted || generation != _generation) return;
      action();
      _afterChange();
    });
  }

  /// Drives bots and trick collection for whatever state the table is in.
  void _afterChange() {
    if (!mounted) return;
    setState(() {});
    _timer?.cancel();
    switch (_game.phase) {
      case Card29Phase.bidding:
        if (_game.currentTurn != 0) {
          _schedule(const Duration(milliseconds: 700), _game.playBotTurn);
        }
        break;
      case Card29Phase.playing:
        if (_game.currentTurn != 0) {
          _schedule(const Duration(milliseconds: 850), _game.playBotTurn);
        }
        break;
      case Card29Phase.trickComplete:
        _schedule(const Duration(milliseconds: 1100), _game.resolveTrick);
        break;
      case Card29Phase.trumpSelection:
      case Card29Phase.roundOver:
        break;
      case Card29Phase.matchOver:
        if (!_Card29Session.matchResultRecorded) {
          _Card29Session.matchResultRecorded = true;
          final userWon = _game.matchPips[0] >= Card29Game.pipsToWin;
          GameAnalyticsService().recordMatch(
            gameType: OnlineGameType.card29,
            won: userWon,
            score: _game.matchPips[0],
          );
        }
        break;
    }
  }

  void _userAction(bool Function() action, {bool heavy = false}) {
    if (!action()) return;
    heavy ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    _afterChange();
  }

  Future<void> _onNewRoundPressed() async {
    if (_game.phase == Card29Phase.matchOver) {
      _startNewMatch();
      return;
    }
    if (_game.isRoundInProgress) {
      final ok = await confirmDiscardGame(
        context,
        title: 'Redeal this round?',
        message: 'The cards in play will be thrown in. Match pips are kept.',
        confirmLabel: 'Redeal',
      );
      if (!ok || !mounted) return;
    }
    _generation++;
    _game.startRound();
    _afterChange();
  }

  void _startNewMatch() {
    _generation++;
    _Card29Session.matchResultRecorded = false;
    _game.newMatch();
    _afterChange();
  }

  bool get _isUserTurnToPlay =>
      _game.phase == Card29Phase.playing && _game.currentTurn == 0;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          try {
            context.go('/game-zone');
          } catch (_) {}
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0F381E),
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70, size: 18),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  try {
                    context.go('/game-zone');
                  } catch (_) {}
                }
              },
            ),
            title: const Text('29 Card Game (টুয়েন্টি নাইন)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF092614),
            foregroundColor: Colors.white,
            elevation: 2,
            actions: [
              IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'New Round',
                  onPressed: _onNewRoundPressed),
              IconButton(
                  icon: const Icon(Icons.help_outline),
                  tooltip: '29 Rules',
                  onPressed: _showRulesDialog),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildScoreHeader(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(top: 6, child: _buildPlayerSeat(2)),
                          Positioned(left: 6, child: _buildPlayerSeat(3)),
                          Positioned(right: 6, child: _buildPlayerSeat(1)),
                          _buildCenterTable(constraints),
                          if (_game.phase == Card29Phase.bidding &&
                              _game.currentTurn == 0)
                            Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Center(child: _buildBiddingControls())),
                          if (_game.phase == Card29Phase.trumpSelection)
                            Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Center(child: _buildTrumpSelector())),
                          if (_game.phase == Card29Phase.roundOver ||
                              _game.phase == Card29Phase.matchOver)
                            Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Center(child: _buildRoundOverBanner())),
                        ],
                      );
                    },
                  ),
                ),
                _buildActionBar(),
                _buildUserHand(),
              ],
            ),
          ),
        ));
  }

  Widget _buildScoreHeader() {
    final bidText = _game.highestBidder == -1
        ? 'Bidding...'
        : _game.bidTarget != _game.highestBid && _game.bidTarget != 0
            ? 'Bid ${_game.highestBid} by ${_shortName(_game.highestBidder)} · target ${_game.bidTarget}'
            : 'Bid ${_game.highestBid} by ${_shortName(_game.highestBidder)}';

    Widget teamScore(
        String label, int team, Color color, CrossAxisAlignment align) {
      return Expanded(
        child: Column(
          crossAxisAlignment: align,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${_game.teamPoints[team]} pts · pips ${_game.matchPips[team]}/${Card29Game.pipsToWin}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF092614),
        border: Border(bottom: BorderSide(color: Color(0x33FFFFFF))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              teamScore(
                  '🛡 Your team', 0, Colors.amber, CrossAxisAlignment.start),
              const SizedBox(width: 6),
              Flexible(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.amber.shade800,
                      borderRadius: BorderRadius.circular(12)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bidText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              teamScore('Opponents 🔥', 1, Colors.redAccent.shade100,
                  CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _game.status,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  String _shortName(int player) =>
      player == 0 ? 'You' : Card29Game.playerNames[player].split(' ').first;

  Widget _buildPlayerSeat(int playerIdx) {
    final isTurn = _game.currentTurn == playerIdx &&
        (_game.phase == Card29Phase.bidding ||
            _game.phase == Card29Phase.playing);
    final isTrickWinner = _game.phase == Card29Phase.trickComplete &&
        _game.trickWinner == playerIdx;
    final cardCount = _game.hands[playerIdx].length;
    final isPartner = playerIdx == 2;
    final highlight = isTurn || isTrickWinner;

    return Semantics(
      label:
          '${Card29Game.playerNames[playerIdx]}, $cardCount cards${isTurn ? ', their turn' : ''}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: highlight ? Colors.amber : const Color(0x66000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: highlight ? Colors.white : Colors.white24,
                  width: highlight ? 2 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy,
                    size: 14, color: highlight ? Colors.black87 : Colors.white),
                const SizedBox(width: 4),
                Text(
                  isPartner
                      ? 'North · Partner'
                      : Card29Game.playerNames[playerIdx].split(' ').first,
                  style: TextStyle(
                    color: highlight ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Compact two-row fan of card backs so side seats stay narrow.
          SizedBox(
            width: 4 * 12.0,
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              alignment: WrapAlignment.center,
              children: List.generate(
                cardCount,
                (_) => const PlayingCardView(
                  rank: '',
                  suitSymbol: '',
                  isRed: false,
                  isFaceUp: false,
                  width: 11,
                  height: 15,
                  backColor: Color(0xFF8B0000),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterTable(BoxConstraints constraints) {
    final tableSize =
        min(constraints.maxWidth * 0.56, constraints.maxHeight - 110)
            .clamp(150.0, 250.0);
    final cardW = tableSize * 0.2;
    final cardH = cardW * 1.45;
    final offset = tableSize * 0.15;
    final trump = _game.trumpSuit;
    final userIsBidder = _game.highestBidder == 0 && trump != null;

    return Container(
      width: tableSize,
      height: tableSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Color(0xFF1B6638), Color(0xFF134526), Color(0xFF092B15)],
        ),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2.5),
        boxShadow: const [
          BoxShadow(
              color: Colors.black87, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: tableSize * 0.07,
            child: GestureDetector(
              onTap: () {
                if (_game.canRevealTrump(0)) {
                  _userAction(() => _game.revealTrump(0), heavy: true);
                } else if (_game.canAskTrump(0)) {
                  _userAction(() => _game.askTrump(0), heavy: true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (_game.canRevealTrump(0) || _game.canAskTrump(0))
                      ? Colors.amber.withValues(alpha: 0.25)
                      : const Color(0x88000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_game.canRevealTrump(0) || _game.canAskTrump(0))
                        ? Colors.amber
                        : Colors.amber.withValues(alpha: 0.4),
                    width: (_game.canRevealTrump(0) || _game.canAskTrump(0))
                        ? 1.5
                        : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Trump: ',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    if (_game.isTrumpRevealed && trump != null)
                      Text(
                        '${trump.symbol} ${trump.name}',
                        style: TextStyle(
                          color:
                              _isRed(trump) ? Colors.redAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    else if (_game.canRevealTrump(0) && trump != null)
                      Text(
                        '🔓 Tap to Reveal (${trump.symbol})',
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      )
                    else if (_game.canAskTrump(0))
                      const Text(
                        '❓ Tap to Ask',
                        style: TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      )
                    else
                      Text(
                        userIsBidder
                            ? '🔒 ${trump.symbol} (only you know)'
                            : '🔒 Hidden',
                        style:
                            const TextStyle(color: Colors.amber, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_game.currentTrick.isEmpty)
            Text(
              _game.phase == Card29Phase.playing
                  ? 'Trick #${_game.trickCount + 1}'
                  : '29',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            )
          else
            ..._game.currentTrick.map((play) {
              final positions = {
                0: Offset(0, offset),
                1: Offset(offset, 0),
                2: Offset(0, -offset),
                3: Offset(-offset, 0),
              };
              final isWinner = _game.phase == Card29Phase.trickComplete &&
                  _game.trickWinner == play.playerIndex;
              return Transform.translate(
                offset:
                    positions[play.playerIndex]! + Offset(0, tableSize * 0.04),
                child: _buildCardView(play.card,
                    width: cardW, height: cardH, highlighted: isWinner),
              );
            }),
        ],
      ),
    );
  }

  bool _isRed(CardSuit s) => s == CardSuit.hearts || s == CardSuit.diamonds;

  Widget _panel({required Widget child}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEE092614),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: child,
    );
  }

  Widget _buildBiddingControls() {
    final bids = [
      for (int b = _game.minimumNextBid; b <= Card29Engine.maxBid; b++) b
    ];
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _game.highestBidder == -1
                ? 'Your turn to bid'
                : 'Your turn · current bid ${_game.highestBid}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _userAction(() => _game.pass(0)),
                child: const Text('Pass'),
              ),
              for (final b in bids)
                SizedBox(
                  width: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _userAction(() => _game.placeBid(0, b)),
                    child: Text('$b',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrumpSelector() {
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Pick the secret Trump suit',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: CardSuit.values.map((s) {
              final count = _game.hands[0].where((c) => c.suit == s).length;
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor:
                      _isRed(s) ? Colors.red.shade700 : Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () =>
                    _userAction(() => _game.selectTrump(s), heavy: true),
                child: Text('${s.symbol} ${s.name} ($count)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundOverBanner() {
    final isMatchOver = _game.phase == Card29Phase.matchOver;
    final youWonMatch = _game.matchPips[0] >= Card29Game.pipsToWin;
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isMatchOver
                ? (youWonMatch
                    ? '🏆 Grand Victory! Your team won the match!'
                    : 'Match lost - the opponents reached 6 pips.')
                : _game.status,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: Icon(isMatchOver ? Icons.emoji_events : Icons.play_arrow),
            label: Text(
              isMatchOver
                  ? 'Start New Match (First to ${Card29Game.pipsToWin})'
                  : 'Next Deal',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, foregroundColor: Colors.black87),
            onPressed: isMatchOver
                ? _startNewMatch
                : () {
                    _game.startRound();
                    _afterChange();
                  },
          ),
        ],
      ),
    );
  }

  /// Reveal/Ask Trump and Pair live here, outside the table, so they never cover the trick.
  Widget _buildActionBar() {
    final canReveal = _game.canRevealTrump(0);
    final canAsk = _game.canAskTrump(0);
    final canPair = _game.canClaimRoyalty(0);
    if (!canReveal && !canAsk && !canPair) return const SizedBox(height: 6);
    final pairEffect = Card29Game.teamOf(0) == _game.bidderTeam
        ? 'target −4'
        : 'their target +4';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          if (canReveal)
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open, size: 16),
              label: const Text('Reveal Trump',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87),
              onPressed: () =>
                  _userAction(() => _game.revealTrump(0), heavy: true),
            ),
          if (canAsk)
            ElevatedButton.icon(
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text('Ask Trump',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87),
              onPressed: () =>
                  _userAction(() => _game.askTrump(0), heavy: true),
            ),
          if (canPair)
            ElevatedButton.icon(
              icon: const Icon(Icons.star, color: Colors.amber, size: 16),
              label: Text('Show Pair (K & Q) · $pairEffect',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade900,
                  foregroundColor: Colors.white),
              onPressed: () =>
                  _userAction(() => _game.claimRoyalty(0), heavy: true),
            ),
        ],
      ),
    );
  }

  Widget _buildUserHand() {
    final userHand = _game.hands[0];
    final isUserTurn = _isUserTurnToPlay;
    final legal = _game.legalCards(0);

    String turnPrompt = 'YOUR TURN - Play a card';
    if (isUserTurn &&
        _game.leadSuit != null &&
        !userHand.any((c) => c.suit == _game.leadSuit)) {
      final hasTrump = _game.trumpSuit != null &&
          userHand.any((c) => c.suit == _game.trumpSuit);
      if (_game.isTrumpRevealed && hasTrump) {
        if (_game.currentTrick.isNotEmpty) {
          final currentWinner = Card29Engine.determineTrickWinner(
            trickCards: _game.currentTrick,
            trumpSuit: _game.trumpSuit,
            isTrumpRevealed: _game.isTrumpRevealed,
          );
          if (Card29Game.teamOf(currentWinner.playerIndex) ==
              Card29Game.teamOf(0)) {
            turnPrompt = 'Partner is winning - discard or feed points! 🛡️';
          } else if (legal.any((c) => c.suit != _game.trumpSuit)) {
            turnPrompt = "Opponent's Trump is higher - you may discard! 💡";
          } else {
            turnPrompt = "You can't follow suit - you must play Trump! 👆";
          }
        } else {
          turnPrompt = "You can't follow suit - you must play Trump! 👆";
        }
      }
    }
    return Container(
      height: 128,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF092614),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  isUserTurn ? turnPrompt : 'Your Cards (South)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isUserTurn ? Colors.amber : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isUserTurn) ...[
                const SizedBox(width: 6),
                const Icon(Icons.touch_app, size: 15, color: Colors.amber),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const cardW = 50.0;
                const cardH = 74.0;
                final count = max(userHand.length, 1);
                // Overlap the cards when the full fan would not fit.
                final step = count == 1
                    ? cardW
                    : min(cardW + 6,
                        (constraints.maxWidth - cardW) / (count - 1));
                final totalWidth = cardW + step * (count - 1);
                return Center(
                  child: SizedBox(
                    width: totalWidth,
                    height: min(cardH, constraints.maxHeight),
                    child: Stack(
                      children: [
                        for (int i = 0; i < userHand.length; i++)
                          Positioned(
                            left: i * step,
                            top: 0,
                            bottom: 0,
                            child: _buildHandCard(userHand[i], isUserTurn,
                                legal.contains(userHand[i]), cardW),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandCard(
      Card29 card, bool isUserTurn, bool isLegal, double width) {
    final tappable = isUserTurn && isLegal;
    return Semantics(
      button: tappable,
      label:
          '${card.rank.code} of ${card.suit.name}${tappable ? ', playable' : ''}',
      child: GestureDetector(
        onTap:
            tappable ? () => _userAction(() => _game.playCard(0, card)) : null,
        child: Opacity(
          opacity: (isUserTurn && !isLegal) ? 0.4 : 1.0,
          child: _buildCardView(card,
              width: width, height: 74, highlighted: tappable),
        ),
      ),
    );
  }

  Widget _buildCardView(Card29 card,
      {required double width,
      required double height,
      bool highlighted = false}) {
    return ExcludeSemantics(
      child: PlayingCardView(
        rank: card.rank.code,
        suitSymbol: card.suit.symbol,
        isRed: _isRed(card.suit),
        width: width,
        height: height,
        highlighted: highlighted,
        backColor: const Color(0xFF1B5E20),
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
              Text('Point Values:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '• Jack (J) = 3 points\n• Nine (9) = 2 points\n• Ace (A) = 1 point\n• Ten (10) = 1 point\n'
                '• K, Q, 8, 7 = 0 points\n• Last trick bonus = 1 point\nTotal = 29 points',
              ),
              SizedBox(height: 12),
              Text('Bidding & Trump:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '1. Bidding goes round from the dealer\'s left, 16 up to 28. Once you pass you are out.\n'
                '2. If everyone passes, the dealer plays at 16.\n'
                '3. The highest bidder picks a secret trump suit from their first 4 cards.',
              ),
              SizedBox(height: 12),
              Text('Play:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '4. Follow the led suit if you can.\n'
                '5. If you can\'t follow suit, you may Ask Trump (or Reveal Trump if you are the bidder). You can also tap the Trump badge on the table.\n'
                '6. Once trump is revealed, anyone who can\'t follow suit must play a trump if they have one (unless their partner is winning the trick).\n'
                '7. Pair (K & Q of trump): after trump is revealed, the holder may show it. It lowers the bidding '
                'team\'s target by 4, or raises it by 4 if the opponents hold it.\n'
                '8. The bidding team needs points ≥ its target to win the deal; otherwise the opponents win it.\n'
                '9. Each deal won is 1 pip. First team to 6 pips wins the match.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))
        ],
      ),
    );
  }
}
