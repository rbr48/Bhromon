import '../../card29/card29_engine.dart';
import '../../card29/card29_game.dart';

/// The 29 table as the server publishes it.
///
/// The public part comes from the table's state, which holds no hands and no
/// trump until it is revealed. A seat reads its own cards, and the bidder's
/// hidden trump, from its private document. Parsing is tolerant: a missing
/// field takes a safe default rather than failing the whole table.
class Card29Table {
  const Card29Table({
    required this.step,
    required this.phase,
    required this.dealer,
    required this.currentTurn,
    required this.highestBid,
    required this.highestBidder,
    required this.passed,
    required this.trumpRevealed,
    required this.trumpRevealedBy,
    required this.trumpSuit,
    required this.royaltyClaimed,
    required this.royaltyClaimedBy,
    required this.bidTarget,
    required this.currentTrick,
    required this.leadSuit,
    this.trickWinner,
    required this.trickCount,
    required this.teamPoints,
    required this.matchPips,
    required this.handCounts,
    required this.lastTrick,
    required this.lastEvent,
    required this.turnDeadline,
  });

  final int step;
  final Card29Phase phase;
  final int dealer;
  final int currentTurn;
  final int highestBid;
  final int highestBidder;
  final Set<int> passed;
  final bool trumpRevealed;
  final int trumpRevealedBy;

  /// The trump suit, published only once it has been revealed.
  final CardSuit? trumpSuit;
  final bool royaltyClaimed;
  final int royaltyClaimedBy;
  final int bidTarget;
  final List<PlayedCard> currentTrick;
  final CardSuit? leadSuit;

  /// The seat that takes the trick on the table, once all four cards are in.
  final int? trickWinner;
  final int trickCount;

  /// Points won so far this deal: index 0 is seats 0 and 2, index 1 is seats 1 and 3.
  final List<int> teamPoints;

  /// Pips won in the match, by the same team indexes.
  final List<int> matchPips;

  /// How many cards each seat still holds.
  final List<int> handCounts;
  final Card29LastTrick? lastTrick;
  final Card29Event? lastEvent;

  /// When the seat being waited on may be played for automatically. Null when
  /// the table is waiting on a bot or on nothing at all.
  final DateTime? turnDeadline;

  factory Card29Table.fromState(Map<String, dynamic> state) {
    return Card29Table(
      step: _int(state['step']),
      phase: _phase(state['phase']),
      dealer: _int(state['dealer'], 3),
      currentTurn: _int(state['currentTurn']),
      highestBid: _int(state['highestBid'], 15),
      highestBidder: _int(state['highestBidder'], -1),
      passed: {for (final p in _list(state['passed'])) _int(p)},
      trumpRevealed: state['trumpRevealed'] == true,
      trumpRevealedBy: _int(state['trumpRevealedBy'], -1),
      trumpSuit: _suit(state['trumpSuit']),
      royaltyClaimed: state['royaltyClaimed'] == true,
      royaltyClaimedBy: _int(state['royaltyClaimedBy'], -1),
      bidTarget: _int(state['bidTarget']),
      currentTrick: [
        for (final p in _list(state['currentTrick'])) _playedCard(p)
      ],
      leadSuit: _suit(state['leadSuit']),
      trickWinner: state['trickWinner'] is num
          ? (state['trickWinner'] as num).toInt()
          : null,
      trickCount: _int(state['trickCount']),
      teamPoints: _pair(state['teamPoints']),
      matchPips: _pair(state['matchPips']),
      handCounts: [for (final n in _list(state['handCounts'])) _int(n)],
      lastTrick: _lastTrick(state['lastTrick']),
      lastEvent: _event(state['lastEvent']),
      turnDeadline: _time(state['turnDeadline']),
    );
  }

  /// The seat the table is waiting on: the trump-setter during trump selection,
  /// otherwise whoever's turn it is.
  int get actingSeat =>
      phase == Card29Phase.trumpSelection ? highestBidder : currentTurn;

  bool isVoid(List<Card29> hand) =>
      leadSuit != null && !hand.any((c) => c.suit == leadSuit);

  /// Cards [seat] may play now. [knownTrump] is the seat's own knowledge of the
  /// trump, which only the bidder has before the reveal.
  List<Card29> legalCards({
    required int seat,
    required List<Card29> hand,
    required CardSuit? knownTrump,
  }) {
    if (phase != Card29Phase.playing || currentTurn != seat) return const [];
    return Card29Engine.legalPlays(
      hand: hand,
      player: seat,
      highestBidder: highestBidder,
      leadSuit: leadSuit,
      trick: currentTrick,
      trumpSuit: trumpSuit ?? knownTrump,
      isTrumpRevealed: trumpRevealed,
    );
  }

  bool canAskTrump({required int seat, required List<Card29> hand}) =>
      phase == Card29Phase.playing &&
      currentTurn == seat &&
      !trumpRevealed &&
      seat != highestBidder &&
      isVoid(hand);

  bool canRevealTrump({required int seat, required List<Card29> hand}) =>
      phase == Card29Phase.playing &&
      currentTurn == seat &&
      !trumpRevealed &&
      seat == highestBidder &&
      isVoid(hand);

  bool canClaimPair(
          {required List<Card29> hand, required CardSuit? knownTrump}) =>
      (phase == Card29Phase.playing || phase == Card29Phase.trickComplete) &&
      trumpRevealed &&
      !royaltyClaimed &&
      Card29Engine.hasRoyalty(hand, trumpSuit ?? knownTrump);
}

/// The cards a seat holds, and the trump only the bidder knows before the reveal.
class Card29PrivateHand {
  const Card29PrivateHand({
    required this.seat,
    required this.cards,
    required this.trumpSuit,
  });

  final int seat;
  final List<Card29> cards;
  final CardSuit? trumpSuit;

  factory Card29PrivateHand.fromMap(Map<String, dynamic> map) {
    return Card29PrivateHand(
      seat: _int(map['seat']),
      cards: [
        for (final c in _list(map['hand'])) Card29.fromCode(c.toString())
      ],
      trumpSuit: _suit(map['trumpSuit']),
    );
  }
}

class Card29LastTrick {
  const Card29LastTrick({
    required this.cards,
    required this.winner,
    required this.points,
  });

  final List<PlayedCard> cards;
  final int winner;
  final int points;
}

/// A short, public description of the last thing that happened at the table.
class Card29Event {
  const Card29Event({required this.type, required this.seat, this.value});

  final String type;
  final int seat;
  final int? value;
}

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

List<int> _pair(Object? value) {
  final numbers = [for (final n in _list(value)) _int(n)];
  return numbers.length == 2 ? numbers : [0, 0];
}

Card29Phase _phase(Object? value) {
  return Card29Phase.values.firstWhere(
    (p) => p.name == value,
    orElse: () => Card29Phase.bidding,
  );
}

/// The lowercase key the server uses for a suit, such as "hearts".
///
/// CardSuit declares its own `name` field (the display name, "Hearts"), so
/// Dart's enum name cannot be used here.
String suitKey(CardSuit suit) => suit.name.toLowerCase();

CardSuit? _suit(Object? value) {
  if (value is! String) return null;
  for (final suit in CardSuit.values) {
    if (suitKey(suit) == value) return suit;
  }
  return null;
}

DateTime? _time(Object? value) =>
    value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

PlayedCard _playedCard(Object? raw) {
  final map =
      raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
  return PlayedCard(
    playerIndex: _int(map['seat']),
    card: Card29.fromCode((map['card'] ?? '').toString()),
    trumpEligible: map['trumpEligible'] != false,
  );
}

Card29LastTrick? _lastTrick(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  return Card29LastTrick(
    cards: [for (final c in _list(map['cards'])) _playedCard(c)],
    winner: _int(map['winner'], -1),
    points: _int(map['points']),
  );
}

Card29Event? _event(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final value = map['value'];
  return Card29Event(
    type: (map['type'] ?? '').toString(),
    seat: _int(map['seat'], -1),
    value: value is num ? value.toInt() : null,
  );
}
