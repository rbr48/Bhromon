import 'dart:math';

enum CardSuit {
  spades('S', '♠', 'Spades'),
  hearts('H', '♥', 'Hearts'),
  diamonds('D', '♦', 'Diamonds'),
  clubs('C', '♣', 'Clubs');

  final String code;
  final String symbol;
  final String name;

  const CardSuit(this.code, this.symbol, this.name);

  static CardSuit fromCode(String code) {
    return CardSuit.values
        .firstWhere((s) => s.code == code, orElse: () => CardSuit.spades);
  }
}

enum CardRank {
  jack('J', 3, 8),
  nine('9', 2, 7),
  ace('A', 1, 6),
  ten('10', 1, 5),
  king('K', 0, 4),
  queen('Q', 0, 3),
  eight('8', 0, 2),
  seven('7', 0, 1);

  final String code;
  final int points;
  final int power; // Higher beats lower in a trick

  const CardRank(this.code, this.points, this.power);

  static CardRank fromCode(String code) {
    return CardRank.values
        .firstWhere((r) => r.code == code, orElse: () => CardRank.seven);
  }
}

class Card29 {
  final CardSuit suit;
  final CardRank rank;

  const Card29({required this.suit, required this.rank});

  String get code => '${rank.code}${suit.code}';
  int get points => rank.points;
  int get power => rank.power;

  static Card29 fromCode(String code) {
    final sCode = code.substring(code.length - 1).toUpperCase();
    final rCode = code.substring(0, code.length - 1).toUpperCase();
    return Card29(
      suit: CardSuit.fromCode(sCode),
      rank: CardRank.fromCode(rCode),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Card29 && runtimeType == other.runtimeType && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

class PlayedCard {
  final int
      playerIndex; // 0: South (User), 1: East, 2: North (Partner), 3: West
  final Card29 card;

  /// Whether trump was already revealed when this card was played. A card of
  /// the hidden trump suit discarded before the reveal is an ordinary card.
  final bool trumpEligible;

  const PlayedCard(
      {required this.playerIndex,
      required this.card,
      this.trumpEligible = true});
}

class Card29Engine {
  static const int totalPoints = 28; // Plus 1 for last trick = 29
  static const int minBid = 16;
  static const int maxBid = 28;

  /// Creates a standard 32-card 29 deck.
  static List<Card29> createDeck() {
    final deck = <Card29>[];
    for (final s in CardSuit.values) {
      for (final r in CardRank.values) {
        deck.add(Card29(suit: s, rank: r));
      }
    }
    deck.shuffle(Random());
    return deck;
  }

  /// Determines the winner of a trick among played cards.
  static PlayedCard determineTrickWinner({
    required List<PlayedCard> trickCards,
    CardSuit? trumpSuit,
    bool isTrumpRevealed = false,
  }) {
    if (trickCards.isEmpty) throw ArgumentError('Empty trick cards');

    final leadCard = trickCards.first.card;
    PlayedCard bestPlay = trickCards.first;

    // Cards of the led suit always compare by rank; other trump-suit cards
    // only trump if they were played after the reveal.
    bool countsAsTrump(PlayedCard play) =>
        isTrumpRevealed &&
        trumpSuit != null &&
        play.card.suit == trumpSuit &&
        (play.trumpEligible || play.card.suit == leadCard.suit);

    int highestTrumpPower =
        countsAsTrump(trickCards.first) ? leadCard.power : -1;

    for (int i = 1; i < trickCards.length; i++) {
      final play = trickCards[i];
      final card = play.card;

      if (countsAsTrump(play)) {
        if (card.power > highestTrumpPower) {
          highestTrumpPower = card.power;
          bestPlay = play;
        }
      } else if (highestTrumpPower == -1 && card.suit == leadCard.suit) {
        if (card.power > bestPlay.card.power) {
          bestPlay = play;
        }
      }
    }

    return bestPlay;
  }

  /// Checks if a player's hand contains Royalty (King and Queen of the Trump suit).
  static bool hasRoyalty(List<Card29> hand, CardSuit? trumpSuit) {
    if (trumpSuit == null) return false;
    final hasKing =
        hand.any((c) => c.suit == trumpSuit && c.rank == CardRank.king);
    final hasQueen =
        hand.any((c) => c.suit == trumpSuit && c.rank == CardRank.queen);
    return hasKing && hasQueen;
  }

  /// Validates whether a card can be legally played according to 29 rules.
  static bool isCardLegal({
    required Card29 card,
    required List<Card29> hand,
    required CardSuit? leadSuit,
    required bool isTrumpRevealed,
    CardSuit? trumpSuit,
    bool mustPlayTrumpIfHeld = false,
    int? minTrumpPowerToBeat,
  }) {
    if (!hand.contains(card)) return false;
    if (leadSuit == null) return true; // First card in trick can be any card

    final hasLeadSuit = hand.any((c) => c.suit == leadSuit);
    if (hasLeadSuit) {
      // Must follow suit if player has lead suit
      return card.suit == leadSuit;
    }

    // If player cannot follow suit and trump is revealed:
    if (isTrumpRevealed && trumpSuit != null && mustPlayTrumpIfHeld) {
      if (minTrumpPowerToBeat != null) {
        // Opponent is winning with a trump. Player is only forced to trump
        // if they hold a HIGHER trump that can beat the opponent (over-trump).
        // If they only hold lower trumps, forced under-trumping is NOT required:
        // they may discard any card in hand.
        final canOverTrump = hand
            .any((c) => c.suit == trumpSuit && c.power > minTrumpPowerToBeat);
        if (canOverTrump) {
          return card.suit == trumpSuit && card.power > minTrumpPowerToBeat;
        }
      } else {
        // Opponent is winning with a non-trump card. Any trump beats it.
        final hasTrump = hand.any((c) => c.suit == trumpSuit);
        if (hasTrump) {
          return card.suit == trumpSuit;
        }
      }
    }

    // If player does not have lead suit (and no trump restriction), any card can be played
    return true;
  }

  /// Cards [player] may play from [hand] in the current position. The bidder
  /// may not lead the hidden trump suit. Otherwise a player who cannot follow
  /// suit must trump when an opponent is winning with trump or the trick is
  /// winning on a plain card, unless their partner is winning or they cannot
  /// beat the opponent's trump. The server and the table both use this rule.
  static List<Card29> legalPlays({
    required List<Card29> hand,
    required int player,
    required int highestBidder,
    required CardSuit? leadSuit,
    required List<PlayedCard> trick,
    required CardSuit? trumpSuit,
    required bool isTrumpRevealed,
  }) {
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
    if (isTrumpRevealed && trick.isNotEmpty) {
      final currentWinner = determineTrickWinner(
        trickCards: trick,
        trumpSuit: trumpSuit,
        isTrumpRevealed: isTrumpRevealed,
      );
      if (currentWinner.playerIndex % 2 == player % 2) {
        mustTrump = false;
      } else {
        // Opponent is winning the trick. Check if the winning card counts as trump.
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
        .where((c) => isCardLegal(
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
}
