import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/game_zone/card29/card29_engine.dart';

void main() {
  group('Card29Engine', () {
    test('Deck creation has exactly 32 cards with correct point sum', () {
      final deck = Card29Engine.createDeck();
      expect(deck.length, equals(32));

      final totalPoints = deck.fold<int>(0, (sum, c) => sum + c.points);
      expect(totalPoints, equals(28)); // Total points in 29 deck is 28
    });

    test('Trick winner without trump follows highest lead suit card', () {
      final trick = [
        PlayedCard(playerIndex: 0, card: Card29.fromCode('10S')), // Power: 5
        PlayedCard(playerIndex: 1, card: Card29.fromCode('AS')), // Power: 6
        PlayedCard(playerIndex: 2, card: Card29.fromCode('9S')), // Power: 7
        PlayedCard(playerIndex: 3, card: Card29.fromCode('KS')), // Power: 4
      ];

      final winner = Card29Engine.determineTrickWinner(trickCards: trick);
      expect(winner.playerIndex, equals(2)); // 9S has power 7
    });

    test('Trump card beats higher non-trump card when trump is revealed', () {
      final trick = [
        PlayedCard(
            playerIndex: 0,
            card: Card29.fromCode('JS')), // Jack of Spades (Lead suit)
        PlayedCard(
            playerIndex: 1, card: Card29.fromCode('7H')), // 7 of Hearts (Trump)
        PlayedCard(playerIndex: 2, card: Card29.fromCode('AS')),
        PlayedCard(
            playerIndex: 3,
            card: Card29.fromCode('8H')), // 8 of Hearts (Higher trump)
      ];

      final winner = Card29Engine.determineTrickWinner(
        trickCards: trick,
        trumpSuit: CardSuit.hearts,
        isTrumpRevealed: true,
      );

      expect(winner.playerIndex, equals(3)); // 8H is highest trump
    });

    test('isCardLegal enforces following suit', () {
      final hand = [
        Card29.fromCode('JS'),
        Card29.fromCode('9H'),
        Card29.fromCode('AD'),
      ];

      // If lead suit is Spades, player has JS, so they MUST play Spades
      expect(
          Card29Engine.isCardLegal(
            card: Card29.fromCode('JS'),
            hand: hand,
            leadSuit: CardSuit.spades,
            isTrumpRevealed: true,
          ),
          isTrue);

      expect(
          Card29Engine.isCardLegal(
            card: Card29.fromCode('9H'),
            hand: hand,
            leadSuit: CardSuit.spades,
            isTrumpRevealed: true,
          ),
          isFalse);
    });

    test(
        'isCardLegal does not force under-trump if player cannot beat winning trump',
        () {
      final hand = [
        Card29.fromCode('8D'), // Trump, power 2
        Card29.fromCode('9S'), // Off-suit
        Card29.fromCode('AC'), // Off-suit
      ];

      // Opponent winning with King of Diamonds (power 4). Hand only has 8D (power 2).
      // Player is NOT forced to play 8D because they cannot beat KD.
      expect(
        Card29Engine.isCardLegal(
          card: Card29.fromCode('9S'),
          hand: hand,
          leadSuit: CardSuit.hearts,
          isTrumpRevealed: true,
          trumpSuit: CardSuit.diamonds,
          mustPlayTrumpIfHeld: true,
          minTrumpPowerToBeat: 4, // KD power
        ),
        isTrue,
      );

      // If player has a higher trump (e.g. JD, power 8), they MUST over-trump
      final handWithHigher = [
        Card29.fromCode('JD'), // Trump, power 8
        Card29.fromCode('8D'), // Trump, power 2
        Card29.fromCode('9S'), // Off-suit
      ];

      expect(
        Card29Engine.isCardLegal(
          card: Card29.fromCode('9S'),
          hand: handWithHigher,
          leadSuit: CardSuit.hearts,
          isTrumpRevealed: true,
          trumpSuit: CardSuit.diamonds,
          mustPlayTrumpIfHeld: true,
          minTrumpPowerToBeat: 4,
        ),
        isFalse,
      );

      expect(
        Card29Engine.isCardLegal(
          card: Card29.fromCode('JD'),
          hand: handWithHigher,
          leadSuit: CardSuit.hearts,
          isTrumpRevealed: true,
          trumpSuit: CardSuit.diamonds,
          mustPlayTrumpIfHeld: true,
          minTrumpPowerToBeat: 4,
        ),
        isTrue,
      );
    });
  });
}
