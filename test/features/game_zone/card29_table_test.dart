import 'dart:math';

import 'package:bhromon/features/game_zone/card29/card29_engine.dart';
import 'package:bhromon/features/game_zone/card29/card29_game.dart';
import 'package:bhromon/features/game_zone/domain/models/card29_table.dart';
import 'package:flutter_test/flutter_test.dart';

Card29 _c(String code) => Card29.fromCode(code);

Map<String, dynamic> _playingState({
  int bidder = 0,
  int currentTurn = 1,
  bool revealed = false,
  String? trump,
  List<Map<String, dynamic>> trick = const [],
  String? leadSuit,
  int? deadlineMs,
}) {
  return {
    'step': 7,
    'phase': 'playing',
    'dealer': 3,
    'currentTurn': currentTurn,
    'highestBid': 17,
    'highestBidder': bidder,
    'passed': [2, 3],
    'trumpRevealed': revealed,
    'trumpRevealedBy': revealed ? bidder : -1,
    'trumpSuit': revealed ? trump : null,
    'royaltyClaimed': false,
    'royaltyClaimedBy': -1,
    'bidTarget': 17,
    'currentTrick': trick,
    'leadSuit': leadSuit,
    'trickWinner': null,
    'playedCards': <String>[],
    'trickCount': 2,
    'teamPoints': [5, 3],
    'matchPips': [1, 0],
    'handCounts': [6, 7, 7, 7],
    'lastTrick': null,
    'lastEvent': {'type': 'play', 'seat': 0},
    'turnDeadline': deadlineMs,
  };
}

void main() {
  group('Card29Table public state', () {
    test('keeps the trump secret until it is revealed', () {
      final hidden = Card29Table.fromState(_playingState(trump: 'hearts'));
      expect(hidden.trumpSuit, isNull);
      expect(hidden.trumpRevealed, isFalse);

      final shown =
          Card29Table.fromState(_playingState(revealed: true, trump: 'hearts'));
      expect(shown.trumpSuit, CardSuit.hearts);
    });

    test('reads the scores, phase, cards on the table and the turn deadline',
        () {
      final table = Card29Table.fromState(_playingState(
        trick: [
          {'seat': 1, 'card': '9S', 'trumpEligible': false},
        ],
        leadSuit: 'spades',
        deadlineMs: 1700000000000,
      ));
      expect(table.phase, Card29Phase.playing);
      expect(table.currentTrick.single.card.code, '9S');
      expect(table.currentTrick.single.playerIndex, 1);
      expect(table.leadSuit, CardSuit.spades);
      expect(table.teamPoints, [5, 3]);
      expect(table.matchPips, [1, 0]);
      expect(table.passed, {2, 3});
      expect(table.turnDeadline?.millisecondsSinceEpoch, 1700000000000);
    });

    test('missing or malformed fields fall back to safe defaults', () {
      final table = Card29Table.fromState(const {'phase': 'nonsense'});
      expect(table.phase, Card29Phase.bidding);
      expect(table.teamPoints, [0, 0]);
      expect(table.matchPips, [0, 0]);
      expect(table.turnDeadline, isNull);
      expect(table.currentTrick, isEmpty);
    });

    test(
        'the seat the table waits on is the trump-setter during trump selection',
        () {
      final state = _playingState(bidder: 2)..['phase'] = 'trumpSelection';
      expect(Card29Table.fromState(state).actingSeat, 2);
      expect(
          Card29Table.fromState(_playingState(currentTurn: 3)).actingSeat, 3);
    });
  });

  group('Card29PrivateHand', () {
    test('reads the seat cards and the trump only the bidder holds', () {
      final hand = Card29PrivateHand.fromMap({
        'seat': 0,
        'hand': ['JH', '7S', '10C'],
        'trumpSuit': 'hearts',
      });
      expect(hand.cards.map((c) => c.code), ['JH', '7S', '10C']);
      expect(hand.trumpSuit, CardSuit.hearts);
    });
  });

  group('Card29Table legal cards', () {
    test(
        'the hidden trump cannot be led by the bidder unless it is all they hold',
        () {
      final table =
          Card29Table.fromState(_playingState(bidder: 0, currentTurn: 0));
      final hand = [_c('JH'), _c('7S')];
      expect(
        table
            .legalCards(seat: 0, hand: hand, knownTrump: CardSuit.hearts)
            .map((c) => c.code),
        ['7S'],
      );
    });

    test('a non-bidder cannot see a hidden trump, so every card is allowed',
        () {
      final table = Card29Table.fromState(_playingState(
        bidder: 0,
        currentTurn: 1,
        leadSuit: 'clubs',
        trick: [
          {'seat': 0, 'card': '9C', 'trumpEligible': false},
        ],
      ));
      final hand = [_c('7H'), _c('8D')];
      expect(
        table
            .legalCards(seat: 1, hand: hand, knownTrump: null)
            .map((c) => c.code),
        ['7H', '8D'],
      );
    });

    test('a void player must trump when an opponent wins with a plain card',
        () {
      final table = Card29Table.fromState(_playingState(
        bidder: 2,
        currentTurn: 1,
        revealed: true,
        trump: 'hearts',
        leadSuit: 'clubs',
        trick: [
          {'seat': 2, 'card': 'JC', 'trumpEligible': false},
        ],
      ));
      // East is void in clubs and holds a heart: the North lead is an opponent's winning card.
      final hand = [_c('7H'), _c('8D')];
      expect(
        table
            .legalCards(seat: 1, hand: hand, knownTrump: null)
            .map((c) => c.code),
        ['7H'],
      );
    });

    test('availability of ask, reveal and pair follows the rules', () {
      final table = Card29Table.fromState(
          _playingState(bidder: 0, currentTurn: 0, leadSuit: 'clubs', trick: [
        {'seat': 1, 'card': '7C', 'trumpEligible': false},
      ]));
      final voidHand = [_c('7H'), _c('8D')];
      expect(table.canRevealTrump(seat: 0, hand: voidHand), isTrue);
      expect(table.canAskTrump(seat: 0, hand: voidHand), isFalse);
      expect(table.canAskTrump(seat: 3, hand: voidHand), isFalse);

      final pairHand = [_c('KH'), _c('QH')];
      final revealed = Card29Table.fromState(
          _playingState(bidder: 0, revealed: true, trump: 'hearts'));
      expect(revealed.canClaimPair(hand: pairHand, knownTrump: null), isTrue);
      expect(
          revealed.canClaimPair(hand: [_c('KH')], knownTrump: null), isFalse);
    });

    test('matches the local game for the same position', () {
      // A position from the local rules: the partner leads and wins, and the
      // void player may play anything. Both implementations must agree.
      final game = Card29Game(random: Random(1))..startRound();
      final hands = [
        ['7S', '8S'],
        ['7H', '8D'],
        ['7C', '8C'],
        ['9C', 'KC'],
      ];
      for (var i = 0; i < 4; i++) {
        game.hands[i]
          ..clear()
          ..addAll(hands[i].map(_c));
      }
      game
        ..phase = Card29Phase.playing
        ..highestBidder = 2
        ..highestBid = 16
        ..bidTarget = 16
        ..trumpSuit = CardSuit.hearts
        ..isTrumpRevealed = true
        ..currentTurn = 3;
      game.playCard(3, _c('9C'));
      game.currentTurn = 1;

      final table = Card29Table.fromState(_playingState(
        bidder: 2,
        currentTurn: 1,
        revealed: true,
        trump: 'hearts',
        leadSuit: 'clubs',
        trick: [
          {'seat': 3, 'card': '9C', 'trumpEligible': false},
        ],
      ));
      final expected = game.legalCards(1).map((c) => c.code).toList()..sort();
      final actual = table
          .legalCards(
              seat: 1, hand: hands[1].map(_c).toList(), knownTrump: null)
          .map((c) => c.code)
          .toList()
        ..sort();
      expect(actual, expected);
    });
  });
}
