/**
 * The bot's shot, ported from CarromBot.chooseShot in the phone's carrom game.
 * It lines up cut shots from ghost-ball geometry, simulates the best of them
 * on the real physics, and keeps the one whose outcome scores best. A small
 * aiming error keeps it beatable.
 */

import type { CarromTable, Shot } from './game';
import {
  BASELINE_MAX,
  BASELINE_MIN,
  FRICTION,
  MAX_SHOT_SPEED,
  MIN_SHOT_SPEED,
  POCKETS,
  PIECE_RESTITUTION,
  Piece,
  STRIKER_ID,
  STRIKER_MASS,
  STRIKER_RADIUS,
  baselineY,
  makePiece,
  shotSpeed,
  simulateToRest,
} from './physics';

/** The aiming error the online bot uses, in radians. */
export const BOT_AIM_NOISE = 0.01;

/** Share of the striker's speed along the line of centres that a resting coin picks up. */
const TRANSFER = ((1 + PIECE_RESTITUTION) * STRIKER_MASS) / (STRIKER_MASS + 1);

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

function powerFor(launchSpeed: number): number {
  return (launchSpeed - MIN_SHOT_SPEED) / (MAX_SHOT_SPEED - MIN_SHOT_SPEED);
}

/**
 * Picks the shot for [player]. [random] supplies the tie-break and the aiming
 * error; the server passes a cryptographically random source.
 */
export function chooseShot(
  table: CarromTable,
  player: number,
  aimNoise: number,
  random: () => number,
): Shot {
  const own = player === 0 ? 'white' : 'black';
  const opp = player === 0 ? 'black' : 'white';
  const baseY = baselineY(player);
  const ownPocketed = table.pocketed[player].length;
  const queenCovered = table.queenCoveredBy !== null;
  const active = table.coins.filter((c) => !c.pocketed);

  const strikerFits = (x: number): boolean =>
    active.every((c) => {
      const dx = c.x - x;
      const dy = c.y - baseY;
      const minDist = c.radius + STRIKER_RADIUS;
      return dx * dx + dy * dy >= minDist * minDist;
    });

  const segmentClear = (
    ax: number,
    ay: number,
    bx: number,
    by: number,
    clearance: number,
    ignore: Set<Piece>,
  ): boolean => {
    const dx = bx - ax;
    const dy = by - ay;
    const lenSq = dx * dx + dy * dy;
    if (lenSq === 0) return true;
    for (const c of active) {
      if (ignore.has(c)) continue;
      const t = clamp01(((c.x - ax) * dx + (c.y - ay) * dy) / lenSq);
      const px = ax + dx * t - c.x;
      const py = ay + dy * t - c.y;
      if (px * px + py * py < clearance * clearance) return false;
    }
    return true;
  };

  const ownLeft = active.filter((c) => c.type === own).length;
  const oppLeft = active.filter((c) => c.type === opp).length;
  // Under ICF rules the last coin may only go down once the Queen is covered.
  const lastCoinLocked = ownLeft === 1 && !queenCovered;
  const targets = active.filter(
    (c) => (c.type === own && !lastCoinLocked) || (c.type === 'queen' && ownPocketed > 0),
  );
  const xs: number[] = [];
  for (let i = 0; i <= 12; i++) {
    xs.push(BASELINE_MIN + (i * (BASELINE_MAX - BASELINE_MIN)) / 12);
  }

  const geometric: Array<{ score: number; shot: Shot }> = [];
  for (const t of targets) {
    for (const [px, py] of POCKETS) {
      const toPocketX = px - t.x;
      const toPocketY = py - t.y;
      const pocketDist = Math.sqrt(toPocketX * toPocketX + toPocketY * toPocketY);
      const ux = toPocketX / pocketDist;
      const uy = toPocketY / pocketDist;
      const ghostX = t.x - ux * (t.radius + STRIKER_RADIUS);
      const ghostY = t.y - uy * (t.radius + STRIKER_RADIUS);
      if (!segmentClear(t.x, t.y, px, py, t.radius * 2, new Set([t]))) continue;

      for (const x of xs) {
        if (!strikerFits(x)) continue;
        const ax = ghostX - x;
        const ay = ghostY - baseY;
        const aimDist = Math.sqrt(ax * ax + ay * ay);
        if (aimDist < 0.01) continue;
        const cut = (ax * ux + ay * uy) / aimDist;
        if (cut < 0.35) continue; // thinner than about 70 degrees
        if (!segmentClear(x, baseY, ghostX, ghostY, t.radius + STRIKER_RADIUS, new Set([t]))) continue;
        const angle = Math.atan2(ay, ax);
        // Softest striker speed that still carries the coin into the pocket:
        // friction over both legs plus the momentum handed over at the hit.
        const coinSpeed = Math.sqrt(2 * FRICTION * pocketDist) * 1.25 + 0.1;
        const strikerAtHit = coinSpeed / (TRANSFER * cut);
        const launch = Math.sqrt(strikerAtHit * strikerAtHit + 2 * FRICTION * aimDist);
        const power = powerFor(launch);
        if (power > 1) continue;
        const score = cut * 2 - pocketDist - aimDist * 0.5 + (t.type === 'queen' ? 0.3 : 0);
        geometric.push({ score, shot: { x, angle, power } });
      }
    }
  }
  geometric.sort((a, b) => b.score - a.score);

  const candidates: Shot[] = [];
  for (const g of geometric.slice(0, 30)) {
    for (const boost of [1.0, 1.12, 1.3]) {
      candidates.push({
        x: g.shot.x,
        angle: g.shot.angle,
        power: clamp01(powerFor(shotSpeed(g.shot.power) * boost)),
      });
    }
  }
  // Fallbacks: break shots into the pile from a few spots.
  const centreX =
    active.length === 0 ? 0.5 : active.map((c) => c.x).reduce((a, b) => a + b) / active.length;
  const centreY =
    active.length === 0 ? 0.5 : active.map((c) => c.y).reduce((a, b) => a + b) / active.length;
  for (const x of [0.5, 0.35, 0.65, 0.25, 0.75]) {
    if (!strikerFits(x)) continue;
    for (const power of [0.6, 0.95]) {
      candidates.push({ x, angle: Math.atan2(centreY - baseY, centreX - x), power });
    }
  }
  if (candidates.length === 0) {
    const x = xs.find(strikerFits) ?? 0.5;
    return { x, angle: player === 0 ? -Math.PI / 2 : Math.PI / 2, power: 0.6 };
  }

  let best = candidates[0];
  let bestScore = Number.NEGATIVE_INFINITY;
  for (const shot of candidates) {
    const pieces = table.coins.map((c) => ({ ...c }));
    const striker = makePiece(STRIKER_ID, 'striker', shot.x, baseY);
    const speed = shotSpeed(shot.power);
    striker.vx = Math.cos(shot.angle) * speed;
    striker.vy = Math.sin(shot.angle) * speed;
    const dropped = simulateToRest([...pieces, striker], 12);

    const strikerFoul = dropped.some((p) => p.type === 'striker');
    const ownDown = dropped.filter((p) => p.type === own).length;
    const oppDown = dropped.filter((p) => p.type === opp).length;
    const queenDown = dropped.some((p) => p.type === 'queen');
    let score = ownDown * 10.0 - oppDown * 7.0 + (queenDown ? (ownPocketed > 0 ? 6.0 : -2.0) : 0);
    const lastCoinFoul =
      (ownDown > 0 && ownDown >= ownLeft && !queenCovered) || (oppDown > 0 && oppDown >= oppLeft);
    if (strikerFoul || lastCoinFoul) score -= 15 + ownDown * 10.0;
    score += random() * 0.5;
    if (score > bestScore) {
      bestScore = score;
      best = shot;
    }
  }

  // Human-like aiming error.
  const noise = (random() * 2 - 1) * aimNoise;
  return { x: best.x, angle: best.angle + noise, power: best.power };
}
