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
    return CardSuit.values.firstWhere((s) => s.code == code, orElse: () => CardSuit.spades);
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
    return CardRank.values.firstWhere((r) => r.code == code, orElse: () => CardRank.seven);
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
  final int playerIndex; // 0: South (User), 1: East, 2: North (Partner), 3: West
  final Card29 card;

  const PlayedCard({required this.playerIndex, required this.card});
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
    int highestTrumpPower = (isTrumpRevealed && leadCard.suit == trumpSuit) ? leadCard.power : -1;

    for (int i = 1; i < trickCards.length; i++) {
      final play = trickCards[i];
      final card = play.card;

      if (isTrumpRevealed && trumpSuit != null && card.suit == trumpSuit) {
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

  /// Validates whether a card can be legally played according to 29 rules.
  static bool isCardLegal({
    required Card29 card,
    required List<Card29> hand,
    required CardSuit? leadSuit,
    required bool isTrumpRevealed,
  }) {
    if (!hand.contains(card)) return false;
    if (leadSuit == null) return true; // First card in trick can be any card

    final hasLeadSuit = hand.any((c) => c.suit == leadSuit);
    if (hasLeadSuit) {
      // Must follow suit if player has lead suit
      return card.suit == leadSuit;
    }

    // If player does not have lead suit, any card can be played (trumping or discarding)
    return true;
  }
}
