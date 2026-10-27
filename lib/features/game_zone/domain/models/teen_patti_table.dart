import '../../teen_patti/teen_patti_engine.dart';
import '../../teen_patti/teen_patti_game.dart';

/// Where the online Teen Patti table is, as the server writes it.
enum TeenPattiTablePhase { betting, awaitingSideshowReply, roundOver }

/// One seat of the public table: chips and what the seat has done. The cards
/// are not here; they are the seat's private hand.
class TeenPattiSeat {
  const TeenPattiSeat({
    required this.chips,
    required this.playing,
    required this.isSeen,
    required this.isFolded,
    required this.blindTurns,
    this.lastKind,
    this.lastAmount,
  });

  final int chips;

  /// Dealt into the current hand. A seat short of the buy-in sits the hand out.
  final bool playing;
  final bool isSeen;
  final bool isFolded;
  final int blindTurns;

  /// The seat's last action: blind, chaal, raise, show, sideshow, pack, seen,
  /// left or sideshowLost.
  final String? lastKind;
  final int? lastAmount;

  /// Still in the hand: dealt, and not packed.
  bool get isActive => playing && !isFolded;
}

/// A seat that has asked the previous seat to compare hands in private.
class TeenPattiSideshow {
  const TeenPattiSideshow({required this.from, required this.to});

  final int from;
  final int to;
}

/// How the last hand was settled.
class TeenPattiHandResult {
  const TeenPattiHandResult({
    required this.winners,
    required this.potWon,
    required this.wasShowdown,
    required this.potLimitReached,
    this.handType,
    this.requestedBy,
  });

  final List<int> winners;
  final int potWon;
  final bool wasShowdown;
  final bool potLimitReached;

  /// The winning hand's type name, such as pureSequence. Null when the hand
  /// ended without a showdown.
  final String? handType;
  final int? requestedBy;

  bool get isTie => winners.length > 1;
}

/// The public table, read from the server's state. Its checks mirror the
/// server's rules so the screen can offer only what the server will accept.
class TeenPattiTable {
  const TeenPattiTable({
    required this.step,
    required this.handNumber,
    required this.phase,
    required this.dealer,
    required this.currentTurn,
    required this.pot,
    required this.baseBet,
    required this.totalInjected,
    required this.seats,
    required this.revealed,
    this.pendingSideshow,
    this.result,
    this.lastEventType,
    this.lastEventSeat,
    this.lastEventValue,
    this.turnDeadline,
  });

  factory TeenPattiTable.fromState(Map<String, dynamic> state) {
    final rawSeats =
        state['seats'] is List ? state['seats'] as List : const <Object?>[];
    final event = _mapOf(state['lastEvent']);
    final deadline = state['turnDeadline'];
    return TeenPattiTable(
      step: _intOf(state['step']),
      handNumber: _intOf(state['handNumber']),
      phase: _phaseOf(state['phase'] as String?),
      dealer: _intOf(state['dealer']),
      currentTurn: _intOf(state['currentTurn']),
      pot: _intOf(state['pot']),
      baseBet: _intOf(state['baseBet'], TeenPattiGame.startingBase),
      totalInjected: _intOf(state['totalInjected']),
      seats: List.generate(
        4,
        (i) => _seatOf(i < rawSeats.length ? rawSeats[i] : null),
      ),
      pendingSideshow: _sideshowOf(state['pendingSideshow']),
      result: _resultOf(state['result']),
      revealed: _revealedOf(state['revealed']),
      lastEventType: event?['type'] as String?,
      lastEventSeat: (event?['seat'] as num?)?.toInt(),
      lastEventValue: (event?['value'] as num?)?.toInt(),
      turnDeadline: deadline is num
          ? DateTime.fromMillisecondsSinceEpoch(deadline.toInt())
          : null,
    );
  }

  final int step;
  final int handNumber;
  final TeenPattiTablePhase phase;
  final int dealer;
  final int currentTurn;
  final int pot;
  final int baseBet;

  /// Chips rebuys have added. With the chips and the pot, this is what the
  /// table's books must add up to.
  final int totalInjected;
  final List<TeenPattiSeat> seats;
  final TeenPattiSideshow? pendingSideshow;
  final TeenPattiHandResult? result;

  /// The hands shown at the last showdown, by seat.
  final Map<int, List<TeenPattiCard>> revealed;
  final String? lastEventType;
  final int? lastEventSeat;
  final int? lastEventValue;

  /// When the seat being waited on runs out of time. Null for bots and between hands.
  final DateTime? turnDeadline;

  bool get isRoundOver => phase == TeenPattiTablePhase.roundOver;

  int get activeCount => seats.where((s) => s.isActive).length;

  /// The seat that must act now, or null when the table waits on nobody.
  int? get actingSeat {
    switch (phase) {
      case TeenPattiTablePhase.betting:
        return currentTurn;
      case TeenPattiTablePhase.awaitingSideshowReply:
        return pendingSideshow?.to;
      case TeenPattiTablePhase.roundOver:
        return null;
    }
  }

  bool isTurnOf(int seat) =>
      phase == TeenPattiTablePhase.betting &&
      currentTurn == seat &&
      seats[seat].isActive;

  /// The stake this seat pays to stay in: the base bet blind, double it once seen.
  int costFor(int seat, {int? base}) =>
      seats[seat].isSeen ? (base ?? baseBet) * 2 : (base ?? baseBet);

  /// Looking at your cards is free, and does not use your turn.
  bool canSee(int seat) =>
      !isRoundOver && seats[seat].isActive && !seats[seat].isSeen;

  bool canBet(int seat) => isTurnOf(seat) && seats[seat].chips >= costFor(seat);

  bool canRaise(int seat) =>
      isTurnOf(seat) &&
      baseBet < TeenPattiGame.maxBase &&
      seats[seat].chips >= costFor(seat, base: baseBet * 2);

  bool canShow(int seat) =>
      isTurnOf(seat) && activeCount == 2 && seats[seat].chips >= costFor(seat);

  /// The previous active seat: the one who just acted before [seat].
  int? sideshowTarget(int seat) {
    var idx = (seat + seats.length - 1) % seats.length;
    while (idx != seat) {
      if (seats[idx].isActive) return idx;
      idx = (idx + seats.length - 1) % seats.length;
    }
    return null;
  }

  bool canSideshow(int seat) {
    if (!isTurnOf(seat)) return false;
    final target = sideshowTarget(seat);
    return seats[seat].isSeen &&
        activeCount > 2 &&
        target != null &&
        seats[target].isSeen &&
        seats[seat].chips >= costFor(seat);
  }

  /// Whether [seat] is the one who must answer a sideshow asked of it.
  bool canReplySideshow(int seat) =>
      phase == TeenPattiTablePhase.awaitingSideshowReply &&
      pendingSideshow?.to == seat;

  /// Chips can be topped up between hands, or while sitting a hand out.
  bool canRebuy(int seat) =>
      seats[seat].chips < TeenPattiGame.minimumBuyIn &&
      (isRoundOver || !seats[seat].playing);
}

/// The cards dealt to one seat. Only that seat's owner can read them.
class TeenPattiPrivateHand {
  const TeenPattiPrivateHand(this.cards);

  factory TeenPattiPrivateHand.fromMap(Map<String, dynamic> map) {
    final codes = (map['hand'] as List? ?? const []).cast<String>();
    return TeenPattiPrivateHand(
      codes.map(TeenPattiCard.fromCode).toList(),
    );
  }

  final List<TeenPattiCard> cards;
}

TeenPattiTablePhase _phaseOf(String? name) =>
    TeenPattiTablePhase.values.firstWhere(
      (p) => p.name == name,
      orElse: () => TeenPattiTablePhase.roundOver,
    );

int _intOf(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

Map<String, dynamic>? _mapOf(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

TeenPattiSeat _seatOf(Object? raw) {
  final map = _mapOf(raw) ?? const <String, dynamic>{};
  final last = _mapOf(map['lastAction']);
  return TeenPattiSeat(
    chips: _intOf(map['chips']),
    playing: map['playing'] == true,
    isSeen: map['isSeen'] == true,
    isFolded: map['isFolded'] == true,
    blindTurns: _intOf(map['blindTurns']),
    lastKind: last?['kind'] as String?,
    lastAmount: (last?['amount'] as num?)?.toInt(),
  );
}

TeenPattiSideshow? _sideshowOf(Object? raw) {
  final map = _mapOf(raw);
  if (map == null) return null;
  return TeenPattiSideshow(from: _intOf(map['from']), to: _intOf(map['to']));
}

TeenPattiHandResult? _resultOf(Object? raw) {
  final map = _mapOf(raw);
  if (map == null) return null;
  final winners = (map['winners'] as List? ?? const [])
      .map((w) => (w as num).toInt())
      .toList();
  return TeenPattiHandResult(
    winners: winners,
    potWon: _intOf(map['potWon']),
    wasShowdown: map['wasShowdown'] == true,
    potLimitReached: map['potLimitReached'] == true,
    handType: map['handType'] as String?,
    requestedBy: (map['requestedBy'] as num?)?.toInt(),
  );
}

Map<int, List<TeenPattiCard>> _revealedOf(Object? raw) {
  final map = _mapOf(raw);
  if (map == null) return const {};
  final out = <int, List<TeenPattiCard>>{};
  map.forEach((key, value) {
    final seat = int.tryParse(key);
    if (seat == null || value is! List) return;
    out[seat] = value.cast<String>().map(TeenPattiCard.fromCode).toList();
  });
  return out;
}
