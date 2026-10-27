import 'package:bhromon/features/game_zone/domain/models/teen_patti_table.dart';
import 'package:bhromon/features/game_zone/teen_patti/teen_patti_game.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _seat({
  int chips = 500,
  bool playing = true,
  bool seen = false,
  bool folded = false,
}) =>
    {
      'chips': chips,
      'playing': playing,
      'isSeen': seen,
      'isFolded': folded,
      'blindTurns': 0,
      'lastAction': null,
    };

/// A betting table with four seats in play, dealt to seat 0 first.
Map<String, dynamic> _betting({
  int currentTurn = 1,
  List<Map<String, dynamic>>? seats,
  Map<String, dynamic>? pendingSideshow,
  String phase = 'betting',
}) =>
    {
      'step': 3,
      'handNumber': 1,
      'phase': phase,
      'dealer': 0,
      'currentTurn': currentTurn,
      'pot': 40,
      'baseBet': 10,
      'totalInjected': 0,
      'seats': seats ?? [_seat(), _seat(), _seat(), _seat()],
      'pendingSideshow': pendingSideshow,
      'result': null,
      'revealed': null,
      'lastEvent': {'type': 'dealt', 'seat': 0, 'value': null},
      'turnDeadline': 1700000060000,
    };

void main() {
  group('the public table', () {
    test('reads the phase, the pot, the seats and the deadline', () {
      final table = TeenPattiTable.fromState(_betting());
      expect(table.phase, TeenPattiTablePhase.betting);
      expect(table.pot, 40);
      expect(table.seats, hasLength(4));
      expect(table.seats[1].chips, 500);
      expect(table.actingSeat, 1);
      expect(table.turnDeadline,
          DateTime.fromMillisecondsSinceEpoch(1700000060000));
    });

    test('an empty state reads as a table waiting to be dealt', () {
      final table = TeenPattiTable.fromState(const {});
      expect(table.handNumber, 0);
      expect(table.isRoundOver, isTrue);
      expect(table.actingSeat, isNull);
      expect(table.seats, hasLength(4));
    });

    test('the table reveals hands only for the seats in a showdown', () {
      final table = TeenPattiTable.fromState({
        ..._betting(phase: 'roundOver'),
        'result': {
          'winners': [0],
          'potWon': 60,
          'wasShowdown': true,
          'handType': 'pureSequence',
          'potLimitReached': false,
          'requestedBy': 0,
        },
        'revealed': {
          '0': ['AS', 'KS', 'QS'],
          '3': ['JC', 'JD', '8H'],
        },
      });
      expect(table.result?.handType, 'pureSequence');
      expect(table.result?.winners, [0]);
      expect(table.revealed.keys.toList()..sort(), [0, 3]);
      expect(table.revealed[0]!.first.code, 'AS');
    });
  });

  group('what the table allows', () {
    test('only the seat whose turn it is may bet, pack or show', () {
      final table = TeenPattiTable.fromState(_betting(currentTurn: 1));
      expect(table.canBet(1), isTrue);
      expect(table.canBet(0), isFalse);
      expect(table.canShow(1), isFalse); // four players, not two
    });

    test('looking at the cards is allowed off turn, once', () {
      final table = TeenPattiTable.fromState(_betting(currentTurn: 1));
      expect(table.canSee(0), isTrue);
      final seen = TeenPattiTable.fromState(_betting(seats: [
        _seat(seen: true),
        _seat(),
        _seat(),
        _seat(),
      ]));
      expect(seen.canSee(0), isFalse);
    });

    test('a show needs two players, and a sideshow needs two seen players', () {
      final twoLeft = TeenPattiTable.fromState(_betting(currentTurn: 2, seats: [
        _seat(),
        _seat(folded: true),
        _seat(),
        _seat(folded: true),
      ]));
      expect(twoLeft.canShow(2), isTrue);

      final threeLeft =
          TeenPattiTable.fromState(_betting(currentTurn: 3, seats: [
        _seat(seen: true),
        _seat(seen: true),
        _seat(seen: true),
        _seat(seen: true),
      ]));
      expect(threeLeft.sideshowTarget(3), 2);
      expect(threeLeft.canSideshow(3), isTrue);
      expect(threeLeft.canSideshow(2), isFalse); // not their turn
    });

    test('a person who was asked answers, and nobody else does', () {
      final table = TeenPattiTable.fromState(_betting(
        phase: 'awaitingSideshowReply',
        pendingSideshow: {'from': 3, 'to': 2},
      ));
      expect(table.actingSeat, 2);
      expect(table.canReplySideshow(2), isTrue);
      expect(table.canReplySideshow(3), isFalse);
    });

    test('chips can be topped up between hands, or while sitting out', () {
      final short = [
        _seat(chips: 19),
        _seat(),
        _seat(),
        _seat(),
      ];
      final midHand = TeenPattiTable.fromState(_betting(seats: short));
      expect(midHand.canRebuy(0), isFalse);

      final between = TeenPattiTable.fromState({
        ..._betting(phase: 'roundOver', seats: short),
      });
      expect(between.canRebuy(0), isTrue);
      expect(TeenPattiGame.minimumBuyIn, 20);

      final sittingOut = TeenPattiTable.fromState(_betting(seats: [
        _seat(chips: 19, playing: false),
        _seat(),
        _seat(),
        _seat(),
      ]));
      expect(sittingOut.canRebuy(0), isTrue);
    });
  });

  group('a private hand', () {
    test('reads the cards dealt to the seat', () {
      final hand = TeenPattiPrivateHand.fromMap({
        'owner': 'asha@x.com',
        'seat': 1,
        'hand': ['10S', 'AH', '2D'],
      });
      expect(hand.cards.map((c) => c.code), ['10S', 'AH', '2D']);
      expect(hand.cards.first.value, 10);
    });
  });
}
