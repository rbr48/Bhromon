import 'package:flutter_test/flutter_test.dart';
import 'package:bhromon/features/game_zone/teen_patti/teen_patti_engine.dart';

void main() {
  group('TeenPattiEngine', () {
    test('Deck creation has exactly 52 unique cards', () {
      final deck = TeenPattiEngine.createDeck();
      expect(deck.length, equals(52));
      final codes = deck.map((c) => c.code).toSet();
      expect(codes.length, equals(52));
    });

    test('Identifies Trail (Three of a Kind)', () {
      final hand = [
        TeenPattiCard.fromCode('AS'),
        TeenPattiCard.fromCode('AH'),
        TeenPattiCard.fromCode('AD'),
      ];
      final eval = TeenPattiEngine.evaluateHand(hand);
      expect(eval.handType, equals(TeenPattiHandType.trail));
      expect(eval.primaryValue, equals(14));
    });

    test('Identifies Pure Sequence and regular Sequence', () {
      final pureSeq = [
        TeenPattiCard.fromCode('KS'),
        TeenPattiCard.fromCode('QS'),
        TeenPattiCard.fromCode('JS'),
      ];
      final evalPure = TeenPattiEngine.evaluateHand(pureSeq);
      expect(evalPure.handType, equals(TeenPattiHandType.pureSequence));

      final seq = [
        TeenPattiCard.fromCode('KD'),
        TeenPattiCard.fromCode('QS'),
        TeenPattiCard.fromCode('JH'),
      ];
      final evalSeq = TeenPattiEngine.evaluateHand(seq);
      expect(evalSeq.handType, equals(TeenPattiHandType.sequence));
    });

    test('Hand ranking: Trail beats Pure Sequence, Pure Sequence beats Flush',
        () {
      final trail = [
        TeenPattiCard.fromCode('2S'),
        TeenPattiCard.fromCode('2H'),
        TeenPattiCard.fromCode('2D'),
      ];
      final pureSeq = [
        TeenPattiCard.fromCode('AS'),
        TeenPattiCard.fromCode('KS'),
        TeenPattiCard.fromCode('QS'),
      ];
      final flush = [
        TeenPattiCard.fromCode('AS'),
        TeenPattiCard.fromCode('10S'),
        TeenPattiCard.fromCode('4S'),
      ];

      expect(TeenPattiEngine.compareHands(trail, pureSeq) > 0, isTrue);
      expect(TeenPattiEngine.compareHands(pureSeq, flush) > 0, isTrue);
    });
  });

  sequenceOrderingTests();
}

List<TeenPattiCard> _hand(List<String> codes) =>
    codes.map(TeenPattiCard.fromCode).toList();

void sequenceOrderingTests() {
  group('TeenPattiEngine sequence order', () {
    test('A-2-3 is the lowest run, below 4-3-2, and A-K-Q the highest', () {
      final a23 = _hand(['AS', '2H', '3D']);
      expect(TeenPattiEngine.compareHands(a23, _hand(['4S', '3H', '2D'])),
          lessThan(0));
      expect(TeenPattiEngine.compareHands(a23, _hand(['QS', 'JH', '10D'])),
          lessThan(0));
      expect(TeenPattiEngine.compareHands(a23, _hand(['KS', 'QH', 'JD'])),
          lessThan(0));
      expect(
          TeenPattiEngine.compareHands(
              _hand(['AS', 'KH', 'QD']), _hand(['KS', 'QH', 'JD'])),
          greaterThan(0));
      expect(TeenPattiEngine.evaluateHand(a23).handType,
          TeenPattiHandType.sequence);
    });
  });
}
