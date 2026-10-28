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

  static const double stepSeconds = 1 / 480;
  static const double restSpeed = 0.004;

  static const List<(double, double)> pockets = [
    (pocketRadius, pocketRadius),
    (1 - pocketRadius, pocketRadius),
    (pocketRadius, 1 - pocketRadius),
    (1 - pocketRadius, 1 - pocketRadius),
  ];

  /// Player 0 shoots from the bottom baseline, player 1 from the top.
  static double baselineY(int player) =>
      player == 0 ? 1 - baselineInset : baselineInset;

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
  /// dropped into a pocket during it.
  static List<CarromPiece> step(List<CarromPiece> pieces) {
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
        _collide(a, b);
      }
    }

    for (int i = 0; i < len; i++) {
      final p = pieces[i];
      if (p.pocketed) continue;
      _bounceOffWalls(p);
    }

    List<CarromPiece>? dropped;
    for (int i = 0; i < len; i++) {
      final p = pieces[i];
      if (p.pocketed) continue;
      for (final pocket in pockets) {
        final dx = p.x - pocket.$1;
        final dy = p.y - pocket.$2;
        if (dx * dx + dy * dy < pocketRadius * pocketRadius) {
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

  static void _collide(CarromPiece a, CarromPiece b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final minDist = a.radius + b.radius;
    final distSq = dx * dx + dy * dy;
    if (distSq >= minDist * minDist || distSq == 0) return;

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
    if (approach <= 0) return;
    final impulse = (1 + pieceRestitution) * approach / (invA + invB);
    a
      ..vx -= impulse * invA * nx
      ..vy -= impulse * invA * ny;
    b
      ..vx += impulse * invB * nx
      ..vy += impulse * invB * ny;
  }

  static void _bounceOffWalls(CarromPiece p) {
    final r = p.radius;
    if (p.x < r) {
      p.x = r;
      if (p.vx < 0) p.vx = -p.vx * wallRestitution;
    } else if (p.x > 1 - r) {
      p.x = 1 - r;
      if (p.vx > 0) p.vx = -p.vx * wallRestitution;
    }
    if (p.y < r) {
      p.y = r;
      if (p.vy < 0) p.vy = -p.vy * wallRestitution;
    } else if (p.y > 1 - r) {
      p.y = 1 - r;
      if (p.vy > 0) p.vy = -p.vy * wallRestitution;
    }
  }

  /// Runs [pieces] until everything has stopped (or [maxSeconds] passes) and
  /// returns every piece pocketed on the way, in order.
  static List<CarromPiece> simulateToRest(
    List<CarromPiece> pieces, {
    double maxSeconds = 20,
  }) {
    final dropped = <CarromPiece>[];
    final maxSteps = (maxSeconds / stepSeconds).ceil();
    for (int i = 0; i < maxSteps; i++) {
      dropped.addAll(step(pieces));
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
