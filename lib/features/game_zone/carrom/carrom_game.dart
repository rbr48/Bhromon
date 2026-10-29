import 'dart:math';

import 'carrom_engine.dart';

enum CarromPhase { aiming, moving, gameOver }

/// A shot: striker position on the baseline, direction (radians) and power 0..1.
class CarromShot {
  const CarromShot({required this.x, required this.angle, required this.power});

  final double x;
  final double angle;
  final double power;
}

/// Rules for a two-player board (You = white at the bottom, opponent = black
/// at the top, either the bot or a second person passing the phone).
///
/// Scoring follows the ICF foul rules:
/// - Pocket one of your own coins and you shoot again; opponent coins you
///   pocket stay down and count for the opponent.
/// - Fouls: pocketing the striker, pocketing your own last coin while the
///   Queen is still on the board, pocketing your opponent's last coin, and
///   hitting a coin behind your own baseline with the striker before it has
///   touched a cushion. Covering the Queen with your last coin, in the same
///   shot or the next one, is legal and wins the board. On a foul your coins from that
///   shot, the queen (if she went down or was awaiting cover) and the
///   opponent's last coin come back to the centre, you pay one penalty coin,
///   and your turn ends. With no coin to pay, the penalty becomes due and is
///   taken from the next coin you pocket.
/// - The queen may only be pocketed once you have pocketed a coin of your own;
///   she must be covered by pocketing one of your coins on the same or the
///   next shot, otherwise she returns to the centre.
/// - The first player to pocket all nine coins (with the queen covered) wins
///   the board, scoring 1 per opponent coin left plus 3 if they covered the
///   queen. The Queen's 3 only count while the winner has under 22 points.
/// - A match is the first to 25 points, or the leader after 8 boards (more
///   boards are played while it is tied). The break alternates each board.
class CarromGame {
  static const int coinsPerPlayer = 9;
  static const int matchPoints = 25;
  static const int matchBoards = 8;

  /// The Queen's points only count for a player below this match score.
  static const int queenPointsLimit = 22;

  CarromGame({Random? random}) : _random = random ?? Random() {
    reset();
  }

  final Random _random;
  late List<CarromPiece> coins;
  late CarromPiece striker;

  CarromPhase phase = CarromPhase.aiming;
  int currentPlayer = 0;
  bool vsBot = true;

  /// Coins of each player's own colour that are in a pocket.
  final List<List<CarromPiece>> pocketed = [[], []];
  int? queenCoveredBy;

  /// Player who pocketed the queen and still has to cover her.
  int? queenPendingFor;

  /// Penalty coins a player owes from fouls committed with nothing pocketed;
  /// each is paid back from the next coin they pocket.
  final List<int> penaltyDue = [0, 0];

  /// Match points so far, and the board being played (1-based).
  final List<int> matchScore = [0, 0];
  int board = 1;

  /// Who won the last finished board, and the points it gave them.
  int? boardWinner;
  int boardPoints = 0;

  /// The match winner and their match points, once the match is over.
  int? winner;
  int winnerPoints = 0;
  String status = '';
  double strikerX = 0.5;

  final List<CarromPiece> _pocketedThisShot = [];
  double _shotSeconds = 0;
  StrikerContact _contact = StrikerContact();

  /// Coins behind the shooter's baseline when the shot was played.
  Set<int> _behindBaseline = const {};

  static const List<String> _names = ['You', 'Bot'];

  String nameOf(int player) =>
      player == 0 ? _names[0] : (vsBot ? _names[1] : 'Player 2');

  static CarromPieceType colorOf(int player) =>
      player == 0 ? CarromPieceType.white : CarromPieceType.black;

  List<CarromPiece> get allPieces => [...coins, striker];
  CarromPiece get queen =>
      coins.firstWhere((c) => c.type == CarromPieceType.queen);

  bool get isBotTurn =>
      vsBot && currentPlayer == 1 && phase == CarromPhase.aiming;
  bool get isHumanAiming => phase == CarromPhase.aiming && !isBotTurn;

  int remaining(int player) =>
      coins.where((c) => c.type == colorOf(player) && !c.pocketed).length;

  bool get hasStarted =>
      board > 1 ||
      coins.any((c) => c.pocketed) ||
      coins.any((c) => (c.x - 0.5).abs() > 0.2 || (c.y - 0.5).abs() > 0.2);

  /// Starts a new match.
  void reset() {
    matchScore[0] = 0;
    matchScore[1] = 0;
    board = 1;
    boardWinner = null;
    boardPoints = 0;
    winner = null;
    winnerPoints = 0;
    _layOutBoard();
    status =
        'Your break! Slide the striker along your baseline, then drag back anywhere on the board and let go to shoot.';
  }

  /// The player who breaks on [board]: the break alternates.
  int get breaker => (board - 1) % 2;

  /// Sets the coins out for the current board, with its breaker to shoot.
  void _layOutBoard() {
    coins = _initialLayout();
    striker = CarromPiece(
        id: 99,
        type: CarromPieceType.striker,
        x: 0.5,
        y: CarromBoard.baselineY(breaker));
    pocketed[0].clear();
    pocketed[1].clear();
    queenCoveredBy = null;
    queenPendingFor = null;
    penaltyDue[0] = 0;
    penaltyDue[1] = 0;
    currentPlayer = breaker;
    phase = CarromPhase.aiming;
    _pocketedThisShot.clear();
    _setUpStriker();
  }

  /// Queen in the middle, a ring of 6 and a ring of 12, colours alternating.
  static List<CarromPiece> _initialLayout() {
    const r = CarromBoard.coinRadius * 1.02;
    final pieces = <CarromPiece>[
      CarromPiece(id: 0, type: CarromPieceType.queen, x: 0.5, y: 0.5)
    ];
    var id = 1;
    for (int i = 0; i < 6; i++) {
      final a = pi / 2 + i * pi / 3;
      pieces.add(CarromPiece(
        id: id++,
        type: i.isEven ? CarromPieceType.white : CarromPieceType.black,
        x: 0.5 + cos(a) * 2 * r,
        y: 0.5 + sin(a) * 2 * r,
      ));
    }
    for (int i = 0; i < 12; i++) {
      final a = pi / 2 + i * pi / 6;
      pieces.add(CarromPiece(
        id: id++,
        type: i.isEven ? CarromPieceType.black : CarromPieceType.white,
        x: 0.5 + cos(a) * 4 * r,
        y: 0.5 + sin(a) * 4 * r,
      ));
    }
    return pieces;
  }

  // --- STRIKER PLACEMENT & SHOOTING ---

  bool _overlapsCoin(double x, double y, double radius, {CarromPiece? ignore}) {
    for (final c in coins) {
      if (c.pocketed || identical(c, ignore)) continue;
      final dx = c.x - x;
      final dy = c.y - y;
      final minDist = c.radius + radius;
      if (dx * dx + dy * dy < minDist * minDist) return true;
    }
    return false;
  }

  /// The striker may sit anywhere on the baseline where it doesn't touch a coin.
  bool canPlaceStriker(double x) {
    final clamped = x.clamp(CarromBoard.baselineMin, CarromBoard.baselineMax);
    return !_overlapsCoin(clamped, CarromBoard.baselineY(currentPlayer),
        CarromBoard.strikerRadius);
  }

  bool get strikerPlacementValid => canPlaceStriker(strikerX);

  void placeStriker(double x) {
    if (phase != CarromPhase.aiming) return;
    strikerX = x.clamp(CarromBoard.baselineMin, CarromBoard.baselineMax);
    striker
      ..pocketed = false
      ..vx = 0
      ..vy = 0
      ..x = strikerX
      ..y = CarromBoard.baselineY(currentPlayer);
  }

  void _setUpStriker() {
    // Start in the middle, sliding outwards until the spot is free.
    for (int i = 0; i <= 30; i++) {
      final offset = (i + 1) ~/ 2 * 0.02 * (i.isOdd ? 1 : -1);
      final x = 0.5 + offset;
      if (x < CarromBoard.baselineMin || x > CarromBoard.baselineMax) continue;
      strikerX = x;
      if (canPlaceStriker(x)) break;
    }
    phase = CarromPhase.aiming;
    placeStriker(strikerX);
  }

  /// Fires the striker. Returns false if it can't be played from its spot.
  bool shoot(double angle, double power) {
    if (phase != CarromPhase.aiming || !strikerPlacementValid) return false;
    placeStriker(strikerX);
    final speed = CarromBoard.shotSpeed(power);
    striker
      ..vx = cos(angle) * speed
      ..vy = sin(angle) * speed;
    _pocketedThisShot.clear();
    _shotSeconds = 0;
    _contact = StrikerContact();
    _behindBaseline = {
      for (final c in coins)
        if (!c.pocketed && CarromBoard.isBehindBaseline(c, currentPlayer)) c.id
    };
    phase = CarromPhase.moving;
    status =
        '${nameOf(currentPlayer)} ${currentPlayer == 0 ? 'shoot' : 'shoots'}...';
    return true;
  }

  /// Advances a moving shot by [seconds]. Returns true once everything has
  /// stopped and the shot has been scored.
  bool advance(double seconds) {
    if (phase != CarromPhase.moving) return false;
    final steps = max(1, (seconds / CarromBoard.stepSeconds).round());
    final pieces = allPieces;
    for (int i = 0; i < steps; i++) {
      _pocketedThisShot.addAll(CarromBoard.step(pieces, _contact));
      _shotSeconds += CarromBoard.stepSeconds;
      if (CarromBoard.isSettled(pieces) || _shotSeconds > 20) {
        for (final p in pieces) {
          p
            ..vx = 0
            ..vy = 0;
        }
        scoreShot(List.of(_pocketedThisShot));
        return true;
      }
    }
    return false;
  }

  /// Plays the current shot out instantly (used by the bot search and tests).
  void simulateToRest() {
    while (phase == CarromPhase.moving) {
      advance(0.5);
    }
  }

  // --- SCORING ---

  /// Applies the ICF rules to the pieces that went down during the shot just played.
  void scoreShot(List<CarromPiece> pocketedThisShot) {
    final player = currentPlayer;
    final opp = 1 - player;
    final messages = <String>[];
    final who = nameOf(player);
    final whose = '$who${player == 0 ? 'r' : "'s"}';

    final ownNow =
        pocketedThisShot.where((p) => p.type == colorOf(player)).toList();
    final oppNow =
        pocketedThisShot.where((p) => p.type == colorOf(opp)).toList();
    var queenNow = pocketedThisShot.any((p) => p.type == CarromPieceType.queen);
    final queenWasCovered = queenCoveredBy != null;

    pocketed[player].addAll(ownNow);
    pocketed[opp].addAll(oppNow);

    // --- Fouls (ICF) ---
    final fouls = <String>[];
    if (pocketedThisShot.any((p) => p.type == CarromPieceType.striker)) {
      fouls.add('striker pocketed');
    }
    // Your last coin may cover the Queen, pocketed this shot or awaiting cover.
    final coversQueen =
        ownNow.isNotEmpty && (queenNow || queenPendingFor == player);
    if (ownNow.isNotEmpty &&
        remaining(player) == 0 &&
        !queenWasCovered &&
        !coversQueen) {
      fouls.add('last coin pocketed before the Queen was covered');
    }
    final firstHit = _contact.firstCoinId;
    if (firstHit != null &&
        !_contact.cushionFirst &&
        _behindBaseline.contains(firstHit)) {
      fouls.add('a coin behind the baseline was hit directly');
    }
    if (oppNow.isNotEmpty && remaining(opp) == 0) {
      fouls.add("${nameOf(opp)}${opp == 0 ? 'r' : "'s"} last coin pocketed");
    }

    if (fouls.isNotEmpty) {
      // Everything of yours from this shot comes back, the Queen too, and
      // the opponent's last coin if that was the foul.
      for (final c in ownNow) {
        pocketed[player].remove(c);
        _returnToCentre(c);
      }
      if (oppNow.isNotEmpty && remaining(opp) == 0) {
        _returnToCentre(pocketed[opp].removeLast());
      }
      if (queenNow || queenPendingFor == player) {
        _returnToCentre(queen);
        queenNow = false;
        queenPendingFor = null;
      }
      final penalty = _takePenalty(player);
      messages.add('Foul - ${fouls.join(', ')}! $penalty');
      currentPlayer = opp;
      _finishTurn(messages, continueTurn: false, shooter: player);
      return;
    }

    // --- Legal shot ---
    if (queenNow && pocketed[player].isEmpty) {
      // You need a coin of your own pocketed (this shot counts) before taking the Queen.
      _returnToCentre(queen);
      queenNow = false;
      messages.add(
          'The Queen can only be taken after pocketing a coin of your own - she returns to the centre.');
    }

    if (queenNow) {
      if (ownNow.isNotEmpty) {
        queenCoveredBy = player;
        queenPendingFor = null;
        messages.add('$who covered the Queen! (+3)');
      } else {
        queenPendingFor = player;
        messages.add(
            'Queen pocketed! Pocket one of your coins next shot to cover her.');
      }
    } else if (queenPendingFor == player) {
      if (ownNow.isNotEmpty) {
        queenCoveredBy = player;
        messages.add('$who covered the Queen! (+3)');
      } else {
        _returnToCentre(queen);
        messages.add('Queen not covered - she returns to the centre.');
      }
      queenPendingFor = null;
    }

    if (ownNow.isNotEmpty) {
      messages.add(
          '$who pocketed ${ownNow.length} coin${ownNow.length == 1 ? '' : 's'}.');
    }
    if (oppNow.isNotEmpty) {
      messages.add(
          '${oppNow.length} ${opp == 0 ? 'white' : 'black'} coin${oppNow.length == 1 ? '' : 's'} '
          'went down for ${nameOf(opp)}.');
    }

    // A penalty owed from an earlier foul is paid from the coins just pocketed.
    var paid = 0;
    while (penaltyDue[player] > 0 &&
        ownNow.isNotEmpty &&
        pocketed[player].isNotEmpty) {
      _returnToCentre(pocketed[player].removeLast());
      penaltyDue[player]--;
      paid++;
    }
    if (paid > 0) {
      messages.add(
          '$paid due penalty coin${paid == 1 ? '' : 's'} of $whose returned to the centre.');
    }

    for (final p in [player, opp]) {
      if (remaining(p) == 0 && queenCoveredBy != null) {
        _finishBoard(p, messages);
        return;
      }
    }

    final continueTurn =
        ownNow.isNotEmpty || (queenNow && queenPendingFor == player);
    if (!continueTurn) {
      if (queenPendingFor == player) {
        _returnToCentre(queen);
        queenPendingFor = null;
        messages.add('Queen not covered - she returns to the centre.');
      }
      if (messages.isEmpty) messages.add('Nothing pocketed.');
      currentPlayer = opp;
    }
    _finishTurn(messages, continueTurn: continueTurn, shooter: player);
  }

  /// Scores the board for [p], then ends the match or lays out the next board.
  void _finishBoard(int p, List<String> messages) {
    final queenBonus =
        queenCoveredBy == p && matchScore[p] < queenPointsLimit ? 3 : 0;
    final points = remaining(1 - p) + queenBonus;
    matchScore[p] += points;
    boardWinner = p;
    boardPoints = points;
    messages.add('${nameOf(p)} ${p == 0 ? 'win' : 'wins'} board $board '
        'with $points point${points == 1 ? '' : 's'} '
        '(${matchScore[0]}-${matchScore[1]}).');

    final decided = matchScore[p] >= matchPoints ||
        (board >= matchBoards && matchScore[0] != matchScore[1]);
    if (decided) {
      final w = matchScore[0] > matchScore[1] ? 0 : 1;
      winner = w;
      winnerPoints = matchScore[w];
      phase = CarromPhase.gameOver;
      status = '${messages.join(' ')} '
          '${nameOf(w)} ${w == 0 ? 'win' : 'wins'} the match!';
      return;
    }
    board++;
    _layOutBoard();
    final who = breaker == 0 ? 'Your break.' : '${nameOf(breaker)} breaks.';
    status = '${messages.join(' ')} Board $board: $who';
  }

  /// Returns one of [player]'s pocketed coins to the centre, or records it as
  /// due when they have none. Returns the message to show.
  String _takePenalty(int player) {
    final whose = '${nameOf(player)}${player == 0 ? 'r' : "'s"}';
    if (pocketed[player].isNotEmpty) {
      _returnToCentre(pocketed[player].removeLast());
      return 'One of $whose coins goes back to the centre as a penalty.';
    }
    penaltyDue[player]++;
    return 'A penalty coin is now due from $whose next pocketed coin.';
  }

  void _finishTurn(List<String> messages,
      {required bool continueTurn, required int shooter}) {
    _setUpStriker();
    final next =
        currentPlayer == 0 ? 'Your turn.' : "${nameOf(currentPlayer)}'s turn.";
    status = '${messages.join(' ')} '
        '${continueTurn ? '${nameOf(shooter)} ${shooter == 0 ? 'shoot' : 'shoots'} again!' : next}';
  }

  /// Puts a coin back on the board as close to the centre as possible.
  void _returnToCentre(CarromPiece coin) {
    coin
      ..pocketed = false
      ..vx = 0
      ..vy = 0;
    for (int ring = 0; ring < 12; ring++) {
      final steps = ring == 0 ? 1 : 6 * ring;
      for (int k = 0; k < steps; k++) {
        final a = 2 * pi * k / steps;
        final x = 0.5 + cos(a) * ring * CarromBoard.coinRadius * 2.1;
        final y = 0.5 + sin(a) * ring * CarromBoard.coinRadius * 2.1;
        if (!_overlapsCoin(x, y, coin.radius, ignore: coin)) {
          coin
            ..x = x
            ..y = y;
          return;
        }
      }
    }
  }

  // --- BOT ---

  CarromBotRequest botRequest({double aimNoise = 0.01}) => CarromBotRequest(
        coins: [for (final c in coins) c.copy()],
        player: currentPlayer,
        ownPocketed: pocketed[currentPlayer].length,
        queenCovered: queenCoveredBy != null,
        queenPending: queenPendingFor == currentPlayer,
        aimNoise: aimNoise,
        seed: _random.nextInt(1 << 30),
      );
}

/// Plain data for the bot search, so it can run in another isolate.
class CarromBotRequest {
  const CarromBotRequest({
    required this.coins,
    required this.player,
    required this.ownPocketed,
    required this.queenCovered,
    this.queenPending = false,
    required this.aimNoise,
    required this.seed,
  });

  final List<CarromPiece> coins;
  final int player;
  final int ownPocketed;
  final bool queenCovered;

  /// The player pocketed the Queen last shot and must cover her now.
  final bool queenPending;
  final double aimNoise;
  final int seed;
}

/// Top-level entry point for `compute`.
CarromShot carromBotWorker(CarromBotRequest request) =>
    CarromBot.chooseShot(request);

class CarromBot {
  /// Share of the striker's speed along the line of centres that a resting
  /// coin picks up: (1 + e) * striker mass / (striker mass + coin mass).
  static const double _transfer = (1 + CarromBoard.pieceRestitution) *
      CarromBoard.strikerMass /
      (CarromBoard.strikerMass + 1);

  static double _powerFor(double launchSpeed) =>
      (launchSpeed - CarromBoard.minShotSpeed) /
      (CarromBoard.maxShotSpeed - CarromBoard.minShotSpeed);

  static double _launchFor(double power) => CarromBoard.shotSpeed(power);

  /// Picks the shot whose simulated outcome scores best, then adds a small
  /// aiming error so the bot is beatable.
  static CarromShot chooseShot(CarromBotRequest request) {
    final random = Random(request.seed);
    final player = request.player;
    final own = CarromGame.colorOf(player);
    final opp = CarromGame.colorOf(1 - player);
    final baseY = CarromBoard.baselineY(player);
    final active = request.coins.where((c) => !c.pocketed).toList();

    bool strikerFits(double x) => active.every((c) {
          final dx = c.x - x;
          final dy = c.y - baseY;
          final minDist = c.radius + CarromBoard.strikerRadius;
          return dx * dx + dy * dy >= minDist * minDist;
        });

    bool segmentClear(double ax, double ay, double bx, double by,
        double clearance, Set<CarromPiece> ignore) {
      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;
      if (lenSq == 0) return true;
      for (final c in active) {
        if (ignore.contains(c)) continue;
        final t = (((c.x - ax) * dx + (c.y - ay) * dy) / lenSq).clamp(0.0, 1.0);
        final px = ax + dx * t - c.x;
        final py = ay + dy * t - c.y;
        if (px * px + py * py < clearance * clearance) return false;
      }
      return true;
    }

    final ownLeft = active.where((c) => c.type == own).length;
    final oppLeft = active.where((c) => c.type == opp).length;
    // The last coin may only go down once the Queen is covered, or to cover her.
    final lastCoinLocked =
        ownLeft == 1 && !request.queenCovered && !request.queenPending;
    final targets = active
        .where((c) =>
            (c.type == own && !lastCoinLocked) ||
            (c.type == CarromPieceType.queen && request.ownPocketed > 0))
        .toList();
    final xs = [
      for (int i = 0; i <= 12; i++)
        CarromBoard.baselineMin +
            i * (CarromBoard.baselineMax - CarromBoard.baselineMin) / 12
    ];

    final geometric = <(double, CarromShot)>[];
    for (final t in targets) {
      for (final pocket in CarromBoard.pockets) {
        final toPocketX = pocket.$1 - t.x;
        final toPocketY = pocket.$2 - t.y;
        final pocketDist = sqrt(toPocketX * toPocketX + toPocketY * toPocketY);
        final ux = toPocketX / pocketDist;
        final uy = toPocketY / pocketDist;
        final ghostX = t.x - ux * (t.radius + CarromBoard.strikerRadius);
        final ghostY = t.y - uy * (t.radius + CarromBoard.strikerRadius);
        if (!segmentClear(t.x, t.y, pocket.$1, pocket.$2, t.radius * 2, {t})) {
          continue;
        }

        for (final x in xs) {
          if (!strikerFits(x)) continue;
          final ax = ghostX - x;
          final ay = ghostY - baseY;
          final aimDist = sqrt(ax * ax + ay * ay);
          if (aimDist < 0.01) continue;
          final cut = (ax * ux + ay * uy) / aimDist;
          if (cut < 0.35) continue; // thinner than about 70 degrees
          if (!segmentClear(x, baseY, ghostX, ghostY,
              t.radius + CarromBoard.strikerRadius, {t})) {
            continue;
          }
          final angle = atan2(ay, ax);
          // Softest striker speed that still carries the coin into the pocket:
          // friction over both legs plus the momentum handed over at the hit.
          final coinSpeed =
              sqrt(2 * CarromBoard.friction * pocketDist) * 1.25 + 0.1;
          final strikerAtHit = coinSpeed / (_transfer * cut);
          final launch = sqrt(
              strikerAtHit * strikerAtHit + 2 * CarromBoard.friction * aimDist);
          final power = _powerFor(launch);
          if (power > 1) continue;
          final score = cut * 2 -
              pocketDist -
              aimDist * 0.5 +
              (t.type == CarromPieceType.queen ? 0.3 : 0);
          geometric.add((score, CarromShot(x: x, angle: angle, power: power)));
        }
      }
    }
    geometric.sort((a, b) => b.$1.compareTo(a.$1));

    final candidates = <CarromShot>[
      for (final g in geometric.take(30))
        for (final boost in const [1.0, 1.12, 1.3])
          CarromShot(
            x: g.$2.x,
            angle: g.$2.angle,
            power: _powerFor(_launchFor(g.$2.power) * boost).clamp(0.0, 1.0),
          ),
    ];
    // Fallbacks: break shots into the pile from a few spots.
    final centreX = active.isEmpty
        ? 0.5
        : active.map((c) => c.x).reduce((a, b) => a + b) / active.length;
    final centreY = active.isEmpty
        ? 0.5
        : active.map((c) => c.y).reduce((a, b) => a + b) / active.length;
    for (final x in [0.5, 0.35, 0.65, 0.25, 0.75]) {
      if (!strikerFits(x)) continue;
      for (final power in [0.6, 0.95]) {
        candidates.add(CarromShot(
            x: x, angle: atan2(centreY - baseY, centreX - x), power: power));
      }
    }
    if (candidates.isEmpty) {
      final x = xs.firstWhere(strikerFits, orElse: () => 0.5);
      return CarromShot(
          x: x, angle: player == 0 ? -pi / 2 : pi / 2, power: 0.6);
    }

    CarromShot best = candidates.first;
    var bestScore = double.negativeInfinity;
    for (final shot in candidates) {
      final pieces = [for (final c in request.coins) c.copy()];
      final striker = CarromPiece(
          id: 99, type: CarromPieceType.striker, x: shot.x, y: baseY);
      final speed = CarromBoard.shotSpeed(shot.power);
      striker
        ..vx = cos(shot.angle) * speed
        ..vy = sin(shot.angle) * speed;
      final contact = StrikerContact();
      final dropped = CarromBoard.simulateToRest([...pieces, striker],
          maxSeconds: 12, contact: contact);
      final strikerFoul = dropped.any((p) => p.type == CarromPieceType.striker);
      final ownDown = dropped.where((p) => p.type == own).length;
      final oppDown = dropped.where((p) => p.type == opp).length;
      final queenDown = dropped.any((p) => p.type == CarromPieceType.queen);
      var score = ownDown * 10.0 -
          oppDown * 7.0 +
          (queenDown ? (request.ownPocketed > 0 ? 6.0 : -2.0) : 0);
      final coversQueen = queenDown || request.queenPending;
      final lastCoinFoul = (ownDown > 0 &&
              ownDown >= ownLeft &&
              !request.queenCovered &&
              !coversQueen) ||
          (oppDown > 0 && oppDown >= oppLeft);
      final hit = contact.firstCoinId;
      final directHitFoul = hit != null &&
          !contact.cushionFirst &&
          active.any(
              (c) => c.id == hit && CarromBoard.isBehindBaseline(c, player));
      if (strikerFoul || lastCoinFoul || directHitFoul) {
        score -= 15 + ownDown * 10.0;
      }
      score += random.nextDouble() * 0.5;
      if (score > bestScore) {
        bestScore = score;
        best = shot;
      }
    }

    // Human-like aiming error.
    final noise = (random.nextDouble() * 2 - 1) * request.aimNoise;
    return CarromShot(x: best.x, angle: best.angle + noise, power: best.power);
  }
}
