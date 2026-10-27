import 'dart:math';

import 'package:bhromon/features/game_zone/card29/card29_engine.dart';
import 'package:bhromon/features/game_zone/card29/card29_game.dart';
import 'package:flutter_test/flutter_test.dart';

Card29 _c(String code) => Card29.fromCode(code);

/// Puts a game straight into play with chosen hands, bidder and trump.
Card29Game _playing({
  required List<List<String>> hands,
  int bidder = 0,
  CardSuit trump = CardSuit.hearts,
  int bid = 16,
  int leader = 0,
}) {
  final g = Card29Game(random: Random(1))..startRound();
  for (int i = 0; i < 4; i++) {
    g.hands[i]
      ..clear()
      ..addAll(hands[i].map(_c));
  }
  g
    ..phase = Card29Phase.playing
    ..highestBidder = bidder
    ..highestBid = bid
    ..bidTarget = bid
    ..trumpSuit = trump
    ..currentTurn = leader;
  return g;
}

void main() {
  group('Card29Game play rules', () {
    test('No card can be played while a finished trick is on the table', () {
      final g = _playing(hands: [
        ['7S', '8S'],
        ['9S', 'KS'],
        ['QS', 'AS'],
        ['10S', 'JS'],
      ], leader: 1);
      expect(g.playCard(1, _c('9S')), isTrue);
      expect(g.playCard(2, _c('QS')), isTrue);
      expect(g.playCard(3, _c('10S')), isTrue);
      expect(g.playCard(0, _c('7S')), isTrue);
      expect(g.phase, Card29Phase.trickComplete);
      expect(g.legalCards(0), isEmpty);
      expect(g.playCard(0, _c('8S')), isFalse);
      expect(g.currentTrick.length, 4);
      g.resolveTrick();
      expect(g.phase, Card29Phase.playing);
      expect(g.currentTurn, 1); // 9S outranks 10S and QS in 29
      expect(g.teamPoints[1], 3); // 9 (2) + 10 (1)
    });

    test(
        'After trump is revealed a void player must trump if opponent is winning, but is not forced if partner is winning',
        () {
      final g = _playing(
        hands: [
          ['7S', '8S'],
          ['7H', '8D'], // East: void in clubs, holds a trump
          ['7C', '8C'],
          ['9C', 'KC'],
        ],
        bidder: 2,
        trump: CardSuit.hearts,
        leader: 3,
      );
      g.isTrumpRevealed = true;
      expect(g.playCard(3, _c('9C')), isTrue);
      expect(g.legalCards(0).map((c) => c.code),
          ['7S', '8S']); // You hold no trump: anything

      // Partner West (3) is winning: East is not forced to trump partner
      g.currentTurn = 1;
      expect(g.legalCards(1).map((c) => c.code), ['7H', '8D']);

      // If North (opponent 2) leads and is winning, East MUST trump
      final gOpp = _playing(
        hands: [
          ['7S', '8S'],
          ['7H', '8D'], // East: void in clubs, holds a trump
          ['JC', '8C'],
          ['9C', 'KC'],
        ],
        bidder: 2,
        trump: CardSuit.hearts,
        leader: 2,
      );
      gOpp.isTrumpRevealed = true;
      expect(gOpp.playCard(2, _c('JC')), isTrue);
      gOpp.currentTurn = 1;
      expect(gOpp.legalCards(1).map((c) => c.code), ['7H']);
    });

    test(
        'Player void in lead suit with lower trump than opponent winning trump is NOT forced to under-trump',
        () {
      // 0: South (User), 1: East, 2: North (Partner), 3: West
      // Order: 1 (East) -> 2 (North) -> 3 (West) -> 0 (South)
      // Lead suit: Hearts. Trump: Diamonds.
      // East (1) leads 7H. North (2) plays JH. West (3) trumps with KD (power 4).
      // South (0) has: 8D (Diamonds, power 2), 9S, AS, 10C.
      // West (opponent 3) is winning with KD. South only has 8D which cannot beat KD.
      // South is free to play any card (no forced under-trumping).
      final g = _playing(
        hands: [
          [
            '8D',
            '9S',
            'AS',
            '10C'
          ], // South: holds lower trump 8D and off-suits
          ['7H', '8H'], // East
          ['JH', '9H'], // North
          ['KD', '8S'], // West
        ],
        bidder: 3,
        trump: CardSuit.diamonds,
        leader: 1,
      );
      g.isTrumpRevealed = true;
      expect(g.playCard(1, _c('7H')), isTrue);
      expect(g.playCard(2, _c('JH')), isTrue);
      expect(g.playCard(3, _c('KD')), isTrue);

      // Now it is South's (0) turn
      expect(g.currentTurn, equals(0));
      final legal = g.legalCards(0).map((c) => c.code).toList();
      // All cards should be legal because South cannot beat KD
      expect(legal, containsAll(['8D', '9S', 'AS', '10C']));
    });

    test('A hidden trump discarded before the reveal does not trump the trick',
        () {
      final g = _playing(
        hands: [
          ['7C', '8C'],
          ['JH', 'KD'], // East: void in clubs, holds the (hidden) jack of trump
          ['9C', 'QD'],
          ['AC', 'KC'],
        ],
        bidder: 0,
        trump: CardSuit.hearts,
        leader: 0,
      );
      expect(g.playCard(0, _c('7C')), isTrue);
      expect(g.playCard(1, _c('JH')), isTrue); // discarded without asking
      expect(g.isTrumpRevealed, isFalse);
      expect(g.playCard(2, _c('9C')), isTrue);
      expect(g.playCard(3, _c('AC')), isTrue);
      expect(g.trickWinner, 2); // 9C is the top club
    });

    test('The bidder reveals trump by playing it while void', () {
      final g = _playing(
        hands: [
          ['7H', '8D'], // You: bidder, void in clubs
          ['7C', '8C'],
          ['9C', 'QC'],
          ['AC', 'KC'],
        ],
        bidder: 0,
        trump: CardSuit.hearts,
        leader: 1,
      );
      expect(g.canAskTrump(0), isFalse);
      g.playCard(1, _c('7C'));
      g.playCard(2, _c('9C'));
      g.playCard(3, _c('AC'));
      expect(g.playCard(0, _c('7H')), isTrue);
      expect(g.isTrumpRevealed, isTrue);
      expect(g.trickWinner, 0);
    });

    test('The bidder may not lead the hidden trump suit', () {
      final g = _playing(hands: [
        ['JH', '7S'],
        ['7C'],
        ['8C'],
        ['9C'],
      ], bidder: 0, trump: CardSuit.hearts);
      expect(g.legalCards(0).map((c) => c.code), ['7S']);
    });

    test('Pair lowers the bidding team target and raises it for the opponents',
        () {
      final mine = _playing(hands: [
        ['KH', 'QH'],
        ['7C'],
        ['8C'],
        ['9C'],
      ], bidder: 0, bid: 20);
      mine.isTrumpRevealed = true;
      expect(mine.claimRoyalty(0), isTrue);
      expect(mine.bidTarget, 16);
      expect(mine.claimRoyalty(0), isFalse);

      final theirs = _playing(hands: [
        ['7C'],
        ['KH', 'QH'],
        ['8C'],
        ['9C'],
      ], bidder: 0, bid: 26);
      theirs.isTrumpRevealed = true;
      expect(theirs.claimRoyalty(1), isTrue);
      expect(theirs.bidTarget, 28);
    });
  });

  group('Card29Game bidding and match', () {
    test('A pass is final and all-pass makes the dealer play at 16', () {
      final g = Card29Game(random: Random(3))..startRound();
      final first = g.currentTurn;
      for (int i = 0; i < 4; i++) {
        expect(g.pass(g.currentTurn), isTrue);
      }
      expect(g.highestBidder, g.dealer);
      expect(g.highestBid, 16);
      expect(first, (g.dealer + 1) % 4);
    });

    test('Starting a round after the match ends clears the pips', () {
      final g = Card29Game(random: Random(4))..startRound();
      g.matchPips[0] = 6;
      g.phase = Card29Phase.matchOver;
      g.startRound();
      expect(g.matchPips, [0, 0]);
      expect(g.phase, Card29Phase.bidding);
    });

    test('Bots only ever make legal plays and every match finishes', () {
      for (int seed = 0; seed < 20; seed++) {
        final g = Card29Game(random: Random(seed))..startRound();
        var guard = 0;
        while (g.phase != Card29Phase.matchOver && guard++ < 5000) {
          switch (g.phase) {
            case Card29Phase.bidding:
              if (g.currentTurn == 0) {
                g.pass(0);
              } else {
                g.playBotTurn();
              }
              break;
            case Card29Phase.trumpSelection:
              g.selectTrump(Card29Bot.chooseTrump(g.hands[0]));
              break;
            case Card29Phase.playing:
              final p = g.currentTurn;
              final before = g.hands[p].length;
              if (p == 0) {
                g.playCard(0, g.legalCards(0).first);
              } else {
                final legal = g.legalCards(p).toList();
                final trickBefore = g.currentTrick.length;
                g.playBotTurn();
                // The card played must have been legal (after any trump ask).
                final played = g.phase == Card29Phase.trickComplete
                    ? g.currentTrick.last.card
                    : (g.currentTrick.length > trickBefore
                        ? g.currentTrick.last.card
                        : null);
                if (played != null && !g.isTrumpRevealed) {
                  expect(legal, contains(played));
                }
              }
              expect(g.hands[p].length, before - 1);
              break;
            case Card29Phase.trickComplete:
              g.resolveTrick();
              break;
            case Card29Phase.roundOver:
              expect(g.teamPoints[0] + g.teamPoints[1], 29);
              g.startRound();
              break;
            case Card29Phase.matchOver:
              break;
          }
        }
        expect(g.phase, Card29Phase.matchOver, reason: 'seed $seed');
      }
    });

    test('Bidder can reveal trump when void in lead suit', () {
      final g = _playing(
        hands: [
          ['7H', '8H'], // Player 0 (bidder): holds trump hearts, void in clubs
          ['7C', '8C'],
          ['9C', 'KC'],
          ['10C', 'JC'],
        ],
        bidder: 0,
        trump: CardSuit.hearts,
        leader: 1,
      );
      expect(g.isTrumpRevealed, isFalse);
      expect(g.playCard(1, _c('7C')), isTrue);
      expect(g.currentTurn, 2);
      expect(g.playCard(2, _c('9C')), isTrue);
      expect(g.currentTurn, 3);
      expect(g.playCard(3, _c('10C')), isTrue);
      expect(g.currentTurn, 0);

      // Player 0 is bidder and void in clubs: canRevealTrump must be true, canAskTrump must be false
      expect(g.canAskTrump(0), isFalse);
      expect(g.canRevealTrump(0), isTrue);

      expect(g.revealTrump(0), isTrue);
      expect(g.isTrumpRevealed, isTrue);
      expect(g.trumpRevealedBy, 0);
      expect(g.canRevealTrump(0), isFalse);
      expect(g.status, contains('You revealed trump: ♥ Hearts!'));
    });
  });

  test('Engine: trick winner ignores a pre-reveal trump discard', () {
    final winner = Card29Engine.determineTrickWinner(
      trickCards: [
        PlayedCard(playerIndex: 0, card: _c('7C')),
        PlayedCard(playerIndex: 1, card: _c('JH'), trumpEligible: false),
        PlayedCard(playerIndex: 2, card: _c('8C')),
        PlayedCard(playerIndex: 3, card: _c('7H')),
      ],
      trumpSuit: CardSuit.hearts,
      isTrumpRevealed: true,
    );
    expect(winner.playerIndex, 3);
  });
}
