import 'dart:math';

import 'card29_engine.dart';

enum Card29Phase {
  bidding,
  trumpSelection,
  playing,
  trickComplete,
  roundOver,
  matchOver
}

/// Rules and table state for a 4-player game of 29. Seat 0 is you (South),
/// 2 is your bot partner (North); 1 (East) and 3 (West) are the opponents.
///
/// - Bidding goes clockwise from the dealer's left, 16 to 28; a pass is final.
///   If everyone passes the dealer must play at 16.
/// - The bidder secretly picks trump from their first four cards.
/// - Follow the led suit when you can. A player who can't may ask for trump;
///   once trump is revealed, a player who can't follow suit must play trump if
///   they hold any. The bidder reveals trump by playing it while void.
/// - The bidder may not lead the hidden trump suit unless it is all they hold.
/// - Pair (K + Q of trump): once trump is revealed the holder may show it. It
///   lowers the bid target by 4 for the bidding team, or raises it by 4 when
///   the opponents hold it (target stays within 16-28).
/// - Card points: J 3, 9 2, A 1, 10 1, plus 1 for the last trick (29 total).
/// - The team that wins the deal gets a pip; first to [pipsToWin] wins.
class Card29Game {
  static const int pipsToWin = 6;
  static const List<String> playerNames = [
    'You',
    'East (Bot)',
    'North (Partner)',
    'West (Bot)'
  ];

  Card29Game({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<List<Card29>> hands = List.generate(4, (_) => <Card29>[]);
  List<Card29> _deck = [];

  Card29Phase phase = Card29Phase.roundOver;
  int dealer = 3;
  int currentTurn = 0;

  int highestBid = 15;
  int highestBidder = -1;
  final Set<int> passed = {};

  CardSuit? trumpSuit;
  bool isTrumpRevealed = false;
  int trumpRevealedBy = -1;

  bool royaltyClaimed = false;
  int royaltyClaimedBy = -1;

  /// Points the bidding team must reach (the bid, adjusted by a shown pair).
  int bidTarget = 0;

  final List<PlayedCard> currentTrick = [];
  CardSuit? leadSuit;
  int? trickWinner;
  final List<Card29> playedCards = [];

  final List<int> teamPoints = [0, 0];
  final List<int> matchPips = [0, 0];
  int trickCount = 0;
  String status = 'Welcome to 29!';
  bool _started = false;

  static int teamOf(int player) => player % 2;

  bool get hasStarted => _started;
  int get bidderTeam => teamOf(highestBidder);
  bool get isRoundInProgress =>
      _started &&
      phase != Card29Phase.roundOver &&
      phase != Card29Phase.matchOver;

  String nameOf(int player) => playerNames[player];

  /// Starts the next deal (or a new match after one has finished).
  void startRound() {
    if (phase == Card29Phase.matchOver) {
      matchPips[0] = 0;
      matchPips[1] = 0;
    }
    _started = true;
    _deck = Card29Engine.createDeck()..shuffle(_random);
    for (int i = 0; i < 4; i++) {
      hands[i]
        ..clear()
        ..addAll(_deck.sublist(i * 4, (i + 1) * 4));
      _sortHand(hands[i]);
    }

    dealer = (dealer + 1) % 4;
    currentTurn = (dealer + 1) % 4;
    phase = Card29Phase.bidding;
    highestBid = 15;
    highestBidder = -1;
    passed.clear();
    trumpSuit = null;
    isTrumpRevealed = false;
    trumpRevealedBy = -1;
    royaltyClaimed = false;
    royaltyClaimedBy = -1;
    bidTarget = 0;
    currentTrick.clear();
    leadSuit = null;
    trickWinner = null;
    playedCards.clear();
    teamPoints[0] = 0;
    teamPoints[1] = 0;
    trickCount = 0;
    status = currentTurn == 0
        ? '${nameOf(dealer)} dealt. Your bid: ${Card29Engine.minBid}-${Card29Engine.maxBid} or Pass.'
        : '${nameOf(dealer)} dealt. ${nameOf(currentTurn)} opens the bidding.';
  }

  /// Clears the match score and deals a fresh first hand.
  void newMatch() {
    matchPips[0] = 0;
    matchPips[1] = 0;
    dealer = 3;
    phase = Card29Phase.roundOver;
    startRound();
  }

  void _sortHand(List<Card29> hand) {
    hand.sort((a, b) {
      if (a.suit != b.suit) return a.suit.index.compareTo(b.suit.index);
      return b.power.compareTo(a.power);
    });
  }

  // --- BIDDING ---

  int get minimumNextBid => max(Card29Engine.minBid, highestBid + 1);

  bool canBid(int player, int bid) =>
      phase == Card29Phase.bidding &&
      currentTurn == player &&
      !passed.contains(player) &&
      bid >= minimumNextBid &&
      bid <= Card29Engine.maxBid;

  bool placeBid(int player, int bid) {
    if (!canBid(player, bid)) return false;
    highestBid = bid;
    highestBidder = player;
    status = player == 0 ? 'You bid $bid.' : '${nameOf(player)} bids $bid.';
    _advanceBidding();
    return true;
  }

  bool pass(int player) {
    if (phase != Card29Phase.bidding ||
        currentTurn != player ||
        passed.contains(player)) {
      return false;
    }
    passed.add(player);
    status = player == 0 ? 'You pass.' : '${nameOf(player)} passes.';
    _advanceBidding();
    return true;
  }

  void _advanceBidding() {
    if (highestBidder == -1 && passed.length == 4) {
      highestBidder = dealer;
      highestBid = Card29Engine.minBid;
      status =
          'Everyone passed - ${nameOf(dealer)} (dealer) must play at ${Card29Engine.minBid}.';
      _finishBidding();
      return;
    }
    if (highestBidder != -1 &&
        (passed.length >= 3 || highestBid >= Card29Engine.maxBid)) {
      _finishBidding();
      return;
    }
    do {
      currentTurn = (currentTurn + 1) % 4;
    } while (passed.contains(currentTurn));
  }

  void _finishBidding() {
    bidTarget = highestBid;
    currentTurn = highestBidder;
    if (highestBidder == 0) {
      phase = Card29Phase.trumpSelection;
      status = 'You won the bid at $highestBid! Pick the secret trump suit.';
    } else {
      trumpSuit = Card29Bot.chooseTrump(hands[highestBidder]);
      status =
          '${nameOf(highestBidder)} won the bid at $highestBid and set a secret trump.';
      _dealSecondHalf();
    }
  }

  bool selectTrump(CardSuit suit) {
    if (phase != Card29Phase.trumpSelection) return false;
    trumpSuit = suit;
    status = 'Trump set. ';
    _dealSecondHalf();
    return true;
  }

  void _dealSecondHalf() {
    for (int i = 0; i < 4; i++) {
      hands[i].addAll(_deck.sublist(16 + i * 4, 16 + (i + 1) * 4));
      _sortHand(hands[i]);
    }
    phase = Card29Phase.playing;
    currentTurn = highestBidder;
    status =
        '${status.trim()} ${highestBidder == 0 ? 'You lead' : '${nameOf(highestBidder)} leads'} the first trick.';
  }

  // --- PLAY ---

  bool _isVoidInLead(int player) =>
      leadSuit != null && !hands[player].any((c) => c.suit == leadSuit);

  /// Cards [player] may play right now (empty if it is not their turn).
  List<Card29> legalCards(int player) {
    if (phase != Card29Phase.playing || currentTurn != player) return const [];
    final hand = hands[player];
    if (leadSuit == null) {
      if (!isTrumpRevealed && player == highestBidder) {
        final nonTrump = hand.where((c) => c.suit != trumpSuit).toList();
        if (nonTrump.isNotEmpty) return nonTrump;
      }
      return List.of(hand);
    }
    // If trump is revealed and the player is void in the led suit, they must
    // play trump to win the trick from an opponent. However:
    // 1. If their partner is already winning the current trick, the player
    //    is not forced to trump (Partnership Immunity).
    // 2. If an opponent is winning with a trump that is higher than any trump
    //    held by the player, the player is not forced to under-trump.
    bool mustTrump = true;
    int? minTrumpPowerToBeat;
    if (isTrumpRevealed && currentTrick.isNotEmpty) {
      final currentWinner = Card29Engine.determineTrickWinner(
        trickCards: currentTrick,
        trumpSuit: trumpSuit,
        isTrumpRevealed: isTrumpRevealed,
      );
      if (teamOf(currentWinner.playerIndex) == teamOf(player)) {
        mustTrump = false;
      } else {
        // Opponent is winning the trick.
        // Check if the opponent's winning card counts as trump.
        final winningCard = currentWinner.card;
        final bool winningCardIsTrump = trumpSuit != null &&
            winningCard.suit == trumpSuit &&
            (currentWinner.trumpEligible || winningCard.suit == leadSuit);
        if (winningCardIsTrump) {
          minTrumpPowerToBeat = winningCard.power;
        }
      }
    }

    return hand
        .where((c) => Card29Engine.isCardLegal(
              card: c,
              hand: hand,
              leadSuit: leadSuit,
              isTrumpRevealed: isTrumpRevealed,
              trumpSuit: trumpSuit,
              mustPlayTrumpIfHeld: mustTrump,
              minTrumpPowerToBeat: minTrumpPowerToBeat,
            ))
        .toList();
  }

  /// Players who can't follow suit may ask for trump (the bidder already knows it).
  bool canAskTrump(int player) =>
      phase == Card29Phase.playing &&
      currentTurn == player &&
      !isTrumpRevealed &&
      player != highestBidder &&
      _isVoidInLead(player);

  bool askTrump(int player) {
    if (!canAskTrump(player)) return false;
    _reveal(player, asked: true);
    return true;
  }

  /// The bidder can reveal the secret trump when they cannot follow the led suit.
  bool canRevealTrump(int player) =>
      phase == Card29Phase.playing &&
      currentTurn == player &&
      !isTrumpRevealed &&
      player == highestBidder &&
      _isVoidInLead(player);

  bool revealTrump(int player) {
    if (!canRevealTrump(player)) return false;
    _reveal(player, asked: false);
    return true;
  }

  void _reveal(int player, {required bool asked}) {
    isTrumpRevealed = true;
    trumpRevealedBy = player;
    final suit = '${trumpSuit!.symbol} ${trumpSuit!.name}';
    status = asked
        ? '${player == 0 ? 'You' : nameOf(player)} asked for trump: $suit!'
        : '${player == 0 ? 'You' : nameOf(player)} revealed trump: $suit!';
  }

  bool canClaimRoyalty(int player) =>
      (phase == Card29Phase.playing || phase == Card29Phase.trickComplete) &&
      isTrumpRevealed &&
      !royaltyClaimed &&
      Card29Engine.hasRoyalty(hands[player], trumpSuit);

  bool claimRoyalty(int player) {
    if (!canClaimRoyalty(player)) return false;
    royaltyClaimed = true;
    royaltyClaimedBy = player;
    final who = player == 0 ? 'You show' : '${nameOf(player)} shows';
    if (teamOf(player) == bidderTeam) {
      bidTarget = max(Card29Engine.minBid, bidTarget - 4);
      status =
          '$who the Pair (K & Q of trump)! Bidding team target drops to $bidTarget.';
    } else {
      bidTarget = min(Card29Engine.maxBid, bidTarget + 4);
      status =
          '$who the Pair (K & Q of trump)! Bidding team target rises to $bidTarget.';
    }
    return true;
  }

  bool playCard(int player, Card29 card) {
    if (!legalCards(player).contains(card)) return false;

    if (!isTrumpRevealed &&
        player == highestBidder &&
        card.suit == trumpSuit &&
        _isVoidInLead(player)) {
      _reveal(player, asked: false);
    }

    hands[player].remove(card);
    playedCards.add(card);
    currentTrick.add(PlayedCard(
        playerIndex: player, card: card, trumpEligible: isTrumpRevealed));
    leadSuit ??= card.suit;

    if (currentTrick.length == 4) {
      trickWinner = Card29Engine.determineTrickWinner(
        trickCards: currentTrick,
        trumpSuit: trumpSuit,
        isTrumpRevealed: isTrumpRevealed,
      ).playerIndex;
      phase = Card29Phase.trickComplete;
      final pts = currentTrick.fold<int>(0, (s, p) => s + p.card.points) +
          (trickCount == 7 ? 1 : 0);
      status =
          '${trickWinner == 0 ? 'You win' : '${nameOf(trickWinner!)} wins'} the trick (+$pts pts).';
    } else {
      currentTurn = (player + 1) % 4;
    }
    return true;
  }

  /// Collects the finished trick. The UI calls this after showing it briefly.
  void resolveTrick() {
    if (phase != Card29Phase.trickComplete) return;
    final winner = trickWinner!;
    var pts = currentTrick.fold<int>(0, (s, p) => s + p.card.points);
    trickCount++;
    if (trickCount == 8) pts += 1; // last trick bonus
    teamPoints[teamOf(winner)] += pts;

    currentTrick.clear();
    leadSuit = null;
    trickWinner = null;
    currentTurn = winner;

    if (trickCount == 8) {
      _finishRound();
    } else {
      phase = Card29Phase.playing;
    }
  }

  void _finishRound() {
    final team = bidderTeam;
    final score = teamPoints[team];
    final made = score >= bidTarget;
    final winningTeam = made ? team : 1 - team;
    matchPips[winningTeam]++;

    final bidders = team == 0 ? 'Your team' : 'Opponents';
    if (made) {
      status =
          '$bidders made the bid ($score/$bidTarget). +1 pip to ${team == 0 ? 'your team' : 'the opponents'}.';
    } else {
      status =
          '$bidders fell short ($score/$bidTarget). +1 pip to ${team == 0 ? 'the opponents' : 'your team'}.';
    }
    phase = matchPips.any((p) => p >= pipsToWin)
        ? Card29Phase.matchOver
        : Card29Phase.roundOver;
  }

  // --- BOTS ---

  /// Plays one action (bid, pass, or ask/claim/play) for the bot whose turn it is.
  void playBotTurn() {
    final p = currentTurn;
    if (p == 0) return;

    if (phase == Card29Phase.bidding) {
      final limit = Card29Bot.bidLimit(hands[p]);
      final next = minimumNextBid;
      final partnerHolds =
          highestBidder != -1 && teamOf(highestBidder) == teamOf(p);
      if (next <= limit && (!partnerHolds || limit >= next + 2)) {
        placeBid(p, next);
      } else {
        pass(p);
      }
      return;
    }

    if (phase != Card29Phase.playing) return;
    if (canClaimRoyalty(p)) claimRoyalty(p);
    if (canAskTrump(p) && Card29Bot.shouldAskTrump(this, p, _random)) {
      askTrump(p);
    }
    playCard(p, Card29Bot.chooseCard(this, p));
    if (canClaimRoyalty(p)) claimRoyalty(p);
  }
}

/// Heuristic bot used for East, North (your partner) and West.
class Card29Bot {
  static const Map<CardRank, double> _bidWeights = {
    CardRank.jack: 3,
    CardRank.nine: 2,
    CardRank.ace: 1.2,
    CardRank.ten: 1,
    CardRank.king: 0.4,
    CardRank.queen: 0.3,
  };

  /// Highest bid the bot is willing to make with its first four cards.
  static int bidLimit(List<Card29> hand) {
    var strength = 0.0;
    final counts = <CardSuit, int>{};
    for (final c in hand) {
      strength += _bidWeights[c.rank] ?? 0;
      counts[c.suit] = (counts[c.suit] ?? 0) + 1;
    }
    strength += counts.values.fold<int>(0, max).toDouble();
    return (13 + strength * 1.2).round().clamp(15, Card29Engine.maxBid);
  }

  static CardSuit chooseTrump(List<Card29> hand) {
    CardSuit best = hand.first.suit;
    var bestScore = double.negativeInfinity;
    for (final suit in CardSuit.values) {
      final cards = hand.where((c) => c.suit == suit);
      if (cards.isEmpty) continue;
      final score = cards.length * 2.0 +
          cards.fold<double>(0, (s, c) => s + c.points + c.power / 10);
      if (score > bestScore) {
        bestScore = score;
        best = suit;
      }
    }
    return best;
  }

  /// No unplayed card of the same suit outranks [card] outside the bot's own hand.
  static bool isMaster(Card29Game g, int player, Card29 card) {
    for (final rank in CardRank.values) {
      if (rank.power <= card.power) continue;
      final higher = Card29(suit: card.suit, rank: rank);
      if (!g.playedCards.contains(higher) &&
          !g.hands[player].contains(higher)) {
        return false;
      }
    }
    return true;
  }

  static int _trickPoints(Card29Game g) =>
      g.currentTrick.fold<int>(0, (s, p) => s + p.card.points);

  static PlayedCard _currentWinner(Card29Game g) =>
      Card29Engine.determineTrickWinner(
        trickCards: g.currentTrick,
        trumpSuit: g.trumpSuit,
        isTrumpRevealed: g.isTrumpRevealed,
      );

  /// Would [card] from [player] take the lead in the current trick?
  static bool _wouldWin(Card29Game g, int player, Card29 card) {
    final reveals = !g.isTrumpRevealed &&
        player == g.highestBidder &&
        card.suit == g.trumpSuit &&
        g.leadSuit != null &&
        !g.hands[player].any((c) => c.suit == g.leadSuit);
    final revealed = g.isTrumpRevealed || reveals;
    final trick = [
      ...g.currentTrick,
      PlayedCard(playerIndex: player, card: card, trumpEligible: revealed),
    ];
    return Card29Engine.determineTrickWinner(
                trickCards: trick,
                trumpSuit: g.trumpSuit,
                isTrumpRevealed: revealed)
            .playerIndex ==
        player;
  }

  static bool shouldAskTrump(Card29Game g, int player, Random random) {
    final winner = _currentWinner(g);
    if (Card29Game.teamOf(winner.playerIndex) == Card29Game.teamOf(player)) {
      return false;
    }
    return _trickPoints(g) >= 1 ||
        g.currentTrick.length == 3 ||
        random.nextDouble() < 0.3;
  }

  static Card29 chooseCard(Card29Game g, int player) {
    final legal = g.legalCards(player);
    if (legal.length == 1) return legal.first;

    final hidingTrump = !g.isTrumpRevealed && player == g.highestBidder;

    // Lowest-value card, keeping the hidden trump suit back when we know it.
    Card29 cheapest(Iterable<Card29> cards) {
      final pool = hidingTrump && cards.any((c) => c.suit != g.trumpSuit)
          ? cards.where((c) => c.suit != g.trumpSuit)
          : cards;
      return pool.reduce((a, b) {
        if (a.points != b.points) return a.points < b.points ? a : b;
        return a.power <= b.power ? a : b;
      });
    }

    if (g.currentTrick.isEmpty) {
      final ownTeamBid = Card29Game.teamOf(player) == g.bidderTeam;
      final trumps = legal.where((c) => c.suit == g.trumpSuit).toList();
      if (g.isTrumpRevealed && ownTeamBid && trumps.length >= 3) {
        // Draw out the opponents' trumps.
        return trumps.reduce((a, b) => a.power >= b.power ? a : b);
      }
      // (The bidder's legal leads already exclude the hidden trump suit.)
      final masters = legal.where((c) => isMaster(g, player, c)).toList();
      if (masters.isNotEmpty) {
        return masters.reduce((a, b) => a.points >= b.points ? a : b);
      }
      // Lead low from the longest side suit.
      final counts = <CardSuit, int>{};
      for (final c in legal) {
        counts[c.suit] = (counts[c.suit] ?? 0) + 1;
      }
      final sideCards = legal
          .where((c) => c.suit != g.trumpSuit || !g.isTrumpRevealed)
          .toList();
      final pool = sideCards.isEmpty ? legal : sideCards;
      final longest = pool.map((c) => counts[c.suit]!).reduce(max);
      return cheapest(pool.where((c) => counts[c.suit] == longest));
    }

    final winner = _currentWinner(g);
    final partnerWinning =
        Card29Game.teamOf(winner.playerIndex) == Card29Game.teamOf(player);
    final isLast = g.currentTrick.length == 3;

    if (partnerWinning) {
      final partnerSafe = isLast || isMaster(g, player, winner.card);
      if (partnerSafe) {
        // Feed points to the partner's trick.
        final feedable = hidingTrump
            ? legal.where((c) => c.suit != g.trumpSuit).toList()
            : legal;
        final pool = feedable.isEmpty ? legal : feedable;
        return pool.reduce((a, b) {
          if (a.points != b.points) return a.points > b.points ? a : b;
          return a.power <= b.power ? a : b;
        });
      }
      return cheapest(legal);
    }

    final winners = legal.where((c) => _wouldWin(g, player, c)).toList();
    if (winners.isNotEmpty) {
      final cheapestWinner =
          winners.reduce((a, b) => a.power <= b.power ? a : b);
      if (isLast ||
          _trickPoints(g) > 0 ||
          isMaster(g, player, cheapestWinner) ||
          cheapestWinner.points > 0) {
        return cheapestWinner;
      }
    }
    return cheapest(legal);
  }
}
