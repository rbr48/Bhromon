import 'dart:math';

import 'teen_patti_engine.dart';

enum TeenPattiPhase { betting, awaitingSideshowReply, roundOver }

class TeenPattiPlayer {
  TeenPattiPlayer({
    required this.id,
    required this.name,
    required this.isUser,
    this.chips = TeenPattiGame.startingChips,
  });

  final int id;
  final String name;
  final bool isUser;
  List<TeenPattiCard> hand = [];
  bool isSeen = false;
  bool isFolded = false;
  int chips;
  int blindTurns = 0;

  /// Short label of the player's latest action, shown on their seat.
  String? lastAction;
}

class TeenPattiResult {
  const TeenPattiResult({
    required this.winnerIds,
    required this.potWon,
    required this.title,
    required this.detail,
    required this.wasShowdown,
  });

  final List<int> winnerIds;
  final int potWon;
  final String title;
  final String detail;
  final bool wasShowdown;
}

/// A seen player asked the previous seen player to compare hands privately.
class SideshowRequest {
  const SideshowRequest(this.fromId, this.toId);

  final int fromId;
  final int toId;
}

/// Rules and table state for a 4-seat Teen Patti game (You + 3 bots).
///
/// Blind players stake the base bet, seen players stake double (chaal). A raise
/// doubles the base bet (up to [maxBase]). Show is allowed once two players
/// remain; a sideshow compares privately with the previous seen player, who
/// may decline. Ties at a show split the pot between the tied players; in a
/// sideshow the player who asked loses a tie.
class TeenPattiGame {
  static const int boot = 10;
  static const int startingBase = 10;
  static const int maxBase = 40;
  static const int maxBlindTurns = 4;
  static const int startingChips = 500;
  static const int rebuyAmount = 500;
  static const int potLimit = 1280;

  /// Chips needed to sit in a hand: the boot plus one blind stake.
  static const int minimumBuyIn = boot + startingBase;

  TeenPattiGame({Random? random}) : _random = random ?? Random() {
    players = [
      TeenPattiPlayer(id: 0, name: 'You', isUser: true),
      TeenPattiPlayer(id: 1, name: 'East (Bot)', isUser: false),
      TeenPattiPlayer(id: 2, name: 'North (Bot)', isUser: false),
      TeenPattiPlayer(id: 3, name: 'West (Bot)', isUser: false),
    ];
  }

  final Random _random;
  late final List<TeenPattiPlayer> players;
  int dealer = 3;
  int currentTurn = 0;
  int pot = 0;
  int baseBet = startingBase;
  TeenPattiPhase phase = TeenPattiPhase.roundOver;
  String status = 'Welcome to 3 Patti (তিন পাত্তি)!';
  TeenPattiResult? result;
  SideshowRequest? pendingSideshow;
  bool _handStarted = false;

  TeenPattiPlayer get user => players[0];
  List<TeenPattiPlayer> get activePlayers => players.where((p) => !p.isFolded).toList();
  bool get isRoundOver => phase == TeenPattiPhase.roundOver;
  bool get isHandInProgress => _handStarted && !isRoundOver;
  bool get hasDealt => _handStarted;
  bool get userNeedsRebuy => user.chips < minimumBuyIn;

  void rebuyUser() {
    user.chips += rebuyAmount;
    status = 'Rebuy! +$rebuyAmount chips added to your balance.';
  }

  /// Deals a new hand. Returns false if you need to rebuy first.
  bool startHand() {
    if (userNeedsRebuy) return false;

    final notes = <String>[];
    for (final bot in players.where((p) => !p.isUser)) {
      if (bot.chips < minimumBuyIn) {
        bot.chips += rebuyAmount;
        notes.add('${bot.name} bought back in.');
      }
    }

    final deck = TeenPattiEngine.createDeck()..shuffle(_random);
    for (int i = 0; i < players.length; i++) {
      final p = players[i]
        ..hand = deck.sublist(i * 3, (i + 1) * 3)
        ..isFolded = false
        ..isSeen = false
        ..blindTurns = 0
        ..lastAction = null;
      p.chips -= boot;
    }

    dealer = (dealer + 1) % players.length;
    pot = boot * players.length;
    baseBet = startingBase;
    phase = TeenPattiPhase.betting;
    result = null;
    pendingSideshow = null;
    _handStarted = true;
    currentTurn = (dealer + 1) % players.length;
    status = [
      'Boot of $boot collected from everyone (pot $pot).',
      ...notes,
      if (currentTurn == 0) 'Your turn: play Blind or See your cards.' else '${players[currentTurn].name} acts first.',
    ].join(' ');
    return true;
  }

  String displayName(TeenPattiPlayer p) => p.isUser ? 'You' : p.name;

  /// Stake this player pays to stay in: base bet blind, double base (chaal) when seen.
  int costFor(TeenPattiPlayer p, {int? base}) => p.isSeen ? (base ?? baseBet) * 2 : (base ?? baseBet);

  bool isTurnOf(int id) => phase == TeenPattiPhase.betting && currentTurn == id && !players[id].isFolded;

  bool canBet(int id) => isTurnOf(id) && players[id].chips >= costFor(players[id]);

  bool canRaise(int id) =>
      isTurnOf(id) && baseBet < maxBase && players[id].chips >= costFor(players[id], base: baseBet * 2);

  bool canShow(int id) => isTurnOf(id) && activePlayers.length == 2 && players[id].chips >= costFor(players[id]);

  /// The previous active player (the one who just acted before [id]).
  TeenPattiPlayer? sideshowTarget(int id) {
    var idx = (id + players.length - 1) % players.length;
    while (idx != id) {
      if (!players[idx].isFolded) return players[idx];
      idx = (idx + players.length - 1) % players.length;
    }
    return null;
  }

  bool canSideshow(int id) {
    if (!isTurnOf(id)) return false;
    final p = players[id];
    final target = sideshowTarget(id);
    return p.isSeen && activePlayers.length > 2 && target != null && target.isSeen && p.chips >= costFor(p);
  }

  /// Looking at your cards is free and does not use your turn.
  void see(int id) {
    final p = players[id];
    if (isRoundOver || p.isFolded || p.isSeen) return;
    p.isSeen = true;
    p.lastAction = 'Seen';
    status = p.isUser ? 'You saw your cards! Chaal is now ${costFor(p)}.' : '${p.name} looked at their cards.';
  }

  bool bet(int id) {
    if (!canBet(id)) return false;
    _stake(players[id], label: null);
    return true;
  }

  bool raise(int id) {
    if (!canRaise(id)) return false;
    baseBet *= 2;
    _stake(players[id], label: 'Raise');
    return true;
  }

  void _stake(TeenPattiPlayer p, {String? label}) {
    final wasBlind = !p.isSeen;
    final cost = costFor(p);
    _pay(p, cost);
    final action = label ?? (wasBlind ? 'Blind' : 'Chaal');
    p.lastAction = '$action $cost';
    var note = '';
    if (wasBlind) {
      p.blindTurns++;
      if (p.blindTurns >= maxBlindTurns) {
        p.isSeen = true;
        note = p.isUser
            ? ' That was your ${maxBlindTurns}th blind, so your cards are now open.'
            : ' ${p.name} reached the blind limit and sees their cards.';
      }
    }
    status = '${displayName(p)} ${p.isUser ? 'played' : 'plays'} $action ($cost chips).$note';
    _advance();
  }

  void pack(int id) {
    if (!isTurnOf(id)) return;
    final p = players[id]
      ..isFolded = true
      ..lastAction = 'Packed';
    status = p.isUser ? 'You packed (folded).' : '${p.name} packed.';
    _advance();
  }

  bool show(int id) {
    if (!canShow(id)) return false;
    final p = players[id];
    _pay(p, costFor(p));
    p.lastAction = 'Show';
    _showdown(activePlayers, requestedBy: p);
    return true;
  }

  bool requestSideshow(int id) {
    if (!canSideshow(id)) return false;
    final p = players[id];
    final target = sideshowTarget(id)!;
    _pay(p, costFor(p));
    p.lastAction = 'Sideshow';

    if (target.isUser) {
      pendingSideshow = SideshowRequest(id, target.id);
      phase = TeenPattiPhase.awaitingSideshowReply;
      status = '${p.name} asks you for a sideshow.';
      return true;
    }
    if (_botAcceptsSideshow(target)) {
      _resolveSideshow(p, target);
    } else {
      status = '${target.name} declined the sideshow.';
      _advance();
    }
    return true;
  }

  /// Your answer when a bot asks you for a sideshow.
  void answerSideshow(bool accept) {
    final request = pendingSideshow;
    if (request == null) return;
    pendingSideshow = null;
    phase = TeenPattiPhase.betting;
    final from = players[request.fromId];
    final to = players[request.toId];
    if (accept) {
      _resolveSideshow(from, to);
    } else {
      status = 'You declined the sideshow.';
      _advance();
    }
  }

  void _resolveSideshow(TeenPattiPlayer from, TeenPattiPlayer to) {
    final cmp = TeenPattiEngine.compareHands(from.hand, to.hand);
    final loser = cmp > 0 ? to : from; // a tie goes against the player who asked
    final winner = identical(loser, from) ? to : from;
    loser
      ..isFolded = true
      ..lastAction = 'Packed (sideshow)';
    if (from.isUser || to.isUser) {
      status = winner.isUser ? 'Sideshow won! ${loser.name} packed.' : 'Sideshow lost - ${winner.name} had the better hand. You packed.';
    } else {
      status = 'Sideshow: ${winner.name} kept their hand, ${loser.name} packed.';
    }
    _advance();
  }

  /// You walk away from the hand: you pack and the rest of the table settles now.
  void forfeitUserAndFinish() {
    if (!isHandInProgress) return;
    pendingSideshow = null;
    phase = TeenPattiPhase.betting;
    user
      ..isFolded = true
      ..lastAction = 'Packed';
    final active = activePlayers;
    if (active.length == 1) {
      _awardLastStanding(active.first);
    } else {
      _showdown(active, requestedBy: null);
    }
  }

  void _pay(TeenPattiPlayer p, int amount) {
    p.chips -= amount;
    pot += amount;
  }

  void _advance() {
    final active = activePlayers;
    if (active.length <= 1) {
      _awardLastStanding(active.first);
      return;
    }
    if (pot >= potLimit) {
      _showdown(active, requestedBy: null, potLimitReached: true);
      return;
    }
    do {
      currentTurn = (currentTurn + 1) % players.length;
    } while (players[currentTurn].isFolded);
  }

  void _awardLastStanding(TeenPattiPlayer winner) {
    final won = pot;
    winner.chips += won;
    pot = 0;
    phase = TeenPattiPhase.roundOver;
    result = TeenPattiResult(
      winnerIds: [winner.id],
      potWon: won,
      title: winner.isUser ? 'You win!' : '${winner.name} wins',
      detail: winner.isUser
          ? 'Everyone else packed. You collect the pot of $won chips.'
          : 'Everyone else packed. ${winner.name} collects the pot of $won chips.',
      wasShowdown: false,
    );
    status = '${displayName(winner)} won the pot of $won chips!';
  }

  void _showdown(List<TeenPattiPlayer> contenders, {TeenPattiPlayer? requestedBy, bool potLimitReached = false}) {
    HandEvaluation? best;
    var winners = <TeenPattiPlayer>[];
    for (final p in contenders) {
      final eval = TeenPattiEngine.evaluateHand(p.hand);
      final cmp = best == null ? 1 : eval.compareTo(best);
      if (cmp > 0) {
        best = eval;
        winners = [p];
      } else if (cmp == 0) {
        winners.add(p);
      }
    }

    final won = pot;
    final share = won ~/ winners.length;
    for (int i = 0; i < winners.length; i++) {
      winners[i].chips += share + (i == 0 ? won - share * winners.length : 0);
    }
    pot = 0;
    phase = TeenPattiPhase.roundOver;
    for (final p in contenders) {
      p.isSeen = true;
    }

    final handName = best!.handType.banglaName;
    final prefix = potLimitReached
        ? 'Pot limit reached - automatic show. '
        : (requestedBy != null ? '${displayName(requestedBy)} asked for a show. ' : '');
    if (winners.length > 1) {
      final names = winners.map(displayName).join(' & ');
      result = TeenPattiResult(
        winnerIds: winners.map((w) => w.id).toList(),
        potWon: won,
        title: 'Split Pot',
        detail: '$prefix$names tie with $handName and split $won chips ($share each).',
        wasShowdown: true,
      );
      status = 'Showdown tie! $names split the pot.';
    } else {
      final w = winners.first;
      result = TeenPattiResult(
        winnerIds: [w.id],
        potWon: won,
        title: w.isUser ? 'You win!' : '${w.name} wins',
        detail: '$prefix${displayName(w)} ${w.isUser ? 'win' : 'wins'} the pot of $won chips with $handName.',
        wasShowdown: true,
      );
      status = '${displayName(w)} ${w.isUser ? 'win' : 'wins'} with $handName!';
    }
  }

  // --- BOTS ---

  /// Rough 0..1 strength of a 3-card hand, used by the bots.
  static double handStrength(List<TeenPattiCard> hand) {
    final e = TeenPattiEngine.evaluateHand(hand);
    final rank = e.primaryValue / 14;
    switch (e.handType) {
      case TeenPattiHandType.trail:
        return 0.97 + rank * 0.03;
      case TeenPattiHandType.pureSequence:
        return 0.92 + rank * 0.04;
      case TeenPattiHandType.sequence:
        return 0.84 + rank * 0.06;
      case TeenPattiHandType.color:
        return 0.72 + rank * 0.1;
      case TeenPattiHandType.pair:
        return 0.45 + rank * 0.25;
      case TeenPattiHandType.highCard:
        return ((e.primaryValue - 4) / 10).clamp(0.0, 1.0) * 0.4;
    }
  }

  /// Plays one action for the bot whose turn it is.
  void playBotTurn() {
    if (phase != TeenPattiPhase.betting) return;
    final bot = players[currentTurn];
    if (bot.isUser || bot.isFolded) return;
    final id = bot.id;

    if (!bot.isSeen && (bot.blindTurns >= 2 || pot > 120 || _random.nextDouble() < 0.15)) {
      see(id);
    }
    if (!canBet(id)) {
      pack(id);
      return;
    }

    if (!bot.isSeen) {
      if (_random.nextDouble() < 0.1 && canRaise(id)) {
        raise(id);
      } else {
        bet(id);
      }
      return;
    }

    final strength = handStrength(bot.hand) + (_random.nextDouble() - 0.5) * 0.1;
    final activeCount = activePlayers.length;

    if (activeCount == 2 && strength >= 0.55 && pot >= 100 && canShow(id)) {
      show(id);
      return;
    }
    final foldBelow = 0.12 + (baseBet / maxBase) * 0.25 + (pot > 300 ? 0.05 : 0);
    if (strength < foldBelow) {
      pack(id);
      return;
    }
    if (strength > 0.75 && canRaise(id) && _random.nextDouble() < 0.5) {
      raise(id);
      return;
    }
    if (activeCount > 2 && strength >= 0.35 && strength <= 0.7 && canSideshow(id) && _random.nextDouble() < 0.25) {
      requestSideshow(id);
      return;
    }
    if (activeCount == 2 && pot >= 300 && strength >= 0.3 && canShow(id)) {
      show(id);
      return;
    }
    bet(id);
  }

  bool _botAcceptsSideshow(TeenPattiPlayer bot) {
    if (!bot.isSeen) see(bot.id);
    return handStrength(bot.hand) >= 0.45;
  }
}
