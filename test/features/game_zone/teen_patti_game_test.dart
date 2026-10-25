import 'dart:math';

import 'package:bhromon/features/game_zone/teen_patti/teen_patti_engine.dart';
import 'package:bhromon/features/game_zone/teen_patti/teen_patti_game.dart';
import 'package:flutter_test/flutter_test.dart';

List<TeenPattiCard> _hand(List<String> codes) => codes.map(TeenPattiCard.fromCode).toList();

int _totalChips(TeenPattiGame g) => g.players.fold(0, (s, p) => s + p.chips) + g.pot;

/// Packs every player except [keep] until the betting reaches one of them.
void _packAllExcept(TeenPattiGame g, Set<int> keep) {
  while (g.phase == TeenPattiPhase.betting && g.activePlayers.length > keep.length) {
    final id = g.currentTurn;
    if (keep.contains(id)) {
      g.bet(id);
    } else {
      g.pack(id);
    }
  }
}

void main() {
  group('TeenPattiGame', () {
    late TeenPattiGame game;

    setUp(() {
      game = TeenPattiGame(random: Random(7));
      expect(game.startHand(), isTrue);
    });

    test('Boot is collected and chips are conserved', () {
      expect(game.pot, TeenPattiGame.boot * 4);
      final total = _totalChips(game);
      for (int i = 0; i < 40 && game.phase == TeenPattiPhase.betting; i++) {
        if (game.players[game.currentTurn].isUser) {
          game.bet(0);
        } else {
          game.playBotTurn();
        }
        if (game.phase == TeenPattiPhase.awaitingSideshowReply) game.answerSideshow(true);
      }
      expect(_totalChips(game), total);
    });

    test('The pot is cleared once it is paid out', () {
      _packAllExcept(game, {game.currentTurn});
      expect(game.isRoundOver, isTrue);
      expect(game.pot, 0);
      expect(game.result!.potWon, greaterThan(0));
    });

    test('Last-standing result names the bot that won, not "You"', () {
      game.user.isFolded = true;
      final winner = game.players.firstWhere((p) => !p.isUser && p.id != game.currentTurn);
      _packAllExcept(game, {winner.id});
      expect(game.result!.winnerIds, [winner.id]);
      expect(game.result!.detail, contains(winner.name));
      expect(game.result!.detail, isNot(contains('You collect')));
    });

    test('Players cannot stake chips they do not have', () {
      final p = game.players[game.currentTurn];
      p.chips = game.costFor(p) - 1;
      expect(game.canBet(p.id), isFalse);
      expect(game.bet(p.id), isFalse);
      expect(game.canRaise(p.id), isFalse);
      expect(p.chips, greaterThanOrEqualTo(0));
    });

    test('A raise the player cannot afford does not change the base bet', () {
      final p = game.players[game.currentTurn];
      p.chips = game.costFor(p) + 1;
      expect(game.raise(p.id), isFalse);
      expect(game.baseBet, TeenPattiGame.startingBase);
    });

    test('Show ties split the pot only between the tied players', () {
      game.players[0].hand = _hand(['AS', 'KH', '9D']);
      game.players[1].hand = _hand(['AC', 'KD', '9S']);
      game.players[2].hand = _hand(['2S', '5H', '7D']);
      game.players[3].hand = _hand(['3S', '6H', '8C']);
      for (final p in game.players) {
        p.isSeen = true;
      }
      _packAllExcept(game, {0, 1});
      final chipsBefore = game.players[2].chips;
      final potBefore = game.pot;
      while (!game.isRoundOver) {
        if (!game.show(game.currentTurn)) game.bet(game.currentTurn);
      }
      expect(game.result!.winnerIds.toSet(), {0, 1});
      expect(game.players[2].chips, chipsBefore);
      expect(game.result!.potWon, greaterThanOrEqualTo(potBefore));
    });

    test('Sideshow: a tie packs the player who asked', () {
      for (final p in game.players) {
        p.isSeen = true;
      }
      game.currentTurn = 2; // North asks East (the previous active seat)
      game.players[2].hand = _hand(['AS', 'AH', '9D']);
      game.players[1].hand = _hand(['AC', 'AD', '9S']);
      expect(game.sideshowTarget(2)!.id, 1);
      expect(game.requestSideshow(2), isTrue);
      expect(game.players[2].isFolded, isTrue);
      expect(game.players[1].isFolded, isFalse);
    });

    test('Sideshow: a bot with a weak hand declines', () {
      for (final p in game.players) {
        p.isSeen = true;
      }
      game.currentTurn = 2;
      game.players[2].hand = _hand(['AS', 'AH', '9D']);
      game.players[1].hand = _hand(['2S', '5H', '7D']);
      expect(game.requestSideshow(2), isTrue);
      expect(game.players[1].isFolded, isFalse);
      expect(game.players[2].isFolded, isFalse);
      expect(game.currentTurn, 3);
    });

    test('Sideshow: you are asked before anything is compared', () {
      for (final p in game.players) {
        p.isSeen = true;
      }
      game.currentTurn = 1; // East asks you
      game.players[0].hand = _hand(['KS', 'KH', '9D']);
      game.players[1].hand = _hand(['2S', '5H', '7D']);
      expect(game.requestSideshow(1), isTrue);
      expect(game.phase, TeenPattiPhase.awaitingSideshowReply);
      game.answerSideshow(true);
      expect(game.players[1].isFolded, isTrue);
      expect(game.user.isFolded, isFalse);
    });

    test('Bots always finish a hand on their own', () {
      game.user.isFolded = true;
      for (int i = 0; i < 500 && !game.isRoundOver; i++) {
        game.playBotTurn();
        if (game.phase == TeenPattiPhase.awaitingSideshowReply) game.answerSideshow(false);
      }
      expect(game.isRoundOver, isTrue);
    });

    test('Leaving a hand settles it among the remaining players', () {
      final total = _totalChips(game);
      game.forfeitUserAndFinish();
      expect(game.isRoundOver, isTrue);
      expect(game.user.isFolded, isTrue);
      expect(game.result!.winnerIds, isNot(contains(0)));
      expect(_totalChips(game), total);
    });

    test('Rebuy is required before dealing when short of chips', () {
      _packAllExcept(game, {game.currentTurn});
      game.user.chips = TeenPattiGame.minimumBuyIn - 1;
      expect(game.userNeedsRebuy, isTrue);
      expect(game.startHand(), isFalse);
      game.rebuyUser();
      expect(game.startHand(), isTrue);
    });
  });
}
