import 'dart:math';

enum TeenPattiHandType {
  highCard(1, 'হাই কার্ড (High Card)'),
  pair(2, 'জোড়া (Pair)'),
  color(3, 'কালার (Flush)'),
  sequence(4, 'সাধারণ রান (Sequence)'),
  pureSequence(5, 'পিওর সিকোয়েন্স (Pure Run)'),
  trail(6, 'ট্রিও / ট্রেল (Trio / Trail)');

  final int score;
  final String banglaName;

  const TeenPattiHandType(this.score, this.banglaName);
}

class TeenPattiCard {
  final String rank; // '2'-'10', 'J', 'Q', 'K', 'A'
  final String suit; // 'S', 'H', 'D', 'C'
  final int value; // 2..14 (A=14)

  const TeenPattiCard(
      {required this.rank, required this.suit, required this.value});

  String get code => '$rank$suit';

  String get suitSymbol {
    switch (suit) {
      case 'S':
        return '♠';
      case 'H':
        return '♥';
      case 'D':
        return '♦';
      case 'C':
        return '♣';
      default:
        return suit;
    }
  }

  static TeenPattiCard fromCode(String code) {
    final s = code.substring(code.length - 1).toUpperCase();
    final r = code.substring(0, code.length - 1).toUpperCase();
    int val = 0;
    if (r == 'A') {
      val = 14;
    } else if (r == 'K') {
      val = 13;
    } else if (r == 'Q') {
      val = 12;
    } else if (r == 'J') {
      val = 11;
    } else {
      val = int.tryParse(r) ?? 2;
    }

    return TeenPattiCard(rank: r, suit: s, value: val);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeenPattiCard &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

class HandEvaluation {
  final TeenPattiHandType handType;
  final int primaryValue;
  final int secondaryValue;
  final int kickerValue;

  const HandEvaluation({
    required this.handType,
    required this.primaryValue,
    this.secondaryValue = 0,
    this.kickerValue = 0,
  });

  /// Compares this hand evaluation with other: >0 means this wins, <0 means other wins.
  int compareTo(HandEvaluation other) {
    if (handType.score != other.handType.score) {
      return handType.score.compareTo(other.handType.score);
    }
    if (primaryValue != other.primaryValue) {
      return primaryValue.compareTo(other.primaryValue);
    }
    if (secondaryValue != other.secondaryValue) {
      return secondaryValue.compareTo(other.secondaryValue);
    }
    return kickerValue.compareTo(other.kickerValue);
  }
}

class TeenPattiEngine {
  static List<TeenPattiCard> createDeck() {
    const suits = ['S', 'H', 'D', 'C'];
    const ranks = [
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'J',
      'Q',
      'K',
      'A'
    ];
    final deck = <TeenPattiCard>[];
    for (final s in suits) {
      for (final r in ranks) {
        deck.add(TeenPattiCard.fromCode('$r$s'));
      }
    }
    deck.shuffle(Random());
    return deck;
  }

  static HandEvaluation evaluateHand(List<TeenPattiCard> cards) {
    if (cards.length != 3) {
      throw ArgumentError('A Teen Patti hand must contain exactly 3 cards');
    }

    // Sort descending by card value
    final sorted = List<TeenPattiCard>.from(cards)
      ..sort((a, b) => b.value.compareTo(a.value));

    final v1 = sorted[0].value;
    final v2 = sorted[1].value;
    final v3 = sorted[2].value;

    final isFlush =
        sorted[0].suit == sorted[1].suit && sorted[1].suit == sorted[2].suit;

    // 1. Trail / Trio (Three of a Kind)
    if (v1 == v2 && v2 == v3) {
      return HandEvaluation(
          handType: TeenPattiHandType.trail, primaryValue: v1);
    }

    // Check Sequence (Straight)
    // A-K-Q is the highest run (14), then K-Q-J (13) and so on down to 4-3-2 (4).
    // A-2-3 plays the ace low, so it is the lowest run of all (3).
    bool isStandardSeq = (v1 - v2 == 1 && v2 - v3 == 1);
    bool isA23Seq = (v1 == 14 && v2 == 3 && v3 == 2);

    if (isStandardSeq || isA23Seq) {
      final seqRank = isA23Seq ? 3 : v1;
      if (isFlush) {
        return HandEvaluation(
            handType: TeenPattiHandType.pureSequence, primaryValue: seqRank);
      } else {
        return HandEvaluation(
            handType: TeenPattiHandType.sequence, primaryValue: seqRank);
      }
    }

    // 4. Color / Flush
    if (isFlush) {
      return HandEvaluation(
        handType: TeenPattiHandType.color,
        primaryValue: v1,
        secondaryValue: v2,
        kickerValue: v3,
      );
    }

    // 5. Pair
    if (v1 == v2) {
      return HandEvaluation(
        handType: TeenPattiHandType.pair,
        primaryValue: v1,
        kickerValue: v3,
      );
    } else if (v2 == v3) {
      return HandEvaluation(
        handType: TeenPattiHandType.pair,
        primaryValue: v2,
        kickerValue: v1,
      );
    } else if (v1 == v3) {
      return HandEvaluation(
        handType: TeenPattiHandType.pair,
        primaryValue: v1,
        kickerValue: v2,
      );
    }

    // 6. High Card
    return HandEvaluation(
      handType: TeenPattiHandType.highCard,
      primaryValue: v1,
      secondaryValue: v2,
      kickerValue: v3,
    );
  }

  static int compareHands(
      List<TeenPattiCard> handA, List<TeenPattiCard> handB) {
    final evalA = evaluateHand(handA);
    final evalB = evaluateHand(handB);
    return evalA.compareTo(evalB);
  }
}
