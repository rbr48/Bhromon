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
/// - Pocket one of your own coins and you shoot again.
/// - Pocketing the striker is a foul: coins of yours pocketed on that shot
///   come back to the centre, plus one penalty coin, and your turn ends.
/// - The queen may only be pocketed once you have pocketed a coin of your own;
///   she must be covered by pocketing one of your coins on the same or the
///   next shot, otherwise she returns to the centre.
/// - Your last coin may not go down before the queen is covered; if it does,
///   it is returned to the centre.
/// - Opponent coins you pocket count for the opponent.
/// - The first player to pocket all nine coins (with the queen covered) wins
///   the board, scoring 1 per opponent coin left plus 3 if they covered the queen.
class CarromGame {
  static const int coinsPerPlayer = 9;

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

  int? winner;
  int winnerPoints = 0;
  String status = '';
  double strikerX = 0.5;

  final List<CarromPiece> _pocketedThisShot = [];
  double _shotSeconds = 0;

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
      coins.any((c) => c.pocketed) ||
      coins.any((c) => (c.x - 0.5).abs() > 0.2 || (c.y - 0.5).abs() > 0.2);

  void reset() {
    coins = _initialLayout();
    striker = CarromPiece(
        id: 99,
        type: CarromPieceType.striker,
        x: 0.5,
        y: CarromBoard.baselineY(0));
    pocketed[0].clear();
    pocketed[1].clear();
    queenCoveredBy = null;
    queenPendingFor = null;
    winner = null;
    winnerPoints = 0;
    currentPlayer = 0;
    phase = CarromPhase.aiming;
    _pocketedThisShot.clear();
    _setUpStriker();
    status =
        'Your break! Slide the striker along your baseline, then drag back anywhere on the board and let go to shoot.';
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
      _pocketedThisShot.addAll(CarromBoard.step(pieces));
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

  /// Applies the rules to the pieces that went down during the shot just played.
  void scoreShot(List<CarromPiece> pocketedThisShot) {
    final player = currentPlayer;
    final opp = 1 - player;
    final messages = <String>[];
    final who = nameOf(player);

    final strikerFoul =
        pocketedThisShot.any((p) => p.type == CarromPieceType.striker);
    final ownNow =
        pocketedThisShot.where((p) => p.type == colorOf(player)).toList();
    final oppNow =
        pocketedThisShot.where((p) => p.type == colorOf(opp)).toList();
    var queenNow = pocketedThisShot.any((p) => p.type == CarromPieceType.queen);

    pocketed[player].addAll(ownNow);
    pocketed[opp].addAll(oppNow);
    var foul = strikerFoul;

    if (strikerFoul) {
      for (final c in ownNow) {
        pocketed[player].remove(c);
        _returnToCentre(c);
      }
      ownNow.clear();
      if (pocketed[player].isNotEmpty) {
        _returnToCentre(pocketed[player].removeLast());
        messages.add(
            'Foul! Striker pocketed - one of $who${player == 0 ? 'r' : "'s"} coins goes back to the centre.');
      } else {
        messages.add('Foul! Striker pocketed.');
      }
      if (queenNow) {
        _returnToCentre(queen);
        queenNow = false;
      }
    }

    if (queenNow && pocketed[player].isEmpty) {
      // You need a coin of your own pocketed (this shot counts) before taking the queen.
      _returnToCentre(queen);
      queenNow = false;
      messages.add(
          'The queen can only be taken after pocketing a coin of your own - she returns to the centre.');
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
      if (!foul && ownNow.isNotEmpty) {
        queenCoveredBy = player;
        messages.add('$who covered the Queen! (+3)');
      } else {
        _returnToCentre(queen);
        messages.add('Queen not covered - she returns to the centre.');
      }
      queenPendingFor = null;
    }

    if (ownNow.isNotEmpty && !foul) {
      messages.add(
          '$who pocketed ${ownNow.length} coin${ownNow.length == 1 ? '' : 's'}.');
    }
    if (oppNow.isNotEmpty) {
      messages.add(
          '${oppNow.length} ${opp == 0 ? 'white' : 'black'} coin${oppNow.length == 1 ? '' : 's'} went down for ${nameOf(opp)}.');
    }

    // A player's last coin can't go down before the queen is covered.
    if (queenCoveredBy == null) {
      for (final p in [player, opp]) {
        if (remaining(p) == 0 && pocketed[p].isNotEmpty) {
          _returnToCentre(pocketed[p].removeLast());
          messages.add(
              "The queen must be covered first - ${nameOf(p)}${p == 0 ? 'r' : "'s"} last coin goes back.");
          if (p == player) foul = true;
        }
      }
    }

    for (final p in [player, opp]) {
      if (remaining(p) == 0 && queenCoveredBy != null) {
        winner = p;
        winnerPoints = remaining(1 - p) + (queenCoveredBy == p ? 3 : 0);
        phase = CarromPhase.gameOver;
        status =
            '${messages.join(' ')} ${nameOf(p)} ${p == 0 ? 'win' : 'wins'} the board with $winnerPoints points!'
                .trim();
        return;
      }
    }

    final continueTurn =
        !foul && (ownNow.isNotEmpty || (queenNow && queenPendingFor == player));
    if (!continueTurn) {
      if (queenPendingFor == player) {
        _returnToCentre(queen);
        queenPendingFor = null;
        messages.add('Queen not covered - she returns to the centre.');
      }
      if (messages.isEmpty) messages.add('Nothing pocketed.');
      currentPlayer = opp;
    }

    _setUpStriker();
    final next =
        currentPlayer == 0 ? 'Your turn.' : "${nameOf(currentPlayer)}'s turn.";
    status =
        '${messages.join(' ')} ${continueTurn ? '${nameOf(player)} ${player == 0 ? 'shoot' : 'shoots'} again!' : next}';
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
    required this.aimNoise,
    required this.seed,
  });

  final List<CarromPiece> coins;
  final int player;
  final int ownPocketed;
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

    final targets = active
        .where((c) =>
            c.type == own ||
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
      final dropped =
          CarromBoard.simulateToRest([...pieces, striker], maxSeconds: 12);
      final strikerFoul = dropped.any((p) => p.type == CarromPieceType.striker);
      final ownDown = dropped.where((p) => p.type == own).length;
      final oppDown = dropped.where((p) => p.type == opp).length;
      final queenDown = dropped.any((p) => p.type == CarromPieceType.queen);
      var score = ownDown * 10.0 -
          oppDown * 7.0 +
          (queenDown ? (request.ownPocketed > 0 ? 6.0 : -2.0) : 0);
      if (strikerFoul) score -= 15;
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
