/**
 * Board geometry and the fixed-step physics of a carrom shot, ported from
 * lib/features/game_zone/carrom/carrom_engine.dart. The server is the only
 * place a shot is simulated, so the two versions only need to agree with each
 * other in what the rules say, not bit for bit. The arithmetic is kept in the
 * same order anyway, so the animation on the phone matches the stored result.
 *
 * Positions are in board units: the playing surface spans 0..1 on both axes,
 * with (0, 0) at the top-left pocket.
 */

export type PieceType = 'white' | 'black' | 'queen' | 'striker';

export interface Piece {
  id: number;
  type: PieceType;
  radius: number;
  mass: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  pocketed: boolean;
}

export const COIN_RADIUS = 0.0215;
export const STRIKER_RADIUS = 0.028;
export const POCKET_RADIUS = 0.031;
export const STRIKER_MASS = 2.6;

/** Sliding friction, in board units per second squared. */
export const FRICTION = 1.1;
export const WALL_RESTITUTION = 0.7;
export const PIECE_RESTITUTION = 0.9;

/** Distance of each player's baseline from their edge, and its extent. */
export const BASELINE_INSET = 0.155;
export const BASELINE_MIN = 0.19;
export const BASELINE_MAX = 0.81;

export const MIN_SHOT_SPEED = 0.35;
export const MAX_SHOT_SPEED = 3.4;

export const STEP_SECONDS = 1 / 480;
export const REST_SPEED = 0.004;

/** A shot that has not settled by then is scored as it stands. */
export const MAX_SHOT_SECONDS = 20;

export const POCKETS: ReadonlyArray<readonly [number, number]> = [
  [POCKET_RADIUS, POCKET_RADIUS],
  [1 - POCKET_RADIUS, POCKET_RADIUS],
  [POCKET_RADIUS, 1 - POCKET_RADIUS],
  [1 - POCKET_RADIUS, 1 - POCKET_RADIUS],
];

export const STRIKER_ID = 99;

/** Player 0 shoots from the bottom baseline, player 1 from the top. */
export function baselineY(player: number): number {
  return player === 0 ? 1 - BASELINE_INSET : BASELINE_INSET;
}

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

/** Speed given to the striker for a shot power in 0..1. */
export function shotSpeed(power: number): number {
  return MIN_SHOT_SPEED + clamp01(power) * (MAX_SHOT_SPEED - MIN_SHOT_SPEED);
}

export function makePiece(id: number, type: PieceType, x: number, y: number): Piece {
  const striker = type === 'striker';
  return {
    id,
    type,
    radius: striker ? STRIKER_RADIUS : COIN_RADIUS,
    mass: striker ? STRIKER_MASS : 1,
    x,
    y,
    vx: 0,
    vy: 0,
    pocketed: false,
  };
}

export function isMoving(p: Piece): boolean {
  return p.vx !== 0 || p.vy !== 0;
}

function speedOf(p: Piece): number {
  return Math.sqrt(p.vx * p.vx + p.vy * p.vy);
}

export function isSettled(pieces: readonly Piece[]): boolean {
  return pieces.every((p) => p.pocketed || !isMoving(p));
}

/**
 * Advances every piece by one fixed step and returns the pieces that dropped
 * into a pocket during it.
 */
export function step(pieces: Piece[]): Piece[] {
  const dt = STEP_SECONDS;
  const active = pieces.filter((p) => !p.pocketed);

  for (const p of active) {
    if (!isMoving(p)) continue;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
  }

  for (let i = 0; i < active.length; i++) {
    const a = active[i];
    for (let j = i + 1; j < active.length; j++) {
      const b = active[j];
      if (!isMoving(a) && !isMoving(b)) continue;
      collide(a, b);
    }
  }

  for (const p of active) bounceOffWalls(p);

  const dropped: Piece[] = [];
  for (const p of active) {
    for (const [px, py] of POCKETS) {
      const dx = p.x - px;
      const dy = p.y - py;
      if (dx * dx + dy * dy < POCKET_RADIUS * POCKET_RADIUS) {
        p.pocketed = true;
        p.vx = 0;
        p.vy = 0;
        p.x = px;
        p.y = py;
        dropped.push(p);
        break;
      }
    }
  }

  for (const p of active) {
    if (p.pocketed || !isMoving(p)) continue;
    const speed = speedOf(p);
    const slowed = speed - FRICTION * dt;
    if (slowed <= REST_SPEED) {
      p.vx = 0;
      p.vy = 0;
    } else {
      const scale = slowed / speed;
      p.vx *= scale;
      p.vy *= scale;
    }
  }
  return dropped;
}

function collide(a: Piece, b: Piece): void {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const minDist = a.radius + b.radius;
  const distSq = dx * dx + dy * dy;
  if (distSq >= minDist * minDist || distSq === 0) return;

  const dist = Math.sqrt(distSq);
  const nx = dx / dist;
  const ny = dy / dist;
  const invA = 1 / a.mass;
  const invB = 1 / b.mass;

  // Push the pieces apart so they no longer overlap.
  const overlap = minDist - dist;
  const share = overlap / (invA + invB);
  a.x -= nx * share * invA;
  a.y -= ny * share * invA;
  b.x += nx * share * invB;
  b.y += ny * share * invB;

  // Exchange momentum along the line of centres if they are approaching.
  const approach = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
  if (approach <= 0) return;
  const impulse = ((1 + PIECE_RESTITUTION) * approach) / (invA + invB);
  a.vx -= impulse * invA * nx;
  a.vy -= impulse * invA * ny;
  b.vx += impulse * invB * nx;
  b.vy += impulse * invB * ny;
}

function bounceOffWalls(p: Piece): void {
  const r = p.radius;
  if (p.x < r) {
    p.x = r;
    if (p.vx < 0) p.vx = -p.vx * WALL_RESTITUTION;
  } else if (p.x > 1 - r) {
    p.x = 1 - r;
    if (p.vx > 0) p.vx = -p.vx * WALL_RESTITUTION;
  }
  if (p.y < r) {
    p.y = r;
    if (p.vy < 0) p.vy = -p.vy * WALL_RESTITUTION;
  } else if (p.y > 1 - r) {
    p.y = 1 - r;
    if (p.vy > 0) p.vy = -p.vy * WALL_RESTITUTION;
  }
}

/**
 * Runs [pieces] until everything has stopped (or [maxSeconds] passes) and
 * returns every piece pocketed on the way, in order.
 */
export function simulateToRest(pieces: Piece[], maxSeconds = MAX_SHOT_SECONDS): Piece[] {
  const dropped: Piece[] = [];
  const maxSteps = Math.ceil(maxSeconds / STEP_SECONDS);
  for (let i = 0; i < maxSteps; i++) {
    dropped.push(...step(pieces));
    if (isSettled(pieces)) return dropped;
  }
  for (const p of pieces) {
    p.vx = 0;
    p.vy = 0;
  }
  return dropped;
}
