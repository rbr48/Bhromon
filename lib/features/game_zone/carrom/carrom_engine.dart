import 'dart:math';

enum CarromPieceType { white, black, queen, striker }

/// A coin or the striker. Positions are in board units: the playing surface
/// spans 0..1 on both axes, with (0, 0) at the top-left pocket.
class CarromPiece {
  CarromPiece({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
  })  : radius = type == CarromPieceType.striker
            ? CarromBoard.strikerRadius
            : CarromBoard.coinRadius,
        mass = type == CarromPieceType.striker ? CarromBoard.strikerMass : 1.0;

  final int id;
  final CarromPieceType type;
  final double radius;
  final double mass;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool pocketed = false;

  bool get isMoving => vx != 0 || vy != 0;
  double get speed => sqrt(vx * vx + vy * vy);

  CarromPiece copy() => CarromPiece(id: id, type: type, x: x, y: y)
    ..vx = vx
    ..vy = vy
    ..pocketed = pocketed;
}

/// What the striker touched first during a shot. The rules use it to tell a
/// legal shot from a direct hit on a coin behind the shooter's baseline.
class StrikerContact {
  /// The first coin the striker hit, or null if it has hit none yet.
  int? firstCoinId;

  /// Whether the striker touched a cushion before hitting [firstCoinId].
  bool cushionFirst = false;
}

/// Board geometry and a deterministic fixed-step physics simulation.
///
/// Sizes follow the ICF board (74 cm playing surface): coins 3.18 cm,
/// striker 4.13 cm, pockets 4.45 cm. The striker is about 2.6x a coin's mass.
class CarromBoard {
  static const double coinRadius = 0.0215;
  static const double strikerRadius = 0.028;
  static const double pocketRadius = 0.031;
  static const double strikerMass = 2.6;

  /// Sliding friction, in board units per second squared.
  static const double friction = 1.1;
  static const double wallRestitution = 0.7;
  static const double pieceRestitution = 0.9;

  /// Distance of each player's baseline from their edge, and its extent.
  static const double baselineInset = 0.155;
  static const double baselineMin = 0.19;
  static const double baselineMax = 0.81;

  static const double minShotSpeed = 0.35;
  static const double maxShotSpeed = 3.4;

  /// A slingshot pull this long, in board widths, is a full-power shot.
  static const double fullPowerPull = 0.3;

  /// A pull below this share of full power is not a shot.
  static const double minPullPower = 0.05;

  /// Shot power for a slingshot pull of [pull] board widths, or null when the
  /// pull is too short to count. Both the offline and the online board use it.
  static double? powerForPull(double pull) {
    final power = (pull / fullPowerPull).clamp(0.0, 1.0);
    return power < minPullPower ? null : power;
  }

  static const double stepSeconds = 1 / 480;
  static const double restSpeed = 0.004;

  /// A piece crossing a pocket faster than this rattles off the lip instead
  /// of dropping in.
  static const double maxPocketSpeed = 2.6;

  static const List<(double, double)> pockets = [
    (pocketRadius, pocketRadius),
    (1 - pocketRadius, pocketRadius),
    (pocketRadius, 1 - pocketRadius),
    (1 - pocketRadius, 1 - pocketRadius),
  ];

  /// Player 0 shoots from the bottom baseline, player 1 from the top.
  static double baselineY(int player) =>
      player == 0 ? 1 - baselineInset : baselineInset;

  /// Whether [coin] lies behind [player]'s baseline, between it and their
  /// edge. The striker may only reach such a coin off a cushion.
  static bool isBehindBaseline(CarromPiece coin, int player) =>
      player == 0 ? coin.y > baselineY(0) : coin.y < baselineY(1);

  /// Speed given to the striker for a shot power in 0..1.
  static double shotSpeed(double power) =>
      minShotSpeed + power.clamp(0.0, 1.0) * (maxShotSpeed - minShotSpeed);

  static bool isSettled(Iterable<CarromPiece> pieces) {
    for (final p in pieces) {
      if (!p.pocketed && p.isMoving) return false;
    }
    return true;
  }

  /// Advances every piece by one fixed step and returns the pieces that
  /// dropped into a pocket during it. [contact] records what the striker
  /// touched first.
  static List<CarromPiece> step(List<CarromPiece> pieces,
      [StrikerContact? contact]) {
    const dt = stepSeconds;
    final len = pieces.length;

    for (int i = 0; i < len; i++) {
      final p = pieces[i];
      if (p.pocketed || !p.isMoving) continue;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }

    for (int i = 0; i < len; i++) {
      final a = pieces[i];
      if (a.pocketed) continue;
      for (int j = i + 1; j < len; j++) {
        final b = pieces[j];
        if (b.pocketed) continue;
        if (!a.isMoving && !b.isMoving) continue;
        final hit = _collide(a, b);
        if (hit && contact != null && contact.firstCoinId == null) {
          if (a.type == CarromPieceType.striker) {
            contact.firstCoinId = b.id;
          } else if (b.type == CarromPieceType.striker) {
            contact.firstCoinId = a.id;
          }
        }
      }
    }

    for (int i = 0; i < len; i++) {
      final p = pieces[i];
      if (p.pocketed) continue;
      final bounced = _bounceOffWalls(p);
      if (bounced &&
          contact != null &&
          contact.firstCoinId == null &&
          p.type == CarromPieceType.striker) {
        contact.cushionFirst = true;
      }
    }

    List<CarromPiece>? dropped;
    for (int i = 0; i < len; i++) {
      final p = pieces[i];
      if (p.pocketed) continue;
      for (final pocket in pockets) {
        final dx = p.x - pocket.$1;
        final dy = p.y - pocket.$2;
        if (dx * dx + dy * dy < pocketRadius * pocketRadius &&
            p.speed <= maxPocketSpeed) {
          p
            ..pocketed = true
            ..vx = 0
            ..vy = 0
            ..x = pocket.$1
            ..y = pocket.$2;
          (dropped ??= <CarromPiece>[]).add(p);
          break;
        }
      }
    }

    for (int i = 0; i < len; i++) {
      final p = pieces[i];
      if (p.pocketed || !p.isMoving) continue;
      final speed = p.speed;
      final slowed = speed - friction * dt;
      if (slowed <= restSpeed) {
        p
          ..vx = 0
          ..vy = 0;
      } else {
        final scale = slowed / speed;
        p
          ..vx *= scale
          ..vy *= scale;
      }
    }
    return dropped ?? const <CarromPiece>[];
  }

  /// Separates two overlapping pieces. Returns true when they were moving
  /// towards each other, so momentum changed hands.
  static bool _collide(CarromPiece a, CarromPiece b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final minDist = a.radius + b.radius;
    final distSq = dx * dx + dy * dy;
    if (distSq >= minDist * minDist || distSq == 0) return false;

    final dist = sqrt(distSq);
    final nx = dx / dist;
    final ny = dy / dist;
    final invA = 1 / a.mass;
    final invB = 1 / b.mass;

    // Push the pieces apart so they no longer overlap.
    final overlap = minDist - dist;
    final share = overlap / (invA + invB);
    a
      ..x -= nx * share * invA
      ..y -= ny * share * invA;
    b
      ..x += nx * share * invB
      ..y += ny * share * invB;

    // Exchange momentum along the line of centres if they are approaching.
    final approach = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
    if (approach <= 0) return false;
    final impulse = (1 + pieceRestitution) * approach / (invA + invB);
    a
      ..vx -= impulse * invA * nx
      ..vy -= impulse * invA * ny;
    b
      ..vx += impulse * invB * nx
      ..vy += impulse * invB * ny;
    return true;
  }

  /// Keeps a piece on the board. Returns true when it bounced off a cushion.
  static bool _bounceOffWalls(CarromPiece p) {
    final r = p.radius;
    var bounced = false;
    if (p.x < r) {
      p.x = r;
      if (p.vx < 0) {
        p.vx = -p.vx * wallRestitution;
        bounced = true;
      }
    } else if (p.x > 1 - r) {
      p.x = 1 - r;
      if (p.vx > 0) {
        p.vx = -p.vx * wallRestitution;
        bounced = true;
      }
    }
    if (p.y < r) {
      p.y = r;
      if (p.vy < 0) {
        p.vy = -p.vy * wallRestitution;
        bounced = true;
      }
    } else if (p.y > 1 - r) {
      p.y = 1 - r;
      if (p.vy > 0) {
        p.vy = -p.vy * wallRestitution;
        bounced = true;
      }
    }
    return bounced;
  }

  /// Runs [pieces] until everything has stopped (or [maxSeconds] passes) and
  /// returns every piece pocketed on the way, in order.
  static List<CarromPiece> simulateToRest(
    List<CarromPiece> pieces, {
    double maxSeconds = 20,
    StrikerContact? contact,
  }) {
    final dropped = <CarromPiece>[];
    final maxSteps = (maxSeconds / stepSeconds).ceil();
    for (int i = 0; i < maxSteps; i++) {
      dropped.addAll(step(pieces, contact));
      if (isSettled(pieces)) return dropped;
    }
    for (final p in pieces) {
      p
        ..vx = 0
        ..vy = 0;
    }
    return dropped;
  }
}
